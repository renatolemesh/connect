class V2::Reports::ConversationBacklogBuilder
  include DateRangeHelper
  include TimezoneHelper

  RESOLVED_EVENT = 'conversation_resolved'.freeze

  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  # Every other report measures flow — how much came in, how much went out. This one
  # measures stock: how many conversations were still open at the end of each day.
  # A conversation counts as closed from its first resolution onwards; reopenings are
  # not added back, which is why this tracks the backlog rather than the status column.
  def build
    return [] if range.blank?

    opened = opened_per_day
    closed = closed_per_day
    running = backlog_at_range_start

    days.map do |day|
      running += opened.fetch(day, 0) - closed.fetch(day, 0)
      { timestamp: day.in_time_zone(timezone).to_i, value: running }
    end
  end

  private

  def days
    @days ||= opened_per_day.keys.sort
  end

  def opened_per_day
    @opened_per_day ||= conversation_filter.conversations
                                           .where(created_at: range)
                               .group_by_period(:day, :created_at, range: range, default_value: 0, time_zone: timezone)
                               .count
  end

  def closed_per_day
    @closed_per_day ||= ReportingEvent.unscoped
                                      .from(first_resolutions, :reporting_events)
                                      .where(created_at: range)
                                      .group_by_period(:day, :created_at, range: range, default_value: 0, time_zone: timezone)
                                      .count
  end

  # One row per conversation, holding the moment it was first resolved.
  def first_resolutions
    conversation_filter.apply(ReportingEvent.where(account_id: account.id, name: RESOLVED_EVENT))
                       .group(:conversation_id)
                  .select('conversation_id, MIN(created_at) AS created_at')
  end

  # Conversations opened before the window minus those already resolved before it.
  # A resolution always follows its conversation's creation, so the difference is
  # exactly what was still open when the window started.
  def backlog_at_range_start
    opened_before = conversation_filter.conversations.where(conversations: { created_at: ...range.begin }).count
    resolved_before = conversation_filter.apply(ReportingEvent.where(account_id: account.id, name: RESOLVED_EVENT))
                                         .where(created_at: ...range.begin)
                                    .distinct
                                    .count(:conversation_id)
    opened_before - resolved_before
  end

  def conversation_filter
    @conversation_filter ||= V2::Reports::ConversationFilter.new(account, params)
  end

  def timezone
    @timezone ||= timezone_name_from_offset(params[:timezone_offset])
  end
end
