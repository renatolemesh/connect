# Reenvia automaticamente mensagens que falharam no envio, respeitando a natureza
# do erro devolvido pelo provedor.
#
# O reenvio em si repete o que o botão "Reenviar" faz (ver claim_message_retry em
# Api::V1::Accounts::Conversations::MessagesController), com uma diferença: o botão
# zera content_attributes inteiro, e aqui o contador de tentativas precisa sobreviver
# entre as rodadas. Messages::StatusUpdateService já limpa só o external_error, então
# basta não apagar o resto.
class Whatsapp::AutoRetryService
  def initialize(setting, dry_run: false)
    @setting = setting
    @account = setting.account
    @dry_run = dry_run
    @summary = Hash.new(0)
    @summary[:skipped_by_reason] = Hash.new(0)
  end

  def perform
    candidates.find_each do |message|
      break if @summary[:retried] >= @setting.max_per_run

      evaluate(message)
    end
    finish
  end

  private

  attr_reader :setting, :account, :summary

  def finish
    result = {
      'ran_at' => Time.current.iso8601,
      'dry_run' => @dry_run,
      'examined' => summary[:examined],
      'retried' => summary[:retried],
      'skipped' => summary[:skipped],
      'skipped_by_reason' => summary[:skipped_by_reason].transform_keys(&:to_s)
    }
    setting.update!(last_run_at: Time.current, last_run_summary: result) unless @dry_run
    result
  end

  def candidates
    scope = account.messages
                   .where(status: :failed, message_type: :outgoing)
                   .where('messages.created_at > ?', setting.widest_max_age_hours.hours.ago)
                   .order(created_at: :asc)
    inbox_ids = resolved_inbox_ids
    inbox_ids.present? ? scope.where(inbox_id: inbox_ids) : scope.none
  end

  # Sem inbox_ids configurado, a rotina age só nas caixas de WhatsApp oficial —
  # que é o caso de uso pedido. Configurar inbox_ids permite estender para as
  # caixas Channel::Api (canal não oficial), onde os erros são outros.
  def resolved_inbox_ids
    configured = setting.inbox_ids
    return configured if configured.present?

    account.inboxes.where(channel_type: 'Channel::Whatsapp').pluck(:id)
  end

  def evaluate(message)
    summary[:examined] += 1
    reason = skip_reason(message)
    if reason
      summary[:skipped] += 1
      summary[:skipped_by_reason][reason] += 1
      return
    end
    retry_message(message)
  end

  def skip_reason(message)
    error = message.external_error.to_s
    return :sem_erro if error.blank?
    return :codigo_permanente if matches_any?(error, setting.never_codes)

    group = group_for(error)
    return :codigo_fora_das_regras if group.nil?
    return :tentativas_esgotadas if attempts(message) >= setting.max_attempts
    return :fora_da_janela if too_old?(message, group)
    return :aguardando_intervalo unless due?(message, group)

    nil
  end

  def group_for(error)
    WhatsappRetrySetting::GROUPS.find do |group|
      matches_any?(error, Array(setting.group_config(group)['codes']))
    end
  end

  # Entrada só de dígitos casa com o número isolado em qualquer posição do texto —
  # cobre "131049: ...", "(#131000) Something went wrong" e "500 Internal Server Error".
  # Entrada com letras casa como trecho literal, sem diferenciar maiúsculas.
  def matches_any?(error, entries)
    Array(entries).any? { |entry| matches?(error, entry.to_s) }
  end

  def matches?(error, entry)
    return false if entry.blank?

    if entry.match?(/\A\d+\z/)
      error.match?(/(?<!\d)#{Regexp.escape(entry)}(?!\d)/)
    else
      error.downcase.include?(entry.downcase)
    end
  end

  def retry_state(message)
    message.content_attributes.is_a?(Hash) ? (message.content_attributes['auto_retry'] || {}) : {}
  end

  def attempts(message)
    retry_state(message)['count'].to_i
  end

  def too_old?(message, group)
    max_age = setting.group_config(group)['max_age_hours'].to_i
    return false if max_age.zero?

    message.created_at < max_age.hours.ago
  end

  def due?(message, group)
    delays = Array(setting.group_config(group)['delays_minutes']).map(&:to_i)
    return false if delays.empty?

    wait = delays[attempts(message)] || delays.last
    reference(message) + wait.minutes <= Time.current
  end

  # Depois da primeira tentativa automática o relógio corre a partir dela. Antes
  # disso, a partir do momento em que a mensagem foi marcada como falha.
  def reference(message)
    last_at = retry_state(message)['last_at']
    last_at.present? ? Time.zone.parse(last_at) : message.updated_at
  end

  def retry_message(message)
    if @dry_run
      summary[:retried] += 1
      return
    end

    return unless claim(message)

    ::SendReplyJob.perform_later(message.id)
    summary[:retried] += 1
    Rails.logger.info("[auto_retry] reenviando message=#{message.id} inbox=#{message.inbox_id} tentativa=#{attempts(message)}")
  end

  def claim(message)
    message.with_lock do
      next false unless message.failed?

      previous_error = message.external_error.to_s
      state = { 'count' => attempts(message) + 1, 'last_at' => Time.current.iso8601, 'last_error' => previous_error[0, 120] }
      Messages::StatusUpdateService.new(message, 'sent').perform
      attrs = { content_attributes: message.content_attributes.merge('auto_retry' => state) }
      attrs[:source_id] = nil unless message.inbox.api? || message.inbox.web_widget?
      message.update!(attrs)
      true
    end
  end
end
