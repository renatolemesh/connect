# Recorte do relatorio de conversas pelos atributos da conversa: time, caixa de
# entrada, agente atribuido e etiqueta -- os mesmos que o relatorio de SLA ja filtra.
#
# O recorte vale pelo estado ATUAL da conversa, nao pelo estado na hora do evento.
# Uma conversa que passou do time Suporte para o Comercial leva todo o historico
# (mensagens, primeira resposta, resolucao) para o Comercial. E a mesma semantica
# do relatorio por time que ja existe (`team.conversations`, `team.messages`).
#
# Mensagens e reporting_events sao filtrados pela conversa a que pertencem, e nao
# por colunas proprias: `reporting_events.user_id` e quem executou a acao, o que
# nao responde "o que aconteceu nas conversas do agente X".
class V2::Reports::ConversationFilter
  attr_reader :account, :params

  def initialize(account, params)
    @account = account
    @params = params || {}
  end

  def active?
    conditions.present? || label.present?
  end

  # Para relacoes cuja tabela base e `conversations`.
  def apply_to_conversations(relation)
    return relation unless active?

    relation = relation.where(conversations: conditions) if conditions.present?
    relation = relation.where(conversations: { id: labelled_conversation_ids }) if label.present?
    relation
  end

  # Para relacoes com uma coluna apontando para a conversa (mensagens, reporting_events).
  def apply(relation, column = :conversation_id)
    return relation unless active?

    relation.where(column => conversations.select(:id))
  end

  def conversations
    apply_to_conversations(account.conversations)
  end

  private

  def conditions
    @conditions ||= {
      team_id: params[:team_id].presence,
      inbox_id: params[:inbox_id].presence,
      assignee_id: params[:assigned_agent_id].presence
    }.compact
  end

  def label
    params[:label_list].presence
  end

  def labelled_conversation_ids
    ActsAsTaggableOn::Tagging
      .joins(:tag)
      .where(taggable_type: 'Conversation', context: 'labels', tags: { name: label })
      .select(:taggable_id)
  end
end
