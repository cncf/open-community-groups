import { queryE2eDatabase, sqlString, sqlUuid } from "../database.js";

/**
 * Deletes the UTM page-view counters of an owned event. Run it before the event is removed:
 * deleting the event only nulls the counters' event reference.
 * @param {string} eventId - Event whose counters `setupEventUtmViews` stored.
 * @returns {void}
 */
export const cleanupEventUtmViews = (eventId) => {
  queryE2eDatabase(`delete from event_views_utm where event_id = ${sqlUuid(eventId)};`);
};

/**
 * Stores UTM page-view counters of an owned event, three days ago, as the activity tracker
 * does. Values hold 1 to 50 lowercase letters, digits, dots, hyphens and underscores. Release
 * them with `cleanupEventUtmViews` before the event.
 * @param {{
 *   eventId: string,
 *   rows: Array<{ campaign: string, medium: string, source: string, total: number }>
 * }} input - Owned event and its counters; each combination appears once.
 * @returns {void}
 */
export const setupEventUtmViews = ({ eventId, rows }) => {
  if (rows.length === 0) {
    return;
  }

  queryE2eDatabase(`
    insert into event_views_utm (event_id, day, total, utm_campaign, utm_medium, utm_source)
    values ${rows
      .map(
        ({ campaign, medium, source, total }) => `(
          ${sqlUuid(eventId)},
          current_date - 3,
          ${Number(total)},
          ${sqlString(campaign)},
          ${sqlString(medium)},
          ${sqlString(source)}
        )`,
      )
      .join(", ")};
  `);
};
