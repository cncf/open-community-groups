import { randomUUID } from "node:crypto";

import { queryE2eDatabase, queryE2eDatabaseRows, sqlString, sqlUuid, sqlUuidArray } from "../database.js";

/**
 * Deletes owned inbox conversations with their messages.
 * @param {string[]} ids - Exact conversation identifiers created by the scenario.
 */
export const cleanupInboxConversations = (ids) => {
  const conversationIds = ids.filter(Boolean);
  if (conversationIds.length === 0) {
    return;
  }

  const idArray = sqlUuidArray(conversationIds);
  queryE2eDatabase(`
    delete from inbox_message where inbox_conversation_id = any(${idArray});
    delete from inbox_conversation where inbox_conversation_id = any(${idArray});
  `);
};

/**
 * Deletes every inbox conversation of one user with its messages. Never use it for a user who
 * owns seeded conversations, such as the second member.
 * @param {string} userId - User whose conversations are removed.
 */
export const cleanupUserInboxConversations = (userId) => {
  queryE2eDatabase(`
    delete from inbox_message
    where inbox_conversation_id in (
      select inbox_conversation_id from inbox_conversation where user_id = ${sqlUuid(userId)}
    );
    delete from inbox_conversation where user_id = ${sqlUuid(userId)};
  `);
};

/**
 * Returns the only conversation one user has with one group, such as the one a contact modal
 * message just started.
 * @param {{ groupId: string, userId: string }} options - Conversation group and user.
 * @returns {string} Conversation identifier.
 */
export const findUserConversationId = ({ groupId, userId }) => {
  const rows = queryE2eDatabaseRows(`
    select inbox_conversation_id
    from inbox_conversation
    where group_id = ${sqlUuid(groupId)}
    and user_id = ${sqlUuid(userId)}
  `);
  if (rows.length !== 1) {
    throw new Error(`Expected one inbox conversation for user ${userId}, found ${rows.length}`);
  }

  return rows[0][0];
};

/**
 * Inserts closed conversations started now by one user, so they count towards the daily
 * conversation limit without leaving an open thread.
 * @param {{ count: number, groupId: string, userId: string }} options - Conversation shape.
 * @returns {string[]} Inserted conversation identifiers.
 */
export const insertClosedUserConversations = ({ count, groupId, userId }) =>
  queryE2eDatabaseRows(`
    insert into inbox_conversation (group_id, inbox_conversation_status_id, user_id)
    select ${sqlUuid(groupId)}, 'closed', ${sqlUuid(userId)}
    from generate_series(1, ${Number(count)})
    returning inbox_conversation_id
  `).map(([id]) => id);

/**
 * Inserts an owned inbox conversation with its messages, one minute apart and ending now.
 * The first message is the `initial` one; later messages are `user-reply` or `group-reply`.
 * Message authors default to the conversation user, except group replies, which name theirs.
 * Bodies must be non-blank and at most 5,000 characters.
 * @param {{
 *   eventId?: string|null,
 *   groupId: string,
 *   messages: Array<{
 *     authorUserId?: string|null,
 *     body: string,
 *     kind?: "group-reply"|"initial"|"user-reply"
 *   }>,
 *   status?: "answered"|"closed"|"open"|"spam",
 *   userId?: string|null
 * }} options - Conversation shape; a null `userId` models a deleted user.
 * @returns {{ id: string, messageIds: string[] }} Conversation and message identifiers.
 */
export const setupInboxConversation = ({
  eventId = null,
  groupId,
  messages,
  status = "open",
  userId = null,
}) => {
  const rows = messages.map((message, index) => buildMessageRow(message, index, userId));
  if (rows.length === 0) {
    throw new Error("An inbox conversation needs an initial message");
  }

  const id = randomUUID();
  const firstOffset = rows.length - 1;
  const messageValues = rows.map(
    ({ authorUserId, body, id: messageId, kind }, index) => `(
      ${sqlUuid(messageId)},
      ${sqlString(body)},
      current_timestamp - interval '${firstOffset - index} minutes',
      ${sqlUuid(id)},
      ${sqlString(kind)},

      ${sqlNullableUuid(authorUserId)}
    )`,
  );

  queryE2eDatabase(`
    insert into inbox_conversation (
      inbox_conversation_id,
      created_at,
      group_id,
      inbox_conversation_status_id,
      last_message_at,

      event_id,
      user_id
    ) values (
      ${sqlUuid(id)},
      current_timestamp - interval '${firstOffset} minutes',
      ${sqlUuid(groupId)},
      ${sqlString(status)},
      current_timestamp,

      ${sqlNullableUuid(eventId)},
      ${sqlNullableUuid(userId)}
    );

    insert into inbox_message (
      inbox_message_id,
      body,
      created_at,
      inbox_conversation_id,
      kind,

      author_user_id
    ) values ${messageValues.join(", ")};
  `);

  return { id, messageIds: rows.map(({ id: messageId }) => messageId) };
};

// Helpers.

/**
 * Resolves one message row, enforcing a single leading `initial` message.
 * @param {{ authorUserId?: string|null, body: string, kind?: string }} message - Message shape.
 * @param {number} index - Message position in the conversation.
 * @param {string|null} userId - Conversation user, the default author of user messages.
 * @returns {{ authorUserId: string|null, body: string, id: string, kind: string }} Message row.
 */
const buildMessageRow = (message, index, userId) => {
  const kind = message.kind ?? (index === 0 ? "initial" : undefined);
  const expectedKinds = index === 0 ? ["initial"] : ["group-reply", "user-reply"];
  if (!expectedKinds.includes(kind)) {
    throw new Error(`Inbox message ${index} must be ${expectedKinds.join(" or ")}, got ${kind}`);
  }
  if (kind === "group-reply" && message.authorUserId === undefined) {
    throw new Error(`Inbox group reply ${index} needs an authorUserId`);
  }

  return {
    authorUserId: message.authorUserId === undefined ? userId : message.authorUserId,
    body: message.body,
    id: randomUUID(),
    kind,
  };
};

/**
 * Quotes a uuid literal, or returns `null` when the value is absent.
 * @param {string|null} value - UUID string or null.
 * @returns {string} SQL uuid literal or `null`.
 */
const sqlNullableUuid = (value) => (value ? sqlUuid(value) : "null");
