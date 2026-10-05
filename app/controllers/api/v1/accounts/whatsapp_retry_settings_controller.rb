class Api::V1::Accounts::WhatsappRetrySettingsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :set_setting

  def show; end

  def update
    @setting.update!(permitted_params)
    render :show
  end

  # Simulação: percorre as mesmas regras e devolve o que seria reenviado agora,
  # sem tocar em nenhuma mensagem.
  def preview
    render json: Whatsapp::AutoRetryService.new(@setting, dry_run: true).perform
  end

  private

  def set_setting
    @setting = Current.account.whatsapp_retry_setting || Current.account.create_whatsapp_retry_setting!
  end

  def permitted_params
    params.require(:whatsapp_retry_setting).permit(:enabled, config: {})
  end
end
