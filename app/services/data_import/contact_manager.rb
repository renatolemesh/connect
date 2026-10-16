class DataImport::ContactManager
  def initialize(account)
    @account = account
  end

  def build_contact(params)
    contact = find_or_initialize_contact(params)
    update_contact_attributes(params, contact)
    contact
  end

  def find_or_initialize_contact(params)
    contact = find_existing_contact(params)
    contact_params = params.slice(:email, :identifier, :phone_number)
    contact_params[:phone_number] = format_phone_number(contact_params[:phone_number]) if contact_params[:phone_number].present?
    contact ||= @account.contacts.new(contact_params)
    contact
  end

  def find_existing_contact(params)
    contact = find_contact_by_identifier(params)
    contact ||= find_contact_by_email(params)
    contact ||= find_contact_by_phone_number(params)

    update_contact_with_merged_attributes(params, contact) if contact.present? && contact.valid?
    contact
  end

  def find_contact_by_identifier(params)
    return unless params[:identifier]

    @account.contacts.find_by(identifier: params[:identifier])
  end

  def find_contact_by_email(params)
    return unless params[:email]

    @account.contacts.from_email(params[:email])
  end

  def find_contact_by_phone_number(params)
    return unless params[:phone_number]

    @account.contacts.find_by(phone_number: format_phone_number(params[:phone_number]))
  end

  # Pais assumido para numero que chega sem DDI. Todas as instalacoes sao do Brasil;
  # vazio desliga a inferencia e volta ao comportamento antigo (so prefixa "+").
  DEFAULT_PHONE_COUNTRY = ENV.fetch('DEFAULT_PHONE_COUNTRY', 'BR').presence&.upcase&.to_sym

  # Planilha e WhatsApp entregam o numero com espaco, parentese, hifen, caractere
  # invisivel e, muitas vezes, sem o 55. O codigo antigo so prefixava "+", entao
  # "(41) 99127-1309" virava +41991271309 — Suica — e passava na validacao.
  #
  # A ordem importa: primeiro tenta ler como numero nacional do pais padrao, so
  # depois como internacional. Na ordem inversa, DDD que coincide com codigo de
  # pais muda de pais: 51 987654321 (Porto Alegre) vira um celular do Peru.
  # Numero com "+" explicito e sempre lido como internacional.
  def format_phone_number(phone_number)
    raw = phone_number.to_s.strip
    digits = raw.gsub(/\D/, '')
    return raw if digits.blank?

    if raw.start_with?('+')
      valid_e164("+#{digits}") || "+#{digits}"
    else
      valid_e164(digits, DEFAULT_PHONE_COUNTRY) || valid_e164("+#{digits}") || "+#{digits}"
    end
  end

  def update_contact_with_merged_attributes(params, contact)
    contact.identifier = params[:identifier] if params[:identifier].present?
    contact.email = params[:email] if params[:email].present?
    contact.phone_number = format_phone_number(params[:phone_number]) if params[:phone_number].present?
    update_contact_attributes(params, contact)
    contact.save
  end

  private

  def valid_e164(number, country = nil)
    return nil if country.nil? && !number.start_with?('+')

    parsed = country ? TelephoneNumber.parse(number, country) : TelephoneNumber.parse(number)
    parsed.valid? ? parsed.e164_number : nil
  end

  def update_contact_attributes(params, contact)
    contact.name = params[:name] if params[:name].present?
    contact.additional_attributes ||= {}
    contact.additional_attributes[:company_name] = params[:company] if params[:company].present?
    contact.additional_attributes[:city] = params[:city] if params[:city].present?
    contact.assign_attributes(custom_attributes: contact.custom_attributes.merge(params.except(:identifier, :email, :name, :phone_number)))
  end
end
