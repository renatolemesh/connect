module Enterprise::ConversationPolicy
  def show?
    return false unless super
    return true unless custom_role_permissions?

    # custom roles are always scoped to the inboxes the user is a member of
    return false unless inbox_access?

    permissions = custom_role_permissions
    return true if manage_all_conversations?(permissions)
    return true if team_assigned_conversation?(permissions)
    return true if permits_unassigned_manage?(permissions)

    permits_participating?(permissions)
  end

  private

  def manage_all_conversations?(permissions)
    permissions.include?('conversation_manage')
  end

  def permits_unassigned_manage?(permissions)
    return false unless permissions.include?('conversation_unassigned_manage')

    assigned_to_user? || unassigned_within_team_scope?
  end

  # mirrors the conversation list: unassigned conversations routed to another team are out of scope
  def unassigned_within_team_scope?
    return false unless unassigned_conversation?

    record.team_id.blank? || user_team?
  end

  def team_assigned_conversation?(permissions)
    return false unless permissions.include?('conversation_team_manage')
    return false if record.team_id.blank?

    user_team?
  end

  def user_team?
    user.teams.where(account_id: account&.id).exists?(id: record.team_id)
  end

  def permits_participating?(permissions)
    return false unless permissions.include?('conversation_participating_manage')

    assigned_to_user? || participant?
  end

  def unassigned_conversation?
    record.assignee_id.nil? && record.assignee_agent_bot_id.nil?
  end

  def custom_role_permissions?
    account_user&.custom_role_id.present?
  end

  def custom_role_permissions
    account_user&.custom_role&.permissions || []
  end
end
