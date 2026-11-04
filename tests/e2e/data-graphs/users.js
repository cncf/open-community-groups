import { randomUUID } from "node:crypto";

import { queryE2eDatabase, sqlString, sqlUuid } from "../database.js";
import { shortId } from "../utils.js";

/** Argon2 hash stored for temporary users; nothing logs in with it. */
export const TEMP_PASSWORD_HASH =
  "$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g";

/**
 * Deletes a temporary user and the notification, attendee, membership and team rows that
 * reference it.
 * @param {string} userId - User created by `setupTemporaryUser`.
 */
export const cleanupTemporaryUser = (userId) => {
  queryE2eDatabase(`
    delete from notification where user_id = ${sqlUuid(userId)};
    delete from event_attendee where user_id = ${sqlUuid(userId)};
    delete from group_member where user_id = ${sqlUuid(userId)};
    delete from group_team where user_id = ${sqlUuid(userId)};
    delete from community_team where user_id = ${sqlUuid(userId)};
    delete from "user" where user_id = ${sqlUuid(userId)};
  `);
};

/**
 * Creates a verified temporary user; release it with `cleanupTemporaryUser`.
 * @param {{ email?: string, label: string, name?: string }} options - Short label used in the
 *   username, and in the email and name unless `email` or `name` replace them (for long-data
 *   layout coverage). An `email` must be unique, so build it from a unique value.
 * @returns {{ email: string, name: string, userId: string }}
 */
export const setupTemporaryUser = ({ email, label, name }) => {
  const userId = randomUUID();
  const suffix = shortId(userId);
  const username = `e2e-${label}-${suffix}`;
  const userEmail = email ?? `${username}@example.com`;
  const userName = name ?? `E2E ${label} ${suffix}`;

  queryE2eDatabase(`
    insert into "user" (
      user_id,
      username,
      email,
      email_verified,
      name,
      password,
      auth_hash
    ) values (
      ${sqlUuid(userId)},
      ${sqlString(username)},
      ${sqlString(userEmail)},
      true,
      ${sqlString(userName)},
      ${sqlString(TEMP_PASSWORD_HASH)},
      ${sqlString(`e2e-temporary-${suffix}`)}
    );
  `);

  return { email: userEmail, name: userName, userId };
};
