import { expect } from "@playwright/test";

import { queryE2eDatabase, queryE2eDatabaseRows, sqlString, sqlUuidArray } from "./database.js";

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
 * their IDs. Each expectation names a kind, its recipients, and optional JSON fragments that must
 * be contained in the template data of those recipients' rows. A kind may be split across several
 * expectations when recipient groups receive different template data. Unexpected kinds or
 * recipients fail the assertion so silent fan-out regressions are caught.
 */
export const expectNewNotifications = (snapshot, expectations) => {
  const rows = listNotificationsSince(snapshot);
  const actual = rows.map(({ kind, userId }) => `${kind}:${userId}`).sort();
  const expected = expectations
    .flatMap(({ kind, userIds }) => userIds.map((userId) => `${kind}:${userId}`))
    .sort();

  expect(actual, formatNotificationRows(rows)).toEqual(expected);

  for (const { kind, templateDataContains, userIds } of expectations) {
    if (templateDataContains === undefined) {
      continue;
    }

    const expectationRows = rows.filter(
      (candidate) => candidate.kind === kind && userIds.includes(candidate.userId),
    );
    for (const row of expectationRows) {
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

  queryE2eDatabase(`delete from notification where notification_id = any(${sqlUuidArray(notificationIds)})`);
};

/**
 * Deletes every notification and custom notification created since the snapshot, plus
 * the template data rows only those notifications referenced, and the template data and
 * attachment rows created since the snapshot that no notification references any more (cleanups
 * that delete notifications directly, or through a user cascade, leave those behind). Relies on
 * one Playwright worker per database: rows another worker created in the same window would be
 * deleted too.
 */
export const deleteNotificationsCreatedSince = ({ createdAfter }) => {
  // Rows created before the snapshot are exactly the ones that survive the delete, and every
  // part of the statement sees the same snapshot, so only those keep template data alive.
  queryE2eDatabase(`
    with deleted as (
      delete from notification
      where created_at >= ${sqlString(createdAfter)}::timestamptz
      returning notification_template_data_id
    )
    delete from notification_template_data ntd
    where ntd.notification_template_data_id in (select notification_template_data_id from deleted)
    and not exists (
      select 1
      from notification n
      where n.notification_template_data_id = ntd.notification_template_data_id
      and n.created_at < ${sqlString(createdAfter)}::timestamptz
    );

    delete from notification_template_data ntd
    where ntd.created_at >= ${sqlString(createdAfter)}::timestamptz
    and not exists (
      select 1
      from notification n
      where n.notification_template_data_id = ntd.notification_template_data_id
    );

    delete from custom_notification
    where created_at >= ${sqlString(createdAfter)}::timestamptz;

    delete from attachment a
    where a.created_at >= ${sqlString(createdAfter)}::timestamptz
    and not exists (
      select 1
      from notification_attachment na
      where na.attachment_id = a.attachment_id
    );
  `);
};

/**
 * Returns the notification rows created since the snapshot, ordered by kind and recipient.
 * @param {{ createdAfter: string }} snapshot - Cut-off from `snapshotNotifications`.
 * @returns {Array<{ kind: string, notificationId: string, templateData: object|null, userId: string }>}
 */
export const listNotificationsSince = ({ createdAfter }) =>
  queryE2eDatabaseRows(`
    select
      n.notification_id,
      n.kind,
      n.user_id,
      coalesce(ntd.data::text, 'null')
    from notification n
    left join notification_template_data ntd using (notification_template_data_id)
    where n.created_at >= ${sqlString(createdAfter)}::timestamptz
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
