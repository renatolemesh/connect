class ReportingEventListener < BaseListener
  include ReportingEventHelper

  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]
    start_time = resolution_start_time(conversation)
    time_to_resolve = conversation.updated_at.to_i - start_time.to_i

    reporting_event = ReportingEvent.new(
      name: 'conversation_resolved',
      value: time_to_resolve,
      value_in_business_hours: business_hours(conversation.inbox, start_time, conversation.updated_at),
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      user_id: conversation.assignee_id,
      conversation_id: conversation.id,
      event_start_time: start_time,
      event_end_time: conversation.updated_at
    )

    create_bot_resolved_event(conversation, reporting_event)
    reporting_event.save!
  end

  def first_reply_created(event)
    message = extract_message_and_account(event)[0]
    conversation = message.conversation
    first_response_time = message.created_at.to_i - last_non_human_activity(conversation).to_i

    reporting_event = ReportingEvent.new(
      name: 'first_response',
      value: first_response_time,
      value_in_business_hours: business_hours(conversation.inbox, last_non_human_activity(conversation),
                                              message.created_at),
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      user_id: message.sender_id,
      conversation_id: conversation.id,
      event_start_time: last_non_human_activity(conversation),
      event_end_time: message.created_at
    )

    reporting_event.save!
  end

  def reply_created(event)
    message = extract_message_and_account(event)[0]
    conversation = message.conversation
    waiting_since = event.data[:waiting_since]

    return if waiting_since.blank?

    # When waiting_since is nil, set reply_time to 0
    reply_time = message.created_at.to_i - waiting_since.to_i

    reporting_event = ReportingEvent.new(
      name: 'reply_time',
      value: reply_time,
      value_in_business_hours: business_hours(conversation.inbox, waiting_since, message.created_at),
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      user_id: conversation.assignee_id,
      conversation_id: conversation.id,
      event_start_time: waiting_since,
      event_end_time: message.created_at
    )
    reporting_event.save!
  end

  def conversation_bot_handoff(event)
    conversation = extract_conversation_and_account(event)[0]

    # check if a conversation_bot_handoff event exists for this conversation
    bot_handoff_event = ReportingEvent.find_by(conversation_id: conversation.id, name: 'conversation_bot_handoff')
    return if bot_handoff_event.present?

    time_to_handoff = conversation.updated_at.to_i - conversation.created_at.to_i

    reporting_event = ReportingEvent.new(
      name: 'conversation_bot_handoff',
      value: time_to_handoff,
      value_in_business_hours: business_hours(conversation.inbox, conversation.created_at, conversation.updated_at),
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      user_id: conversation.assignee_id,
      conversation_id: conversation.id,
      event_start_time: conversation.created_at,
      event_end_time: conversation.updated_at
    )
    reporting_event.save!
  end

  def conversation_opened(event)
    conversation = extract_conversation_and_account(event)[0]

    # Find the most recent resolved event for this conversation
    last_resolved_event = ReportingEvent.where(
      conversation_id: conversation.id,
      name: 'conversation_resolved'
    ).order(event_end_time: :desc).first

    # For first-time openings, value is 0
    # For reopenings, calculate time since resolution
    if last_resolved_event
      time_since_resolved = conversation.updated_at.to_i - last_resolved_event.event_end_time.to_i
      business_hours_value = business_hours(conversation.inbox, last_resolved_event.event_end_time, conversation.updated_at)
      start_time = last_resolved_event.event_end_time
    else
      time_since_resolved = 0
      business_hours_value = 0
      start_time = conversation.created_at
    end

    create_conversation_opened_event(conversation, time_since_resolved, business_hours_value, start_time)
  end

  private

  # Caixa com "conversa unica" reabre a mesma conversa a cada novo contato do cliente. Contar
  # a resolucao desde a criacao somaria os dias em que ela ficou encerrada, entao ali cada
  # resolucao conta so o periodo aberto: da reabertura que seguiu a resolucao anterior ate agora.
  # Sem resolucao anterior, ou sem o evento de reabertura, vale a criacao, como nas demais caixas.
  def resolution_start_time(conversation)
    return conversation.created_at unless conversation.inbox.lock_to_single_conversation?

    reopened_at(conversation) || conversation.created_at
  end

  # A primeira abertura depois da resolucao anterior, nao a ultima: um adiamento reaberto no meio
  # do periodo tambem gera conversation_opened e nao pode encurtar a conta.
  def reopened_at(conversation)
    events = ReportingEvent.where(conversation_id: conversation.id)
    last_resolved_at = events.where(name: 'conversation_resolved').maximum(:event_end_time)
    return if last_resolved_at.blank?

    events.where(name: 'conversation_opened').where('event_end_time >= ?', last_resolved_at).minimum(:event_end_time)
  end

  def create_conversation_opened_event(conversation, time_since_resolved, business_hours_value, start_time)
    reporting_event = ReportingEvent.new(
      name: 'conversation_opened',
      value: time_since_resolved,
      value_in_business_hours: business_hours_value,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      user_id: conversation.assignee_id,
      conversation_id: conversation.id,
      event_start_time: start_time,
      event_end_time: conversation.updated_at
    )
    reporting_event.save!
  end

  def create_bot_resolved_event(conversation, reporting_event)
    return unless conversation.inbox.active_bot?
    # We don't want to create a bot_resolved event if there is user interaction on the conversation
    return if conversation.messages.exists?(message_type: :outgoing, sender_type: 'User')

    bot_resolved_event = reporting_event.dup
    bot_resolved_event.name = 'conversation_bot_resolved'
    bot_resolved_event.save!
  end
end
