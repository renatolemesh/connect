# Relatorios acrescentados ao fork: percentis, backlog, funil, motivos de
# encerramento e quebra por caixa de entrada.
#
# Vivem aqui, e nao no controller, porque as cinco acoes somadas passavam o
# ReportsController do limite de Metrics/ClassLength. Segue a mesma convencao de
# ReportsHelper e HeatmapHelper, que o controller ja inclui.
module Api::V2::Accounts::CustomReportsHelper
  def response_time_percentiles
    builder = V2::Reports::ResponseTimePercentilesBuilder.new(
      account: Current.account,
      params: response_time_percentiles_params
    )
    render json: builder.build
  end

  def conversation_backlog
    builder = V2::Reports::ConversationBacklogBuilder.new(
      account: Current.account,
      params: conversation_backlog_params
    )
    render json: builder.build
  end

  def conversation_funnel
    builder = V2::Reports::ConversationFunnelBuilder.new(
      account: Current.account,
      params: date_range_params
    )
    render json: builder.build
  end

  def resolution_reasons
    builder = V2::Reports::ResolutionReasonsBuilder.new(
      account: Current.account,
      params: date_range_params
    )
    render json: builder.build
  end

  def inbox_status_breakdown
    builder = V2::Reports::InboxStatusBreakdownBuilder.new(
      account: Current.account,
      params: date_range_params
    )
    render json: builder.build
  end

  private

  def response_time_percentiles_params
    {
      since: params[:since],
      until: params[:until],
      business_hours: params[:business_hours]
    }.merge(conversation_filter_params)
  end

  def date_range_params
    { since: params[:since], until: params[:until] }.merge(conversation_filter_params)
  end

  # Recorte por time, caixa, agente e etiqueta -- ver V2::Reports::ConversationFilter.
  def conversation_filter_params
    params.permit(:team_id, :inbox_id, :assigned_agent_id, :label_list).to_h.symbolize_keys
  end

  def conversation_backlog_params
    {
      since: params[:since],
      until: params[:until],
      timezone_offset: params[:timezone_offset]
    }.merge(conversation_filter_params)
  end
end
