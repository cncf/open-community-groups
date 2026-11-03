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
 * @param {{ label: string }} options - Short label used in the username, email and name.
 * @returns {{ userId: string }}
 */
export const setupTemporaryUser = ({ label }) => {
  const userId = randomUUID();
  const suffix = shortId(userId);
  const username = `e2e-${label}-${suffix}`;

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
      ${sqlString(`${username}@example.com`)},
      true,
      ${sqlString(`E2E ${label} ${suffix}`)},
      ${sqlString(TEMP_PASSWORD_HASH)},
      ${sqlString(`e2e-temporary-${suffix}`)}
    );
  `);

  return { userId };
};
