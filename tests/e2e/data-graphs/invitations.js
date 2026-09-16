import { queryE2eDatabase } from "../database.js";

/**
 * Removes a pending community team invitation by exact owner identifiers.
 * @param {{ communityId: string, userId: string }} options - Invitation owner identifiers.
 */
export const cleanupCommunityTeamInvitation = ({ communityId, userId }) => {
  queryE2eDatabase(`
    delete from community_team
    where community_id = '${communityId}'
    and user_id = '${userId}'
    and accepted = false;
  `);
};

/**
 * Removes a pending group team invitation by exact owner identifiers.
 * @param {{ groupId: string, userId: string }} options - Invitation owner identifiers.
 */
export const cleanupGroupTeamInvitation = ({ groupId, userId }) => {
  queryE2eDatabase(`
    delete from group_team
    where group_id = '${groupId}'
    and user_id = '${userId}'
    and accepted = false;
  `);
};
