class Notification::PushNotificationJob < ApplicationJob
  queue_as :default

  def perform(notification)
    # Idioma da conta; sem isso sai no padrao do servidor (en).
    I18n.with_locale(notification.account.locale) do
      Notification::PushNotificationService.new(notification: notification).perform
    end
  end
end
