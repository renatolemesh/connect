class Whatsapp::AutoRetryFailedMessagesJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    WhatsappRetrySetting.where(enabled: true).find_each do |setting|
      run_for(setting)
    end
  end

  private

  def run_for(setting)
    summary = Whatsapp::AutoRetryService.new(setting).perform
    return if summary['retried'].to_i.zero? && summary['examined'].to_i.zero?

    Rails.logger.info("[auto_retry] account=#{setting.account_id} #{summary.except('skipped_by_reason')}")
  rescue StandardError => e
    Rails.logger.error("[auto_retry] erro na account=#{setting.account_id}: #{e.message}")
    ChatwootExceptionTracker.new(e, account: setting.account).capture_exception
  end
end
