# == Schema Information
#
# Table name: whatsapp_retry_settings
#
#  id               :bigint           not null, primary key
#  config           :jsonb            not null
#  enabled          :boolean          default(FALSE), not null
#  last_run_at      :datetime
#  last_run_summary :jsonb            not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#
# Indexes
#
#  index_whatsapp_retry_settings_on_account_id  (account_id) UNIQUE
#
class WhatsappRetrySetting < ApplicationRecord
  # Dois grupos de erro, porque a natureza da falha muda o intervalo que faz sentido:
  #
  # - transient: a chamada não chegou a ser aceita pela Meta (500, timeout, 131000).
  #   Reenviar em minutos tem chance real de passar.
  # - slow: a Meta aceitou e depois recusou a entrega por limite por destinatário
  #   (131049). A janela reabre sozinha ao longo de horas; reenviar rápido só repete
  #   a recusa, então o intervalo é medido em horas.
  #
  # never_codes são recusas definitivas — número que não recebe WhatsApp (131026),
  # janela de 24h vencida (131047), experimento da Meta (130472), problema de
  # cobrança (131042) e erros de template/payload. Reenviar nunca vai entregar.
  DEFAULT_CONFIG = {
    'max_attempts' => 3,
    'max_per_run' => 50,
    'inbox_ids' => [],
    'transient' => {
      'codes' => ['131000', '500', '502', '503', '504', 'Timed out', 'Temporary failure in name resolution'],
      'delays_minutes' => [5, 30, 180],
      'max_age_hours' => 24
    },
    'slow' => {
      'codes' => ['131049'],
      'delays_minutes' => [720, 1440, 2880],
      'max_age_hours' => 96
    },
    'never_codes' => %w[131026 131047 131051 130472 131042 400 132000 132001 132005 132007 132012 132015 132016 132068 132069]
  }.freeze

  GROUPS = %w[transient slow].freeze

  belongs_to :account
  validates :account_id, uniqueness: true
  validate :validate_config_shape

  def effective_config
    DEFAULT_CONFIG.deep_merge(config.presence || {})
  end

  def max_attempts
    effective_config['max_attempts'].to_i.clamp(1, 10)
  end

  def max_per_run
    effective_config['max_per_run'].to_i.clamp(1, 500)
  end

  def inbox_ids
    Array(effective_config['inbox_ids']).map(&:to_i).reject(&:zero?)
  end

  def never_codes
    Array(effective_config['never_codes']).map(&:to_s)
  end

  def group_config(group)
    effective_config[group] || {}
  end

  # A janela mais larga entre os grupos — serve para a consulta inicial de candidatas.
  def widest_max_age_hours
    GROUPS.map { |g| group_config(g)['max_age_hours'].to_i }.max
  end

  private

  def validate_config_shape
    return if config.blank?

    errors.add(:config, 'deve ser um objeto') and return unless config.is_a?(Hash)

    GROUPS.each { |group| validate_group(group) }
  end

  def validate_group(group)
    group_cfg = config[group]
    return if group_cfg.blank?

    delays = group_cfg['delays_minutes']
    return if delays.blank?

    return if delays.is_a?(Array) && delays.all? { |d| d.to_i.positive? }

    errors.add(:config, "#{group}.delays_minutes deve ser uma lista de minutos positivos")
  end
end
