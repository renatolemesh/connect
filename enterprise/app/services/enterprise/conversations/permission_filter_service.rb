module Enterprise::Conversations::PermissionFilterService
  def perform
    return filter_by_permissions(permissions) if user_has_custom_role?

    super
  end

  private

  # custom roles are honoured for any account user, including administrators,
  # so the role always stays scoped to the inboxes the user is a member of
  def user_has_custom_role?
    account_user&.custom_role_id.present?
  end

  def permissions
    account_user&.permissions || []
  end

  def user_team_ids
    @user_team_ids ||= user.teams.where(account_id: account.id).pluck(:id)
  end

  def filter_by_permissions(permissions)
    # conversation_manage grants every conversation of the inboxes the user belongs to
    return accessible_conversations if permissions.include?('conversation_manage')

    scopes = base_scopes(permissions)
    # conversation_team_manage is an additive flag on top of any other permission
    scopes << accessible_conversations.where(team_id: user_team_ids) if include_team_assigned?(permissions)

    return Conversation.none if scopes.empty?

    union_scope(scopes)
  end

  def base_scopes(permissions)
    if permissions.include?('conversation_unassigned_manage')
      [
        accessible_conversations.assigned_to(user),
        accessible_conversations.unassigned
                                .where('conversations.team_id IN (?) OR conversations.team_id IS NULL', user_team_ids)
      ]
    elsif permissions.include?('conversation_participating_manage')
      [filter_participating_and_mine]
    else
      []
    end
  end

  def include_team_assigned?(permissions)
    permissions.include?('conversation_team_manage') && user_team_ids.any?
  end

  def union_scope(scopes)
    return scopes.first if scopes.one?

    Conversation.from("(#{scopes.map(&:to_sql).join(' UNION ')}) as conversations")
                .where(account_id: account.id)
                .includes(conversations.includes_values)
  end

  def filter_participating_and_mine
    conversations = accessible_conversations
    participant_conversation_ids = ConversationParticipant.where(account_id: account.id, user_id: user.id).select(:conversation_id)

    conversations
      .where(assignee_id: user.id)
      .or(conversations.where(id: participant_conversation_ids))
  end
end
