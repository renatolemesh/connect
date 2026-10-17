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

  # Contato que ja existe so tem preenchido o que estiver vazio. Antes, qualquer valor
  # do CSV substituia o atual: uma lista que repetia o telefone de outra empresa trocou
  # o e-mail e a empresa do contato 6949 em 07/10, sem aviso.
  def update_contact_with_merged_attributes(params, contact)
    contact.identifier = params[:identifier] if contact.identifier.blank? && params[:identifier].present?
    contact.email = params[:email] if contact.email.blank? && params[:email].present?
    contact.phone_number = format_phone_number(params[:phone_number]) if contact.phone_number.blank? && params[:phone_number].present?
    update_contact_attributes(params, contact)
    contact.save
  end

  private

  def valid_e164(number, country = nil)
    return nil if country.nil? && !number.start_with?('+')

    parsed = country ? TelephoneNumber.parse(number, country) : TelephoneNumber.parse(number)
    parsed.valid? ? parsed.e164_number : nil
  end

  # Roda tanto para contato novo quanto para o existente; no novo tudo esta vazio, entao
  # "so preenche o vazio" equivale a preencher tudo.
  def update_contact_attributes(params, contact)
    contact.name = params[:name] if placeholder_name?(contact.name) && params[:name].present?
    contact.additional_attributes ||= {}
    fill_attribute(contact.additional_attributes, 'company_name', params[:company])
    fill_attribute(contact.additional_attributes, 'city', params[:city])
    extra = params.except(:identifier, :email, :name, :phone_number)
    contact.assign_attributes(custom_attributes: extra.merge(contact.custom_attributes.compact_blank))
  end

  # Nome com "~" na frente e o que o canal de WhatsApp grava quando so conhece o nome de
  # exibicao ou o proprio numero ("~+553195818126"). Nao e um nome que alguem escolheu,
  # entao o do CSV pode substituir.
  def placeholder_name?(name)
    name.blank? || name.start_with?('~')
  end

  # additional_attributes e jsonb puro: carregado do banco tem chave string, montado em
  # memoria pode ter chave simbolo. Le as duas e grava com string para nao duplicar.
  def fill_attribute(attributes, key, value)
    return if value.blank?
    return if attributes[key].present? || attributes[key.to_sym].present?

    attributes.delete(key.to_sym)
    attributes[key] = value
  end
end
