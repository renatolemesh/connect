import { CONVERSATION_PRIORITY_ORDER } from 'shared/constants/messages';

export const findPendingMessageIndex = (chat, message) => {
  const { echo_id: tempMessageId } = message;
  return chat.messages.findIndex(
    m => m.id === message.id || m.id === tempMessageId
  );
};

const getExcludedPendingContent = () => {
  const raw = window?.globalConfig?.EXCLUDED_PENDING_CONTENT || '';
  return raw
    .split(',')
    .map(w => w.trim().toLowerCase())
    .filter(Boolean);
};

const isExcludedIncomingLastMessage = conversation => {
  const excluded = getExcludedPendingContent();
  if (!excluded.length) return false;

  const messages = conversation.messages || [];
  const lastMessage = messages[messages.length - 1];
  if (!lastMessage || lastMessage.message_type !== 0) return false;

  const content = (lastMessage.content || '').trim().toLowerCase();
  return excluded.includes(content);
};

// A ultima mensagem e do cliente? O backend (`ConversationFinder#filter_by_unread_status`)
// exige `last_message_type = incoming`, e aqui faltava o mesmo teste: a conversa
// entrava na lista por uma mensagem do cliente e, quando era respondida, o evento
// ao vivo atualizava o texto mas ela NAO saia do filtro -- so sumia recarregando a
// pagina. Aparecia com a setinha de resposta no meio das nao respondidas.
const hasIncomingLastMessage = conversation => {
  const messages = conversation.messages || [];
  const lastMessage = messages[messages.length - 1];
  // Sem mensagem carregada nao da para decidir; manter na lista e o lado seguro,
  // porque o refresh seguinte corrige. Remover por engano esconde conversa viva.
  if (!lastMessage) return true;
  return lastMessage.message_type === 0;
};

export const filterByStatus = (conversation, filterStatus) => {
  if (filterStatus === 'all') return true;
  if (filterStatus === 'unread') {
    return (
      conversation.status === 'open' &&
      hasIncomingLastMessage(conversation) &&
      !isExcludedIncomingLastMessage(conversation)
    );
  }
  return conversation.status === filterStatus;
};

export const filterByInbox = (shouldFilter, inboxId, chatInboxId) => {
  const isOnInbox = Number(inboxId) === chatInboxId;
  return inboxId ? isOnInbox && shouldFilter : shouldFilter;
};

export const filterByTeam = (shouldFilter, teamId, chatTeamId) => {
  const isOnTeam = Number(teamId) === chatTeamId;
  return teamId ? isOnTeam && shouldFilter : shouldFilter;
};

export const filterByLabel = (shouldFilter, labels, chatLabels) => {
  const isOnLabel = labels.every(label => chatLabels.includes(label));
  return labels.length ? isOnLabel && shouldFilter : shouldFilter;
};
export const filterByUnattended = (
  shouldFilter,
  conversationType,
  firstReplyOn,
  waitingSince
) => {
  return conversationType === 'unattended'
    ? (!firstReplyOn || !!waitingSince) && shouldFilter
    : shouldFilter;
};

export const applyPageFilters = (conversation, filters) => {
  const { inboxId, status, labels = [], teamId, conversationType } = filters;
  const {
    inbox_id: chatInboxId,
    labels: chatLabels = [],
    meta = {},
    first_reply_created_at: firstReplyOn,
    waiting_since: waitingSince,
  } = conversation;
  const team = meta.team || {};
  const { id: chatTeamId } = team;

  let shouldFilter = filterByStatus(conversation, status);
  shouldFilter = filterByInbox(shouldFilter, inboxId, chatInboxId);
  shouldFilter = filterByTeam(shouldFilter, teamId, chatTeamId);
  shouldFilter = filterByLabel(shouldFilter, labels, chatLabels);
  shouldFilter = filterByUnattended(
    shouldFilter,
    conversationType,
    firstReplyOn,
    waitingSince
  );

  return shouldFilter;
};

/**
 * Filters conversations based on user role and permissions
 *
 * @param {Object} conversation - The conversation object to check permissions for
 * @param {string} role - The user's role (administrator, agent, etc.)
 * @param {Array<string>} permissions - List of permission strings the user has
 * @param {number|string} currentUserId - The ID of the current user
 * @returns {boolean} - Whether the user has permissions to access this conversation
 */
export const applyRoleFilter = (
  conversation,
  role,
  permissions,
  currentUserId,
  userTeamIds = []
) => {
  // the role === "agent" check is typically not correct on it's own
  // the backend handles this by checking the custom_role_id at the user model
  // here however, the `getUserRole` returns "custom_role" if the id is present,
  // so we can check the role === "agent" directly
  if (['administrator', 'agent'].includes(role)) {
    return true;
  }

  // Check for full conversation management permission
  if (permissions.includes('conversation_manage')) {
    return true;
  }

  const conversationAssignee = conversation.meta.assignee;
  const conversationTeamId = conversation.meta.team?.id;
  const isUnassigned = !conversationAssignee;
  const isAssignedToUser = conversationAssignee?.id === currentUserId;
  const isInUserTeam = userTeamIds.includes(conversationTeamId);

  // Team management is an additive flag on top of any other permission
  if (permissions.includes('conversation_team_manage') && isInUserTeam) {
    return true;
  }

  // Check unassigned management permission
  if (permissions.includes('conversation_unassigned_manage')) {
    const isUnassignedInUserScope =
      isUnassigned && (!conversationTeamId || isInUserTeam);
    return isUnassignedInUserScope || isAssignedToUser;
  }

  // Check participating conversation management permission
  if (permissions.includes('conversation_participating_manage')) {
    return isAssignedToUser;
  }

  return false;
};

const SORT_OPTIONS = {
  last_activity_at_asc: ['sortOnLastActivityAt', 'asc'],
  last_activity_at_desc: ['sortOnLastActivityAt', 'desc'],
  created_at_asc: ['sortOnCreatedAt', 'asc'],
  created_at_desc: ['sortOnCreatedAt', 'desc'],
  priority_asc: ['sortOnPriority', 'asc'],
  priority_desc: ['sortOnPriority', 'desc'],
  waiting_since_asc: ['sortOnWaitingSince', 'asc'],
  waiting_since_desc: ['sortOnWaitingSince', 'desc'],
  priority_desc_created_at_asc: ['sortOnPriorityCreatedAt', 'desc'],
};
const sortAscending = (valueA, valueB) => valueA - valueB;
const sortDescending = (valueA, valueB) => valueB - valueA;

const getSortOrderFunction = sortOrder =>
  sortOrder === 'asc' ? sortAscending : sortDescending;

const sortConfig = {
  sortOnLastActivityAt: (a, b, sortDirection) =>
    getSortOrderFunction(sortDirection)(a.last_activity_at, b.last_activity_at),

  sortOnCreatedAt: (a, b, sortDirection) =>
    getSortOrderFunction(sortDirection)(a.created_at, b.created_at),

  sortOnPriority: (a, b, sortDirection) => {
    const DEFAULT_FOR_NULL = sortDirection === 'asc' ? 5 : 0;

    const p1 = CONVERSATION_PRIORITY_ORDER[a.priority] || DEFAULT_FOR_NULL;
    const p2 = CONVERSATION_PRIORITY_ORDER[b.priority] || DEFAULT_FOR_NULL;

    return getSortOrderFunction(sortDirection)(p1, p2);
  },

  sortOnPriorityCreatedAt: (a, b) => {
    const DEFAULT_FOR_NULL = 0;
    const p1 = CONVERSATION_PRIORITY_ORDER[a.priority] || DEFAULT_FOR_NULL;
    const p2 = CONVERSATION_PRIORITY_ORDER[b.priority] || DEFAULT_FOR_NULL;
    if (p1 !== p2) return p2 - p1;
    return a.created_at - b.created_at;
  },

  sortOnWaitingSince: (a, b, sortDirection) => {
    const sortFunc = getSortOrderFunction(sortDirection);
    if (!a.waiting_since || !b.waiting_since) {
      if (!a.waiting_since && !b.waiting_since) {
        return sortFunc(a.created_at, b.created_at);
      }
      return sortFunc(a.waiting_since ? 0 : 1, b.waiting_since ? 0 : 1);
    }

    return sortFunc(a.waiting_since, b.waiting_since);
  },
};

export const sortComparator = (a, b, sortKey) => {
  const [sortMethod, sortDirection] =
    SORT_OPTIONS[sortKey] || SORT_OPTIONS.last_activity_at_desc;
  return sortConfig[sortMethod](a, b, sortDirection);
};
