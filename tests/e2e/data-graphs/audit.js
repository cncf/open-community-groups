import { randomUUID } from "node:crypto";

import { queryE2eDatabase, sqlString, sqlUuid } from "../database.js";

/**
 * Inserts an audit log row at a fixed date. Audit logs are append-only, so the row stays, as the
 * logs of every dashboard action tests take do.
 * @param {{
 *   action: string,
 *   actorUserId: string,
 *   actorUsername: string,
 *   communityId: string,
 *   createdAt: string,
 *   details: object,
 *   resourceId: string,
 *   resourceType: string,
 *   groupId?: string,
 * }} options - Audit log fields; `createdAt` is a timestamptz literal.
 * @returns {string} Identifier of the new audit log.
 */
export const setupAuditLog = ({
  action,
  actorUserId,
  actorUsername,
  communityId,
  createdAt,
  details,
  resourceId,
  resourceType,
  groupId = null,
}) => {
  const auditLogId = randomUUID();

  queryE2eDatabase(`
    insert into audit_log (
      audit_log_id, action, created_at, resource_id, resource_type, actor_user_id, actor_username,
      community_id, details, group_id
    ) values (
      ${sqlUuid(auditLogId)},
      ${sqlString(action)},
      ${sqlString(createdAt)}::timestamptz,
      ${sqlUuid(resourceId)},
      ${sqlString(resourceType)},
      ${sqlUuid(actorUserId)},
      ${sqlString(actorUsername)},
      ${sqlUuid(communityId)},
      ${sqlString(JSON.stringify(details))}::jsonb,
      ${groupId ? sqlUuid(groupId) : "null"}
    );
  `);

  return auditLogId;
};
