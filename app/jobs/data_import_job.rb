# TODO: logic is written tailored to contact import since its the only import available
# let's break this logic and clean this up in future

class DataImportJob < ApplicationJob
  queue_as :low
  retry_on ActiveStorage::FileNotFoundError, wait: 1.minute, attempts: 3

  LABELS_DELIMITER = ','.freeze
  LABELS_CONTEXT = 'labels'.freeze
  CONTACT_TAGGABLE_TYPE = 'Contact'.freeze

  def perform(data_import)
    @data_import = data_import
    @contact_manager = DataImport::ContactManager.new(@data_import.account)
    begin
      process_import_file
      send_import_notification_to_admin
    rescue CSV::MalformedCSVError => e
      handle_csv_error(e)
    end
  end

  private

  def process_import_file
    @data_import.update!(status: :processing)
    contacts, rejected_contacts = parse_csv_and_build_contacts

    import_contacts(contacts)
    update_data_import_status(contacts.length, rejected_contacts.length)
    save_failed_records_csv(rejected_contacts)
  end

  def parse_csv_and_build_contacts
    contacts = []
    rejected_contacts = []
    @warnings = []
    seen_emails = {}
    seen_phones = {}

    parser.each_row.with_index(2) do |row, line|
      next if row.to_h.values.all?(&:blank?)

      deduplicate_in_file(row, line, seen_emails, seen_phones)
      classify_row(row, contacts, rejected_contacts)
    end

    [contacts, rejected_contacts]
  end

  def classify_row(row, contacts, rejected_contacts)
    # Telefone repetido no proprio arquivo vira rejeicao: dois contatos nao podem
    # dividir o mesmo numero, e sem indice unico o banco aceitaria os dois calado.
    return append_rejected_contact(row, nil, rejected_contacts, row.delete('__duplicate_phone__').last) if row['__duplicate_phone__']

    row_hash = row.to_h.with_indifferent_access
    labels = extract_labels(row_hash)
    invalid_labels = labels.map(&:downcase) - approved_labels
    return append_label_error(row, invalid_labels, rejected_contacts) if invalid_labels.present?

    contact = @contact_manager.build_contact(row_hash.except(:labels))
    if contact.valid?
      contacts << { contact: contact, labels: labels }
    else
      append_rejected_contact(row, contact, rejected_contacts)
    end
  end

  def extract_labels(row_hash)
    row_hash[:labels].to_s.split(LABELS_DELIMITER).map(&:strip).reject(&:blank?)
  end

  def deduplicate_in_file(row, line, seen_emails, seen_phones)
    deduplicate_email(row, line, seen_emails)
    deduplicate_phone(row, line, seen_phones)
  end

  # E-mail repetido: o indice unico uniq_email_per_account_contact somado a
  # on_duplicate_key_ignore descartaria a segunda linha inteira, em silencio, e o
  # telefone dela se perderia. Mantem a linha e esvazia so o e-mail.
  def deduplicate_email(row, line, seen_emails)
    email = row['email'].to_s.downcase.presence
    return if email.blank?

    if seen_emails.key?(email)
      @warnings << "linha #{line}: e-mail #{email} repete a linha #{seen_emails[email]}; importada sem e-mail"
      row['email'] = nil
    else
      seen_emails[email] = line
    end
  end

  # Compara pela forma normalizada: "41991271309" e "5541991271309" sao o mesmo numero.
  def deduplicate_phone(row, line, seen_phones)
    return if row['phone_number'].blank?

    phone = @contact_manager.format_phone_number(row['phone_number'])
    if seen_phones.key?(phone)
      row['__duplicate_phone__'] = "telefone repete a linha #{seen_phones[phone]}"
    else
      seen_phones[phone] = line
    end
  end

  def append_rejected_contact(row, contact, rejected_contacts, reason = nil)
    row['errors'] = reason || contact.errors.full_messages.join(', ')
    rejected_contacts << row
  end

  def import_contacts(contacts_with_labels)
    contacts = contacts_with_labels.pluck(:contact)
    # <struct ActiveRecord::Import::Result failed_instances=[], num_inserts=1, ids=[444, 445], results=[]>
    Contact.import(contacts, synchronize: contacts, on_duplicate_key_ignore: true, track_validation_failures: true, validate: true, batch_size: 1000)
    apply_labels_to_contacts(contacts_with_labels)
  end

  def apply_labels_to_contacts(contacts_with_labels)
    taggings = taggings_for_contacts(contacts_with_labels)
    return if taggings.blank?

    ActsAsTaggableOn::Tagging.import(%i[tag_id taggable_type taggable_id context created_at],
                                     taggings, on_duplicate_key_ignore: true, validate: false, batch_size: 1000)
  end

  def taggings_for_contacts(contacts_with_labels)
    tag_lookup = tags_by_label_name(contacts_with_labels)
    taggings = contacts_with_labels.flat_map do |item|
      contact = contact_for_label_import(item[:contact])
      labels = item[:labels].map(&:downcase).uniq
      next [] if contact&.id.blank?

      labels.map do |label|
        [tag_lookup[label].id, CONTACT_TAGGABLE_TYPE, contact.id, LABELS_CONTEXT]
      end
    end.uniq

    reject_existing_taggings(taggings).map { |tagging| tagging + [Time.zone.now] }
  end

  def reject_existing_taggings(taggings)
    tag_ids = taggings.map { |tag_id, _taggable_type, _taggable_id, _context| tag_id }
    taggable_ids = taggings.map { |_tag_id, _taggable_type, taggable_id, _context| taggable_id }
    existing_taggings = ActsAsTaggableOn::Tagging
                        .where(context: LABELS_CONTEXT, taggable_type: CONTACT_TAGGABLE_TYPE,
                               taggable_id: taggable_ids, tag_id: tag_ids)
                        .pluck(:tag_id, :taggable_id)
                        .index_with(true)

    taggings.reject do |tag_id, _taggable_type, taggable_id, _context|
      existing_taggings[[tag_id, taggable_id]]
    end
  end

  def contact_for_label_import(contact)
    return contact if contact.id.present?

    key = contact_identity_key(contact)
    return if key.blank?

    imported_contact(contact)
  end

  def contact_identity_key(contact)
    contact.identifier.presence || contact.email.presence || contact.phone_number.presence
  end

  def imported_contact(contact)
    return @data_import.account.contacts.find_by(identifier: contact.identifier) if contact.identifier.present?
    return @data_import.account.contacts.from_email(contact.email) if contact.email.present?

    @data_import.account.contacts.find_by(phone_number: contact.phone_number) if contact.phone_number.present?
  end

  def tags_by_label_name(contacts_with_labels)
    labels = contacts_with_labels.flat_map { |item| item[:labels] }.map(&:downcase).uniq

    ActsAsTaggableOn::Tag.find_or_create_all_with_like_by_name(labels).index_by { |tag| tag.name.downcase }
  end

  def approved_labels
    @approved_labels ||= @data_import.account.labels.pluck(:title)
  end

  def append_label_error(row, labels, rejected_contacts)
    row['errors'] = "Unknown labels: #{labels.join(', ')}"
    rejected_contacts << row
  end

  def update_data_import_status(processed_records, rejected_records)
    @data_import.update!(status: :completed, processed_records: processed_records,
                         total_records: processed_records + rejected_records,
                         processing_errors: import_report)
  end

  # Fica em processing_errors para quem for conferir depois saber como o arquivo foi
  # lido — separador e encoding adivinhados — e o que foi ajustado em silencio.
  def import_report
    lines = ["separador detectado: #{parser.delimiter.inspect}", "encoding: #{parser.encoding_used}"]
    lines += Array(@warnings)
    lines.join("\n")
  end

  def save_failed_records_csv(rejected_contacts)
    csv_data = generate_csv_data(rejected_contacts)
    return if csv_data.blank?

    @data_import.failed_records.attach(io: StringIO.new(csv_data), filename: "#{Time.zone.today.strftime('%Y%m%d')}_contacts.csv",
                                       content_type: 'text/csv')
  end

  def generate_csv_data(rejected_contacts)
    headers = csv_headers
    headers << 'errors'
    return if rejected_contacts.blank?

    CSV.generate do |csv|
      csv << headers
      rejected_contacts.each do |record|
        csv << record
      end
    end
  end

  def handle_csv_error(error) # rubocop:disable Lint/UnusedMethodArgument
    @data_import.update!(status: :failed)
    send_import_failed_notification_to_admin
  end

  def send_import_notification_to_admin
    AdministratorNotifications::AccountNotificationMailer.with(account: @data_import.account).contact_import_complete(@data_import).deliver_later
  end

  def send_import_failed_notification_to_admin
    AdministratorNotifications::AccountNotificationMailer.with(account: @data_import.account).contact_import_failed.deliver_later
  end

  def csv_headers
    parser.headers
  end

  def parser
    @parser ||= with_import_file { |file| DataImport::CsvParser.new(file.read) }
  end

  def with_import_file
    temp_dir = Rails.root.join('tmp/imports')
    FileUtils.mkdir_p(temp_dir)

    @data_import.import_file.open(tmpdir: temp_dir) do |file|
      file.binmode
      yield file
    end
  end
end
