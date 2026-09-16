import { expect } from "@playwright/test";

import { queryE2eDatabase, queryE2eDatabaseRows } from "./database.js";

/**
 * Captures the notification queue position so later assertions only consider rows enqueued
 * afterwards. Uses the database clock, so browser and worker time never influence the cut-off.
 */
export const snapshotNotifications = () => {
  const createdAfter = queryE2eDatabase("select clock_timestamp()");

  return { createdAfter };
};

/**
 * Asserts that exactly the expected notifications were enqueued after the snapshot and returns
 * their IDs. Each expectation names a kind, the full recipient set for that kind, and optional
 * JSON fragments that must be contained in the template data. Unexpected kinds or recipients
 * fail the assertion so silent fan-out regressions are caught.
 */
export const expectNewNotifications = (snapshot, expectations) => {
  const rows = listNotificationsSince(snapshot);
  const actual = rows.map(({ kind, userId }) => `${kind}:${userId}`).sort();
  const expected = expectations
    .flatMap(({ kind, userIds }) => userIds.map((userId) => `${kind}:${userId}`))
    .sort();

  expect(actual, formatNotificationRows(rows)).toEqual(expected);

  for (const { kind, templateDataContains } of expectations) {
    if (templateDataContains === undefined) {
      continue;
    }

    for (const row of rows.filter((candidate) => candidate.kind === kind)) {
      expect(row.templateData, `template data for ${kind}`).toMatchObject(templateDataContains);
    }
  }

  return rows.map(({ notificationId }) => notificationId);
};

/** Deletes the notifications created by a test so reruns start from the seeded queue. */
export const deleteNotifications = (notificationIds) => {
  if (notificationIds.length === 0) {
    return;
  }

  const idList = notificationIds.map((notificationId) => `'${notificationId}'`).join(", ");
  queryE2eDatabase(`delete from notification where notification_id in (${idList})`);
};

/** Returns notification rows created since the snapshot from the notification table. */
const listNotificationsSince = ({ createdAfter }) =>
  queryE2eDatabaseRows(`
    select
      n.notification_id,
      n.kind,
      n.user_id,
      coalesce(ntd.data::text, 'null')
    from notification n
    left join notification_template_data ntd using (notification_template_data_id)
    where n.created_at >= '${createdAfter}'::timestamptz
    order by n.kind, n.user_id
  `).map(parseNotificationRow);

/** Rebuilds a notification row from psql cells, re-joining JSON that contained "|". */
const parseNotificationRow = ([notificationId, kind, userId, ...templateDataCells]) => ({
  notificationId,
  kind,
  userId,
  templateData: JSON.parse(templateDataCells.join("|")),
});

/** Formats notification rows for assertion failure messages. */
const formatNotificationRows = (rows) =>
  rows.length === 0
    ? "no notifications enqueued since snapshot"
    : rows.map(({ kind, userId }) => `${kind} -> ${userId}`).join("\n");
