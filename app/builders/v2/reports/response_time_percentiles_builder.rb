class V2::Reports::ResponseTimePercentilesBuilder
  include DateRangeHelper

  attr_reader :account, :params

  # Averages hide the tail: the customer who waited four hours disappears into a
  # mean pulled down by fast replies. These percentiles expose that tail.
  METRICS = {
    first_response_time: 'first_response',
    resolution_time: 'conversation_resolved'
  }.freeze

  PERCENTILES = { p50: 0.5, p90: 0.9, p95: 0.95 }.freeze

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    rows = fetch_percentiles.index_by(&:name)
    METRICS.transform_values { |event_name| build_metric(rows[event_name]) }
  end

  private

  def fetch_percentiles
    conversation_filter
      .apply(ReportingEvent.where(account_id: account.id, name: METRICS.values))
      .where(range_condition)
      .group(:name)
      .select(:name, percentile_statements, "COUNT(#{value_column}) AS events_count")
  end

  def percentile_statements
    PERCENTILES.map do |label, fraction|
      "PERCENTILE_CONT(#{fraction}) WITHIN GROUP (ORDER BY #{value_column}) AS #{label}"
    end.join(', ')
  end

  # Boolean cast keeps this to one of two literals, never user input.
  def value_column
    @value_column ||= ActiveModel::Type::Boolean.new.cast(params[:business_hours]) ? 'value_in_business_hours' : 'value'
  end

  def conversation_filter
    @conversation_filter ||= V2::Reports::ConversationFilter.new(account, params)
  end

  def range_condition
    range.present? ? { created_at: range } : {}
  end

  def build_metric(row)
    return empty_metric if row.nil?

    PERCENTILES.keys.index_with { |label| row[label] }
               .merge(count: row.events_count)
  end

  def empty_metric
    PERCENTILES.keys.index_with { |_label| nil }.merge(count: 0)
  end
end
