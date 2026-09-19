class V2::Reports::ConversationFunnelBuilder
  include DateRangeHelper

  RESOLVED_EVENT = 'conversation_resolved'.freeze

  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  # Stages of the same cohort: the conversations opened inside the window, followed
  # through to a reply, a resolution and a rating.
  #
  # These stages do not strictly shrink. A conversation can be resolved with no agent
  # reply at all — closed by a bot or closed unanswered — so `resolved` may exceed
  # `answered`. That gap is the point of the report, so it is reported rather than
  # smoothed over: `unanswered` and `resolved_without_answer` name it directly.
  def build
    {
      received: received_count,
      answered: answered_count,
      resolved: resolved_count,
      rated: rated_count,
      unanswered: received_count - answered_count,
      resolved_without_answer: resolved_without_answer_count
    }
  end

  private

  def cohort
    @cohort ||= V2::Reports::ConversationFilter.new(account, params).conversations.where(range_condition)
  end

  def range_condition
    range.present? ? { created_at: range } : {}
  end

  def received_count
    @received_count ||= cohort.count
  end

  def answered_count
    @answered_count ||= cohort.where.not(first_reply_created_at: nil).count
  end

  def resolved_conversation_ids
    ReportingEvent.where(account_id: account.id, name: RESOLVED_EVENT).select(:conversation_id)
  end

  def resolved_count
    @resolved_count ||= cohort.where(id: resolved_conversation_ids).count
  end

  def resolved_without_answer_count
    cohort.where(id: resolved_conversation_ids, first_reply_created_at: nil).count
  end

  def rated_count
    CsatSurveyResponse.where(account_id: account.id, conversation_id: cohort.select(:id)).count
  end
end
