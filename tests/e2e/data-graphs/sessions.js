import { randomUUID } from "node:crypto";

import { queryE2eDatabase, sqlString, sqlUuid, sqlUuidArray } from "../database.js";

/**
 * Inserts virtual sessions in an owned event, each spanning the event's first hour, with their
 * speakers. Session speakers are not featured unless `featured` is set. Sessions and their
 * speakers cascade when `cleanupEventsByIds([eventId])` removes the event, so release the event
 * before the users.
 * @param {{
 *   eventId: string,
 *   sessions: Array<{ featured?: boolean, name: string, speakerUserIds?: string[] }>
 * }} input - Owned event and its sessions in display order.
 * @returns {string[]} Session identifiers in the order given.
 */
export const setupEventSessions = ({ eventId, sessions }) => {
  const rows = sessions.map((session) => ({ ...session, sessionId: randomUUID() }));
  if (rows.length === 0) {
    return [];
  }

  queryE2eDatabase(`
    insert into session (event_id, name, session_id, session_kind_id, starts_at, ends_at)
    select e.event_id, s.name, s.session_id, 'virtual', e.starts_at, e.starts_at + interval '1 hour'
    from event e
    cross join (
      values ${rows.map(({ name, sessionId }) => `(${sqlString(name)}, ${sqlUuid(sessionId)})`).join(", ")}
    ) as s(name, session_id)
    where e.event_id = ${sqlUuid(eventId)};

    ${rows
      .filter(({ speakerUserIds = [] }) => speakerUserIds.length > 0)
      .map(
        ({ featured = false, sessionId, speakerUserIds }) => `
          insert into session_speaker (session_id, user_id, featured)
          select ${sqlUuid(sessionId)}, user_id, ${featured}
          from unnest(${sqlUuidArray(speakerUserIds)}) as user_id;
        `,
      )
      .join("")}
  `);

  return rows.map(({ sessionId }) => sessionId);
};
