import { queryE2eDatabase } from "../database.js";

/**
 * Deletes a user's notification mute for one group.
 * @param {{ groupId: string, userId: string }} ids - Mute owner and group.
 * @returns {void}
 */
export const cleanupGroupMute = ({ groupId, userId }) => {
  queryE2eDatabase(`
    delete from user_group_notification_mute
    where user_id = '${userId}'::uuid
    and group_id = '${groupId}'::uuid;
  `);
};

/**
 * Restores one persisted notification category preference.
 * @param {{ category: string, enabled: boolean, userId: string }} preference - Preference state.
 * @returns {void}
 */
export const restoreNotificationPreference = ({ category, enabled, userId }) => {
  if (enabled) {
    queryE2eDatabase(`
      delete from user_notification_opt_out
      where user_id = '${userId}'::uuid
      and notification_category_id = '${category}';
    `);
    return;
  }

  queryE2eDatabase(`
    insert into user_notification_opt_out (user_id, notification_category_id)
    values ('${userId}'::uuid, '${category}')
    on conflict do nothing;
  `);
};

/**
 * Creates a user's notification mute for one group.
 * @param {{ groupId: string, userId: string }} ids - Mute owner and group.
 * @returns {void}
 */
export const setupGroupMute = ({ groupId, userId }) => {
  queryE2eDatabase(`
    insert into user_group_notification_mute (user_id, group_id)
    values ('${userId}'::uuid, '${groupId}'::uuid)
    on conflict do nothing;
  `);
};
