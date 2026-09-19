class V2::Reports::ResolutionReasonsBuilder
  include DateRangeHelper

  RESOLVED_EVENT = 'conversation_resolved'.freeze

  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  # Chatwoot has no "resolution reason" field, so the labels carried by a resolved
  # conversation stand in for it. That substitution is only worth anything alongside
  # its coverage: an account that labels 15% of its closures has a ranking describing
  # 15% of reality. `unlabelled` reports that share instead of hiding it.
  #
  # A conversation can carry several labels, so the per-label counts add up to more
  # than `labelled`. They count (resolution, label) pairs, not resolutions.
  def build
    labelled = labelled_resolutions_count

    {
      total: total_resolutions_count,
      labelled: labelled,
      unlabelled: total_resolutions_count - labelled,
      labels: label_counts
    }
  end

  private

  def resolutions
    @resolutions ||= V2::Reports::ConversationFilter.new(account, params)
                                                    .apply(ReportingEvent.where(account_id: account.id, name: RESOLVED_EVENT))
                                                    .where(range_condition)
  end

  def range_condition
    range.present? ? { created_at: range } : {}
  end

  def total_resolutions_count
    @total_resolutions_count ||= resolutions.count
  end

  def labelled_resolutions_count
    resolutions.where(conversation_id: labelled_conversation_ids).count
  end

  def labelled_conversation_ids
    ActsAsTaggableOn::Tagging.where(taggable_type: 'Conversation', context: 'labels').select(:taggable_id)
  end

  def label_counts
    resolutions
      .joins(conversation: { taggings: :tag })
      .where(taggings: { taggable_type: 'Conversation', context: 'labels' })
      .group('tags.name')
      .order(Arel.sql('COUNT(*) DESC'))
      .count
      .map { |name, count| { name: name, count: count } }
  end
end
