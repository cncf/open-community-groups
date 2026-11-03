import { randomUUID } from "node:crypto";

import { queryE2eDatabase, queryE2eDatabaseRows, sqlString, sqlUuid } from "../database.js";
import {
  TEST_COMMUNITY_BANNER_MOBILE_URL,
  TEST_COMMUNITY_BANNER_URL,
  TEST_COMMUNITY_LOGO_URL,
} from "../seed.js";
import { shortId, uniqueName } from "../utils.js";
import { cleanupTemporaryGroup } from "./groups.js";

// Taxonomy tables `setupCommunityTaxonomyItem` and `cleanupCommunityTaxonomyItem` use, keyed by kind.
const TAXONOMY_TABLES = {
  eventCategory: "event_category",
  groupCategory: "group_category",
  region: "region",
};

/**
 * Deletes an unused event category, group category or region of a community, for an item a
 * view must not list.
 * @param {{ itemId: string, kind: "eventCategory" | "groupCategory" | "region" }} options -
 *   Taxonomy kind and item identifier.
 */
export const cleanupCommunityTaxonomyItem = ({ itemId, kind }) => {
  const table = TAXONOMY_TABLES[kind];

  queryE2eDatabase(`delete from ${table} where ${table}_id = ${sqlUuid(itemId)};`);
};

/**
 * Deletes event categories with an exact name in any community, for categories a test named.
 * @param {string} name - Unique category name used by the test.
 */
export const cleanupEventCategoriesByName = (name) => {
  queryE2eDatabase(`delete from event_category where name = ${sqlString(name)};`);
};

/**
 * Deletes regions with an exact name in any community, for regions a test named.
 * @param {string} name - Unique region name used by the test.
 */
export const cleanupRegionsByName = (name) => {
  queryE2eDatabase(`delete from region where name = ${sqlString(name)};`);
};

/**
 * Deletes a temporary community, its groups and its team, event category, region and group
 * category rows.
 * @param {string} communityId - Community created by `setupTemporaryCommunity`.
 */
export const cleanupTemporaryCommunity = (communityId) => {
  for (const groupId of groupIdsByCommunity(communityId)) {
    cleanupTemporaryGroup(groupId);
  }

  queryE2eDatabase(`
    delete from community_team where community_id = ${sqlUuid(communityId)};
    delete from event_category where community_id = ${sqlUuid(communityId)};
    delete from region where community_id = ${sqlUuid(communityId)};
    delete from group_category where community_id = ${sqlUuid(communityId)};
    delete from community where community_id = ${sqlUuid(communityId)};
  `);
};

/**
 * Returns the IDs of every group, deleted or not, that belongs to a community.
 * @param {string} communityId - Community identifier.
 * @returns {string[]}
 */
export const groupIdsByCommunity = (communityId) =>
  queryE2eDatabaseRows(`select group_id from "group" where community_id = ${sqlUuid(communityId)};`).map(
    ([groupId]) => groupId,
  );

/**
 * Adds an event category, group category or region to a community. `cleanupTemporaryCommunity`
 * removes it with the community.
 * @param {{ communityId: string, kind: "eventCategory" | "groupCategory" | "region", name: string }}
 *   options - Community, taxonomy kind and item name.
 * @returns {string} Identifier of the new item.
 */
export const setupCommunityTaxonomyItem = ({ communityId, kind, name }) => {
  const table = TAXONOMY_TABLES[kind];
  const itemId = randomUUID();

  queryE2eDatabase(`
    insert into ${table} (${table}_id, community_id, name)
    values (${sqlUuid(itemId)}, ${sqlUuid(communityId)}, ${sqlString(name)});
  `);

  return itemId;
};

/**
 * Creates a temporary community with one group category and an accepted team member. Release it
 * with `cleanupTemporaryCommunity`.
 * @param {{ label: string, teamRole: string, userId: string }} options - Label used in the names
 * and the community team role granted to the user.
 * @returns {{ communityId: string, displayName: string, groupCategoryId: string }}
 */
export const setupTemporaryCommunity = ({ label, teamRole, userId }) => {
  const communityId = randomUUID();
  const groupCategoryId = randomUUID();
  const communityName = `e2e-${label.replace(/\s+/gu, "-")}-${shortId(communityId)}`;
  const displayName = uniqueName(label);

  queryE2eDatabase(`
    insert into community (
      community_id,
      name,
      display_name,
      description,
      banner_url,
      banner_mobile_url,
      logo_url
    ) values (
      ${sqlUuid(communityId)},
      ${sqlString(communityName)},
      ${sqlString(displayName)},
      'Temporary community owned by E2E coverage.',
      ${sqlString(TEST_COMMUNITY_BANNER_URL)},
      ${sqlString(TEST_COMMUNITY_BANNER_MOBILE_URL)},
      ${sqlString(TEST_COMMUNITY_LOGO_URL)}
    );

    insert into group_category (group_category_id, name, community_id)
    values (${sqlUuid(groupCategoryId)}, ${sqlString(uniqueName("temporary group category"))}, ${sqlUuid(communityId)});

    insert into community_team (community_id, user_id, accepted, role)
    values (${sqlUuid(communityId)}, ${sqlUuid(userId)}, true, ${sqlString(teamRole)});
  `);

  return { communityId, displayName, groupCategoryId };
};
