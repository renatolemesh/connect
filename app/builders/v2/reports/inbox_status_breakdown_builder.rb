# Breaks the period's conversations down by inbox and status.
#
# Grouping by channel type collapses every inbox that shares a channel into a
# single row -- five distinct "Channel::Api" inboxes become one meaningless
# line -- so this builder keys on the inbox itself and keeps the channel type
# only as a label.
class V2::Reports::InboxStatusBreakdownBuilder
  include DateRangeHelper

  pattr_initialize [:account!, :params!]

  STATUSES = %w[open pending snoozed resolved].freeze

  def build
    counts = conversations_by_inbox_and_status

    rows = account.inboxes.map { |inbox| build_inbox_stats(inbox, counts[inbox.id] || {}) }
    # Com recorte ativo, as caixas fora dele so acrescentariam linhas zeradas.
    rows = rows.select { |row| row[:total].positive? } if conversation_filter.active?
    rows.sort_by { |row| -row[:total] }
  end

  private

  def conversations_by_inbox_and_status
    conversation_filter.conversations
                       .where(created_at: range)
                       .group(:inbox_id, :status)
           .count
           .each_with_object({}) do |((inbox_id, status), count), grouped|
      grouped[inbox_id] ||= {}
      grouped[inbox_id][status.to_s] = count
    end
  end

  def conversation_filter
    @conversation_filter ||= V2::Reports::ConversationFilter.new(account, params)
  end

  def build_inbox_stats(inbox, status_counts)
    counts = STATUSES.to_h { |status| [status.to_sym, status_counts[status] || 0] }

    {
      id: inbox.id,
      name: inbox.name,
      channel_type: inbox.channel_type,
      **counts,
      total: counts.values.sum
    }
  end
end
