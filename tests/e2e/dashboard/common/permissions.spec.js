import { randomUUID } from "node:crypto";
import { expect, test } from "../../fixtures.js";
import { queryE2eDatabase, queryE2eDatabaseRows } from "../../database.js";
import { cleanupEventsByIds } from "../../data-graphs/events.js";
import { cleanupOwnedPaymentPurchase, setupExternalRefundRequestGraph } from "../../data-graphs/payments.js";
import {
  TEST_COMMUNITY_DESCRIPTION,
  TEST_COMMUNITY_IDS,
  TEST_COMMUNITY_TITLE,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_PAYMENT_EVENT_IDS,
  TEST_USER_IDS,
} from "../../seed.js";
import { buildE2eUrl, futureDate, uniqueName } from "../../utils.js";

const ADMIN1_USER_ID = "77777777-7777-7777-7777-777777777701";

const BADGE_ARTWORK_FILE_NAME = "e2e-disposable-badge.png";

const COMMUNITY_BANNER_MOBILE_URL = "/static/images/e2e/community-primary-banner-mobile.svg";

const COMMUNITY_BANNER_URL = "/static/images/e2e/community-primary-banner.svg";

const COMMUNITY_LOGO_URL = "/static/images/e2e/community-primary-logo.svg";

const EVENT_CATEGORY_ID = "33333333-3333-3333-3333-333333333331";

const EVENTS_MANAGER_USER_ID = "77777777-7777-7777-7777-777777777711";

const GROUP_CATEGORY_ID = "22222222-2222-2222-2222-222222222221";

const INVITATION_REDIRECT_STATUS = 303;

const PRIMARY_COMMUNITY_ID = TEST_COMMUNITY_IDS.community1;

const PRIMARY_GROUP_ID = TEST_GROUP_IDS.community1.alpha;

const TEMP_PASSWORD_HASH =
  "$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g";

const COMMUNITY_ROLES = {
  adminCommunityPage: {
    buckets: {
      groups: true,
      settings: true,
      taxonomy: true,
      team: true,
    },
    roleName: "community admin",
    userId: ADMIN1_USER_ID,
  },
  communityViewerPage: {
    buckets: {
      groups: false,
      settings: false,
      taxonomy: false,
      team: false,
    },
    roleName: "community viewer",
  },
  groupsManagerPage: {
    buckets: {
      groups: true,
      settings: false,
      taxonomy: false,
      team: false,
    },
    roleName: "groups-manager",
    userId: TEST_USER_IDS.communityGroupsManager1,
  },
  member2Page: {
    buckets: {
      groups: false,
      settings: false,
      taxonomy: false,
      team: false,
    },
    redirectsWithoutContext: true,
    roleName: "plain member",
  },
};

const GROUP_ROLES = {
  adminCommunityPage: {
    buckets: {
      badges: true,
      checkIns: true,
      events: true,
      notifications: true,
      refunds: true,
      settings: true,
      sponsors: true,
      team: true,
    },
    roleName: "community admin",
  },
  checkInManagerGroupPage: {
    buckets: {
      badges: false,
      checkIns: true,
      events: false,
      notifications: false,
      refunds: false,
      settings: false,
      sponsors: false,
      team: false,
    },
    groupRole: "check-in-manager",
    roleName: "check-in manager",
    userId: TEST_USER_IDS.checkInManager1,
  },
  eventsManagerGroupPage: {
    buckets: {
      badges: true,
      checkIns: true,
      events: true,
      notifications: false,
      refunds: true,
      settings: false,
      sponsors: false,
      team: false,
    },
    groupRole: "events-manager",
    roleName: "events-manager",
    userId: EVENTS_MANAGER_USER_ID,
  },
  groupViewerPage: {
    buckets: {
      badges: false,
      checkIns: false,
      events: false,
      notifications: false,
      refunds: false,
      settings: false,
      sponsors: false,
      team: false,
    },
    roleName: "group viewer",
  },
  groupsManagerPage: {
    buckets: {
      badges: true,
      checkIns: true,
      events: true,
      notifications: true,
      refunds: true,
      settings: true,
      sponsors: true,
      team: true,
    },
    roleName: "groups-manager",
  },
  member1Page: {
    buckets: {
      badges: false,
      checkIns: false,
      events: false,
      notifications: false,
      refunds: false,
      settings: false,
      sponsors: false,
      team: false,
    },
    redirectsWithoutContext: true,
    roleName: "plain member",
  },
  organizerGroupPage: {
    buckets: {
      badges: true,
      checkIns: true,
      events: true,
      notifications: true,
      refunds: true,
      settings: true,
      sponsors: true,
      team: true,
    },
    groupRole: "admin",
    roleName: "organizer",
    userId: TEST_USER_IDS.organizer1,
  },
};

const COMMUNITY_BUCKETS = [
  {
    key: "groups",
    name: "groups",
    successStatus: 201,
    createOperation: createCommunityGroupOperation,
  },
  {
    key: "settings",
    name: "settings",
    successStatus: 204,
    createOperation: createCommunitySettingsOperation,
  },
  {
    key: "taxonomy",
    name: "taxonomy",
    successStatus: 201,
    createOperation: createCommunityTaxonomyOperation,
  },
  {
    key: "team",
    name: "team",
    successStatus: 201,
    createOperation: createCommunityTeamOperation,
  },
];

const GROUP_BUCKETS = [
  {
    key: "badges",
    name: "badges",
    successStatus: 201,
    createOperation: createGroupBadgesOperation,
  },
  {
    key: "events",
    name: "events",
    successStatus: 201,
    createOperation: createGroupEventsOperation,
  },
  {
    key: "notifications",
    name: "notifications",
    successStatus: 204,
    createOperation: createGroupNotificationsOperation,
  },
  {
    key: "settings",
    name: "settings",
    successStatus: 204,
    createOperation: createGroupSettingsOperation,
  },
  {
    key: "sponsors",
    name: "sponsors",
    successStatus: 201,
    createOperation: createGroupSponsorsOperation,
  },
  {
    key: "team",
    name: "team",
    successStatus: 201,
    createOperation: createGroupTeamOperation,
  },
  {
    key: "checkIns",
    name: "attendees/check-in",
    successStatus: 204,
    createOperation: createGroupCheckInsOperation,
  },
  {
    key: "refunds",
    name: "refunds",
    successStatus: 204,
    createOperation: createGroupRefundsOperation,
  },
];

/** Returns community permission cases for the requested fixture. */
const communityCasesForFixture = (fixture) =>
  COMMUNITY_BUCKETS.map((bucket) => ({
    bucket,
    expectedStatus: expectedCommunityStatus(COMMUNITY_ROLES[fixture], bucket),
    fixture,
    role: COMMUNITY_ROLES[fixture],
  }));

/** Returns group permission cases for the requested fixture. */
const groupCasesForFixture = (fixture) =>
  GROUP_BUCKETS.map((bucket) => ({
    bucket,
    expectedStatus: expectedGroupStatus(GROUP_ROLES[fixture], bucket),
    fixture,
    role: GROUP_ROLES[fixture],
  }));

/** Builds a community group POST operation that creates or preserves a group and cleans up. */
function createCommunityGroupOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const community = allowed ? setupTemporaryCommunity(role, "community group") : null;
  const name = uniqueName("permission community group");
  let groupId;

  return {
    communityId: community?.communityId ?? (role.redirectsWithoutContext ? null : PRIMARY_COMMUNITY_ID),
    form: communityGroupForm(name, community?.groupCategoryId ?? GROUP_CATEGORY_ID),
    method: "POST",
    path: "/dashboard/community/groups/add",
    assertEffect: async (before, page) => {
      const after = countGroupsByName(name);
      if (!allowed) {
        expect(after).toBe(before);
        return;
      }

      expect(after).toBe(1);
      groupId = findGroupIdByName(name);
      expect(groupId).toBeTruthy();

      if (role.roleName === "groups-manager") {
        const deleteResponse = await page.request.delete(
          buildE2eUrl(`/dashboard/community/groups/${groupId}/delete`),
        );
        expect(deleteResponse.status()).toBe(204);
      }
    },
    cleanup: () => {
      if (groupId) {
        cleanupTemporaryGroup(groupId);
      }
      community?.cleanup();
    },
    readEffect: () => countGroupsByName(name),
  };
}

/** Builds a community settings PUT operation that updates new group details and cleans up. */
function createCommunitySettingsOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const community = allowed ? setupTemporaryCommunity(role, "community settings") : null;
  const communityId = community?.communityId ?? PRIMARY_COMMUNITY_ID;
  const newGroupDetails = uniqueName("permission community settings");

  return {
    communityId: role.redirectsWithoutContext ? null : communityId,
    form: communitySettingsForm(newGroupDetails, community),
    method: "PUT",
    path: "/dashboard/community/settings/update",
    assertEffect: (before) => {
      const after = communityNewGroupDetails(communityId);
      expect(after).toBe(allowed ? newGroupDetails : before);
    },
    cleanup: () => community?.cleanup(),
    readEffect: () => communityNewGroupDetails(communityId),
  };
}

/** Builds a community taxonomy POST operation that creates a category and cleans up. */
function createCommunityTaxonomyOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const community = allowed ? setupTemporaryCommunity(role, "community taxonomy") : null;
  const name = uniqueName("permission event category");
  let eventCategoryId;

  return {
    communityId: community?.communityId ?? (role.redirectsWithoutContext ? null : PRIMARY_COMMUNITY_ID),
    form: { name },
    method: "POST",
    path: "/dashboard/community/event-categories/add",
    assertEffect: (before) => {
      const after = countEventCategoriesByName(name);
      if (!allowed) {
        expect(after).toBe(before);
        return;
      }

      expect(after).toBe(1);
      eventCategoryId = findEventCategoryIdByName(name);
      expect(eventCategoryId).toBeTruthy();
    },
    cleanup: () => {
      if (eventCategoryId) {
        queryE2eDatabase(`delete from event_category where event_category_id = ${sqlUuid(eventCategoryId)};`);
      }
      community?.cleanup();
    },
    readEffect: () => countEventCategoriesByName(name),
  };
}

/** Builds a community team POST operation that invites a user and cleans up notifications. */
function createCommunityTeamOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const community = allowed ? setupTemporaryCommunity(role, "community team") : null;
  const communityId = community?.communityId ?? PRIMARY_COMMUNITY_ID;
  const targetUser = setupTemporaryUser("community-team-target");
  let newNotificationIds = [];

  return {
    communityId: role.redirectsWithoutContext ? null : communityId,
    form: { role: "viewer", user_id: targetUser.userId },
    method: "POST",
    path: "/dashboard/community/team/add",
    assertEffect: (before) => {
      const after = countCommunityTeamMember(communityId, targetUser.userId);
      expect(after).toBe(allowed ? 1 : before.count);
      newNotificationIds = newNotificationIdsForUser(
        before.notificationIds,
        targetUser.userId,
        "community-team-invitation",
      );
    },
    cleanup: () => {
      deleteNotificationsByIds(newNotificationIds);
      queryE2eDatabase(`
        delete from community_team
        where community_id = ${sqlUuid(communityId)}
        and user_id = ${sqlUuid(targetUser.userId)};
      `);
      community?.cleanup();
      targetUser.cleanup();
    },
    readEffect: () => ({
      count: countCommunityTeamMember(communityId, targetUser.userId),
      notificationIds: notificationIdsForUser(targetUser.userId, "community-team-invitation"),
    }),
  };
}

/** Builds a group badges POST operation that creates a badge and cleans up. */
function createGroupBadgesOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const group = allowed ? setupTemporaryGroup(role, { withArtwork: true }) : null;
  const badgeName = uniqueName("permission badge");
  let badgeId;

  return {
    form: {
      criteria: "Complete the RBAC matrix scenario.",
      description: "Badge created by dashboard permission coverage.",
      image_file_name: BADGE_ARTWORK_FILE_NAME,
      name: badgeName,
    },
    groupId: group?.groupId ?? (role.redirectsWithoutContext ? null : PRIMARY_GROUP_ID),
    method: "POST",
    path: "/dashboard/group/badges",
    assertEffect: (before) => {
      const after = countBadgesByName(badgeName);
      if (!allowed) {
        expect(after).toBe(before);
        return;
      }

      expect(after).toBe(1);
      badgeId = findBadgeIdByName(badgeName);
      expect(badgeId).toBeTruthy();
    },
    cleanup: () => {
      if (badgeId) {
        queryE2eDatabase(`delete from badge where badge_id = ${sqlUuid(badgeId)};`);
      }
      group?.cleanup();
    },
    readEffect: () => countBadgesByName(badgeName),
  };
}

/** Builds a group events POST operation that creates an event and cleans up. */
function createGroupEventsOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const group = allowed ? setupTemporaryGroup(role) : null;
  const eventName = uniqueName("permission event");
  let eventIds = [];

  return {
    form: eventForm(eventName),
    groupId: group?.groupId ?? (role.redirectsWithoutContext ? null : PRIMARY_GROUP_ID),
    method: "POST",
    path: "/dashboard/group/events/add",
    assertEffect: (before) => {
      const after = countEventsByName(eventName);
      if (!allowed) {
        expect(after).toBe(before);
        return;
      }

      expect(after).toBe(1);
      eventIds = findEventIdsByName(eventName);
      expect(eventIds).toHaveLength(1);
    },
    cleanup: () => {
      cleanupEventsByIds(eventIds);
      group?.cleanup();
    },
    readEffect: () => countEventsByName(eventName),
  };
}

/** Builds a group notifications POST operation that sends notices and cleans up. */
function createGroupNotificationsOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const notificationTarget = allowed ? setupTemporaryUser("group-notification-target") : null;
  const group = allowed ? setupTemporaryGroup(role, { memberUserId: notificationTarget.userId }) : null;
  const subject = uniqueName("permission notification");
  let newNotificationIds = [];

  return {
    form: {
      body: "This notification verifies the group members permission bucket.",
      subject,
    },
    groupId: group?.groupId ?? (role.redirectsWithoutContext ? null : PRIMARY_GROUP_ID),
    method: "POST",
    path: "/dashboard/group/notifications",
    assertEffect: (before) => {
      const after = countGroupCustomNotificationsBySubject(subject);
      if (!allowed) {
        expect(after).toBe(before);
        return;
      }

      expect(after).toBe(1);
      newNotificationIds = notificationIdsForTemplateSubject(subject);
      expect(newNotificationIds.length).toBeGreaterThan(0);
    },
    cleanup: () => {
      deleteNotificationsByIds(newNotificationIds);
      deleteGroupCustomNotificationBySubject(subject);
      group?.cleanup();
      notificationTarget?.cleanup();
    },
    readEffect: () => countGroupCustomNotificationsBySubject(subject),
  };
}

/** Builds a group settings PUT operation that updates the description and cleans up. */
function createGroupSettingsOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const group = allowed ? setupTemporaryGroup(role) : null;
  const groupId = group?.groupId ?? PRIMARY_GROUP_ID;
  const description = uniqueName("permission group settings");

  return {
    form: groupForm({
      categoryId: GROUP_CATEGORY_ID,
      description,
      name: group?.groupName ?? TEST_GROUP_NAMES.alpha,
    }),
    groupId: role.redirectsWithoutContext ? null : groupId,
    method: "PUT",
    path: "/dashboard/group/settings/update",
    assertEffect: (before) => {
      const after = groupDescription(groupId);
      expect(after).toBe(allowed ? description : before);
    },
    cleanup: () => group?.cleanup(),
    readEffect: () => groupDescription(groupId),
  };
}

/** Builds a group sponsors POST operation that creates a sponsor and cleans up. */
function createGroupSponsorsOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const group = allowed ? setupTemporaryGroup(role) : null;
  const sponsorName = uniqueName("permission sponsor");
  let sponsorId;

  return {
    form: {
      featured: "true",
      logo_url: "/static/images/e2e/sponsor-logo.svg",
      name: sponsorName,
      website_url: "https://example.com/permission-sponsor",
    },
    groupId: group?.groupId ?? (role.redirectsWithoutContext ? null : PRIMARY_GROUP_ID),
    method: "POST",
    path: "/dashboard/group/sponsors/add",
    assertEffect: (before) => {
      const after = countSponsorsByName(sponsorName);
      if (!allowed) {
        expect(after).toBe(before);
        return;
      }

      expect(after).toBe(1);
      sponsorId = findSponsorIdByName(sponsorName);
      expect(sponsorId).toBeTruthy();
    },
    cleanup: () => {
      if (sponsorId) {
        queryE2eDatabase(`delete from group_sponsor where group_sponsor_id = ${sqlUuid(sponsorId)};`);
      }
      group?.cleanup();
    },
    readEffect: () => countSponsorsByName(sponsorName),
  };
}

/** Builds a group team POST operation that invites a user and cleans up notifications. */
function createGroupTeamOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const group = allowed ? setupTemporaryGroup(role) : null;
  const groupId = group?.groupId ?? PRIMARY_GROUP_ID;
  const targetUser = setupTemporaryUser("group-team-target");
  let newNotificationIds = [];

  return {
    form: { role: "viewer", user_id: targetUser.userId },
    groupId: role.redirectsWithoutContext ? null : groupId,
    method: "POST",
    path: "/dashboard/group/team/add",
    assertEffect: (before) => {
      const after = countGroupTeamMember(groupId, targetUser.userId);
      expect(after).toBe(allowed ? 1 : before.count);
      newNotificationIds = newNotificationIdsForUser(
        before.notificationIds,
        targetUser.userId,
        "group-team-invitation",
      );
    },
    cleanup: () => {
      deleteNotificationsByIds(newNotificationIds);
      queryE2eDatabase(`
        delete from group_team
        where group_id = ${sqlUuid(groupId)}
        and user_id = ${sqlUuid(targetUser.userId)};
      `);
      group?.cleanup();
      targetUser.cleanup();
    },
    readEffect: () => ({
      count: countGroupTeamMember(groupId, targetUser.userId),
      notificationIds: notificationIdsForUser(targetUser.userId, "group-team-invitation"),
    }),
  };
}

/** Builds a group check-in POST operation that marks attendance and cleans up. */
function createGroupCheckInsOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const graph = setupCheckInGraph();

  return {
    groupId: role.redirectsWithoutContext ? null : PRIMARY_GROUP_ID,
    method: "POST",
    path: `/dashboard/group/events/${graph.eventId}/attendees/${graph.userId}/check-in`,
    assertEffect: (before) => {
      const after = attendeeCheckedIn(graph.eventId, graph.userId);
      expect(after).toBe(allowed ? "true" : before);
    },
    cleanup: () => graph.cleanup(),
    readEffect: () => attendeeCheckedIn(graph.eventId, graph.userId),
  };
}

/** Builds a group refunds PUT operation that approves a refund and cleans up. */
function createGroupRefundsOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const refundUser = setupTemporaryUser("refund-request-owner");
  const notificationIds = notificationIdsForUser(refundUser.userId, "event-refund-approved");
  const graph = setupExternalRefundRequestGraph({
    eventId: TEST_PAYMENT_EVENT_IDS.refunds,
    requestedReason: uniqueName("permission refund"),
    userId: refundUser.userId,
  });
  let newNotificationIds = [];

  return {
    form: { review_note: "Approved by permission matrix" },
    groupId: role.redirectsWithoutContext ? null : PRIMARY_GROUP_ID,
    method: "PUT",
    path: `/dashboard/group/refunds/${graph.purchaseId}/approve`,
    assertEffect: (before) => {
      const after = refundRequestStatus(graph.purchaseId);
      expect(after).toBe(allowed ? "approved" : before);
      newNotificationIds = newNotificationIdsForUser(
        notificationIds,
        refundUser.userId,
        "event-refund-approved",
      );
    },
    cleanup: () => {
      deleteNotificationsByIds(newNotificationIds);
      cleanupOwnedPaymentPurchase(graph);
      refundUser.cleanup();
    },
    readEffect: () => refundRequestStatus(graph.purchaseId),
  };
}

/** Returns the permission label for an expected status. */
function statusLabel(status) {
  if (status === 403) {
    return "forbids";
  }
  if (status === INVITATION_REDIRECT_STATUS) {
    return "redirects from";
  }

  return "allows";
}

test.describe("dashboard permission matrix", () => {
  test("community select allows the seeded cross-community viewer context", async ({
    adminCommunityPage,
  }) => {
    // Select the secondary community with the primary admin's seeded viewer role.
    const response = await adminCommunityPage.request.put(
      buildE2eUrl(`/dashboard/community/${TEST_COMMUNITY_IDS.community2}/select`),
    );

    // Verify the path-community read guard accepts the foreign viewer role.
    expect(response.status()).toBe(204);
  });

  test("community select forbids a community without a team role", async ({ communityViewerPage }) => {
    // The community1 viewer has no community_team row for the secondary community.
    const response = await communityViewerPage.request.put(
      buildE2eUrl(`/dashboard/community/${TEST_COMMUNITY_IDS.community2}/select`),
    );

    // Verify user_has_path_community_permission rejects the foreign community outright.
    expect(response.status()).toBe(403);
  });

  for (const matrixCase of communityCasesForFixture("adminCommunityPage")) {
    test(`${matrixCase.role.roleName} ${statusLabel(matrixCase.expectedStatus)} community ${matrixCase.bucket.name} writes`, async ({
      adminCommunityPage,
    }) => {
      await runCommunityCase(matrixCase, adminCommunityPage);
    });
  }

  for (const matrixCase of communityCasesForFixture("communityViewerPage")) {
    test(`${matrixCase.role.roleName} ${statusLabel(matrixCase.expectedStatus)} community ${matrixCase.bucket.name} writes`, async ({
      communityViewerPage,
    }) => {
      await runCommunityCase(matrixCase, communityViewerPage);
    });
  }

  for (const matrixCase of communityCasesForFixture("groupsManagerPage")) {
    test(`${matrixCase.role.roleName} ${statusLabel(matrixCase.expectedStatus)} community ${matrixCase.bucket.name} writes`, async ({
      groupsManagerPage,
    }) => {
      await runCommunityCase(matrixCase, groupsManagerPage);
    });
  }

  for (const matrixCase of communityCasesForFixture("member2Page")) {
    test(`${matrixCase.role.roleName} ${statusLabel(matrixCase.expectedStatus)} community ${matrixCase.bucket.name} writes`, async ({
      member2Page,
    }) => {
      await runCommunityCase(matrixCase, member2Page);
    });
  }

  for (const matrixCase of groupCasesForFixture("adminCommunityPage")) {
    test(`${matrixCase.role.roleName} ${statusLabel(matrixCase.expectedStatus)} group ${matrixCase.bucket.name} writes`, async ({
      adminCommunityPage,
    }) => {
      await runGroupCase(matrixCase, adminCommunityPage);
    });
  }

  for (const matrixCase of groupCasesForFixture("checkInManagerGroupPage")) {
    test(`${matrixCase.role.roleName} ${statusLabel(matrixCase.expectedStatus)} group ${matrixCase.bucket.name} writes`, async ({
      checkInManagerGroupPage,
    }) => {
      await runGroupCase(matrixCase, checkInManagerGroupPage);
    });
  }

  for (const matrixCase of groupCasesForFixture("eventsManagerGroupPage")) {
    test(`${matrixCase.role.roleName} ${statusLabel(matrixCase.expectedStatus)} group ${matrixCase.bucket.name} writes`, async ({
      eventsManagerGroupPage,
    }) => {
      await runGroupCase(matrixCase, eventsManagerGroupPage);
    });
  }

  for (const matrixCase of groupCasesForFixture("groupViewerPage")) {
    test(`${matrixCase.role.roleName} ${statusLabel(matrixCase.expectedStatus)} group ${matrixCase.bucket.name} writes`, async ({
      groupViewerPage,
    }) => {
      await runGroupCase(matrixCase, groupViewerPage);
    });
  }

  for (const matrixCase of groupCasesForFixture("groupsManagerPage")) {
    test(`${matrixCase.role.roleName} ${statusLabel(matrixCase.expectedStatus)} group ${matrixCase.bucket.name} writes`, async ({
      groupsManagerPage,
    }) => {
      await runGroupCase(matrixCase, groupsManagerPage);
    });
  }

  for (const matrixCase of groupCasesForFixture("member1Page")) {
    test(`${matrixCase.role.roleName} ${statusLabel(matrixCase.expectedStatus)} group ${matrixCase.bucket.name} writes`, async ({
      member1Page,
    }) => {
      await runGroupCase(matrixCase, member1Page);
    });
  }

  for (const matrixCase of groupCasesForFixture("organizerGroupPage")) {
    test(`${matrixCase.role.roleName} ${statusLabel(matrixCase.expectedStatus)} group ${matrixCase.bucket.name} writes`, async ({
      organizerGroupPage,
    }) => {
      await runGroupCase(matrixCase, organizerGroupPage);
    });
  }
});

/** Returns the checked_in value from event_attendee. */
function attendeeCheckedIn(eventId, userId) {
  return queryScalar(`
    select checked_in::text
    from event_attendee
    where event_id = ${sqlUuid(eventId)}
    and user_id = ${sqlUuid(userId)}
  `);
}

/** Deletes community, community_team, event_category, region, and group_category rows. */
function cleanupTemporaryCommunity(communityId) {
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
}

/** Deletes group rows and dependent badge, sponsor, notification, member, and team rows. */
function cleanupTemporaryGroup(groupId) {
  const eventIds = eventIdsByGroup(groupId);
  cleanupEventsByIds(eventIds);

  queryE2eDatabase(`
    delete from badge where group_id = ${sqlUuid(groupId)};
    delete from badge_artwork where group_id = ${sqlUuid(groupId)};
    delete from group_sponsor where group_id = ${sqlUuid(groupId)};
    delete from custom_notification where group_id = ${sqlUuid(groupId)};
    delete from group_member where group_id = ${sqlUuid(groupId)};
    delete from group_team where group_id = ${sqlUuid(groupId)};
    delete from "group" where group_id = ${sqlUuid(groupId)};
  `);
}

/** Deletes notification, event_attendee, group_member, group_team, community_team, and user rows. */
function cleanupTemporaryUser(userId) {
  queryE2eDatabase(`
    delete from notification where user_id = ${sqlUuid(userId)};
    delete from event_attendee where user_id = ${sqlUuid(userId)};
    delete from group_member where user_id = ${sqlUuid(userId)};
    delete from group_team where user_id = ${sqlUuid(userId)};
    delete from community_team where user_id = ${sqlUuid(userId)};
    delete from "user" where user_id = ${sqlUuid(userId)};
  `);
}

/** Builds the community group form payload. */
function communityGroupForm(name, categoryId) {
  return groupForm({
    categoryId,
    description: "Temporary group created by dashboard permission coverage.",
    name,
  });
}

/** Returns the new_group_details value from community. */
function communityNewGroupDetails(communityId) {
  return queryScalar(`
    select coalesce(new_group_details, '')
    from community
    where community_id = ${sqlUuid(communityId)}
  `);
}

/** Builds the community settings form payload. */
function communitySettingsForm(newGroupDetails, community) {
  return {
    banner_mobile_url: community ? COMMUNITY_BANNER_MOBILE_URL : COMMUNITY_BANNER_MOBILE_URL,
    banner_url: community ? COMMUNITY_BANNER_URL : COMMUNITY_BANNER_URL,
    description: community?.displayName ?? TEST_COMMUNITY_DESCRIPTION,
    display_name: community?.displayName ?? TEST_COMMUNITY_TITLE,
    group_team_management_restricted: "false",
    logo_url: COMMUNITY_LOGO_URL,
    new_group_details: newGroupDetails,
  };
}

/** Counts badge rows matching a badge name. */
function countBadgesByName(name) {
  return queryCount(`select count(*) from badge where name = ${sqlString(name)};`);
}

/** Counts community_team rows for a community user. */
function countCommunityTeamMember(communityId, userId) {
  return queryCount(`
    select count(*)
    from community_team
    where community_id = ${sqlUuid(communityId)}
    and user_id = ${sqlUuid(userId)};
  `);
}

/** Counts event_category rows matching a category name. */
function countEventCategoriesByName(name) {
  return queryCount(`select count(*) from event_category where name = ${sqlString(name)};`);
}

/** Counts non-deleted event rows matching an event name. */
function countEventsByName(name) {
  return queryCount(`select count(*) from event where name = ${sqlString(name)} and deleted = false;`);
}

/** Counts custom_notification rows matching a subject. */
function countGroupCustomNotificationsBySubject(subject) {
  return queryCount(`select count(*) from custom_notification where subject = ${sqlString(subject)};`);
}

/** Counts non-deleted group rows matching a group name. */
function countGroupsByName(name) {
  return queryCount(`select count(*) from "group" where name = ${sqlString(name)} and deleted = false;`);
}

/** Counts group_team rows for a group user. */
function countGroupTeamMember(groupId, userId) {
  return queryCount(`
    select count(*)
    from group_team
    where group_id = ${sqlUuid(groupId)}
    and user_id = ${sqlUuid(userId)};
  `);
}

/** Counts group_sponsor rows matching a sponsor name. */
function countSponsorsByName(name) {
  return queryCount(`select count(*) from group_sponsor where name = ${sqlString(name)};`);
}

/** Deletes custom_notification rows matching a subject. */
function deleteGroupCustomNotificationBySubject(subject) {
  queryE2eDatabase(`delete from custom_notification where subject = ${sqlString(subject)};`);
}

/** Deletes notification rows matching notification IDs. */
function deleteNotificationsByIds(notificationIds) {
  if (notificationIds.length === 0) {
    return;
  }

  queryE2eDatabase(`delete from notification where notification_id in (${sqlUuidList(notificationIds)});`);
}

/** Builds the event creation form payload. */
function eventForm(name) {
  return {
    category_id: EVENT_CATEGORY_ID,
    description: "Temporary event created by dashboard permission coverage.",
    description_short: "Temporary event created by permission coverage.",
    // The server parses timestamps with seconds, as the event form JS submits them.
    ends_at: `${futureDate({ days: 210, hour: 12 })}:00`,
    kind_id: "virtual",
    name,
    starts_at: `${futureDate({ days: 210, hour: 10 })}:00`,
    "ticket_types[0][active]": "true",
    "ticket_types[0][availability]": "public",
    "ticket_types[0][order]": "1",
    "ticket_types[0][price_windows][0][amount_minor]": "0",
    "ticket_types[0][seats_total]": "500",
    "ticket_types[0][title]": "General Admission",
    ticket_types_present: "true",
    timezone: "UTC",
  };
}

/** Returns event IDs from event rows for a group. */
function eventIdsByGroup(groupId) {
  return queryE2eDatabaseRows(`select event_id from event where group_id = ${sqlUuid(groupId)};`).map(
    ([eventId]) => eventId,
  );
}

/** Returns the expected community permission status for a role and bucket. */
function expectedCommunityStatus(role, bucket) {
  if (role.redirectsWithoutContext) {
    return INVITATION_REDIRECT_STATUS;
  }

  return role.buckets[bucket.key] ? bucket.successStatus : 403;
}

/** Returns the expected group permission status for a role and bucket. */
function expectedGroupStatus(role, bucket) {
  if (role.redirectsWithoutContext) {
    return INVITATION_REDIRECT_STATUS;
  }

  return role.buckets[bucket.key] ? bucket.successStatus : 403;
}

/** Returns a badge_id from badge for a badge name. */
function findBadgeIdByName(name) {
  return queryScalar(`select badge_id from badge where name = ${sqlString(name)};`);
}

/** Returns an event_category_id from event_category for a name. */
function findEventCategoryIdByName(name) {
  return queryScalar(`select event_category_id from event_category where name = ${sqlString(name)};`);
}

/** Returns event IDs from event rows for an event name. */
function findEventIdsByName(name) {
  return queryE2eDatabaseRows(`select event_id from event where name = ${sqlString(name)};`).map(
    ([eventId]) => eventId,
  );
}

/** Returns a group_id from group for a group name. */
function findGroupIdByName(name) {
  return queryScalar(`select group_id from "group" where name = ${sqlString(name)};`);
}

/** Returns a group_sponsor_id from group_sponsor for a sponsor name. */
function findSponsorIdByName(name) {
  return queryScalar(`select group_sponsor_id from group_sponsor where name = ${sqlString(name)};`);
}

/** Returns the description value from group. */
function groupDescription(groupId) {
  return queryScalar(`select coalesce(description, '') from "group" where group_id = ${sqlUuid(groupId)};`);
}

/** Builds the group form payload. */
function groupForm({ categoryId, description, name }) {
  return {
    category_id: categoryId,
    description,
    name,
  };
}

/** Returns group IDs from group rows for a community. */
function groupIdsByCommunity(communityId) {
  return queryE2eDatabaseRows(
    `select group_id from "group" where community_id = ${sqlUuid(communityId)};`,
  ).map(([groupId]) => groupId);
}

/** Returns whether a response status represents an allowed write. */
function isAllowed(status) {
  return status === 200 || status === 201 || status === 204;
}

/** Returns notification IDs for a user and kind that were not present before. */
function newNotificationIdsForUser(beforeIds, userId, kind) {
  const before = new Set(beforeIds);

  return notificationIdsForUser(userId, kind).filter((notificationId) => !before.has(notificationId));
}

/** Returns notification IDs joined through notification_template_data for a subject. */
function notificationIdsForTemplateSubject(subject) {
  return queryE2eDatabaseRows(`
    select n.notification_id
    from notification n
    join notification_template_data ntd using (notification_template_data_id)
    where ntd.data->>'subject' = ${sqlString(subject)}
    order by n.notification_id;
  `).map(([notificationId]) => notificationId);
}

/** Returns notification IDs from notification for a user and kind. */
function notificationIdsForUser(userId, kind) {
  return queryE2eDatabaseRows(`
    select notification_id
    from notification
    where user_id = ${sqlUuid(userId)}
    and kind = ${sqlString(kind)}
    order by notification_id;
  `).map(([notificationId]) => notificationId);
}

/** Returns a numeric count from a scalar SQL query. */
function queryCount(sql) {
  return Number(queryScalar(sql));
}

/** Returns the first scalar value from an E2E SQL query. */
function queryScalar(sql) {
  return queryE2eDatabaseRows(sql).at(0)?.at(0) ?? "";
}

/** Returns the status from event_refund_request for a purchase. */
function refundRequestStatus(purchaseId) {
  return queryScalar(`
    select status
    from event_refund_request
    where event_purchase_id = ${sqlUuid(purchaseId)};
  `);
}

/** Runs a community permission request and cleans up its representative effect. */
const runCommunityCase = async (matrixCase, page) => {
  const operation = matrixCase.bucket.createOperation(matrixCase.role, matrixCase.expectedStatus);
  let before;

  try {
    if (operation.communityId) {
      await selectCommunityForRequest(page, operation.communityId);
    }

    before = operation.readEffect();

    // Send the representative request through the selected community context.
    const response = await sendDashboardRequest(page, operation, matrixCase.expectedStatus);

    expect(response.status(), await response.text()).toBe(matrixCase.expectedStatus);
    await operation.assertEffect(before, page, matrixCase.expectedStatus);
  } finally {
    operation.cleanup?.();
  }
};

/** Runs a group permission request and cleans up its representative effect. */
const runGroupCase = async (matrixCase, page) => {
  const operation = matrixCase.bucket.createOperation(matrixCase.role, matrixCase.expectedStatus);
  let before;

  try {
    if (operation.groupId) {
      await selectGroupForRequest(page, operation.groupId);
    }

    before = operation.readEffect();

    // Send the representative request through the selected group context.
    const response = await sendDashboardRequest(page, operation, matrixCase.expectedStatus);

    expect(response.status(), await response.text()).toBe(matrixCase.expectedStatus);
    operation.assertEffect(before, matrixCase.expectedStatus);
  } finally {
    operation.cleanup?.();
  }
};

/** Selects the community context required before sending a dashboard request. */
async function selectCommunityForRequest(page, communityId) {
  const response = await page.request.put(buildE2eUrl(`/dashboard/community/${communityId}/select`));
  expect(response.status()).toBe(204);
}

/** Selects the community and group contexts before sending a dashboard request. */
async function selectGroupForRequest(page, groupId) {
  const communityResponse = await page.request.put(
    buildE2eUrl(`/dashboard/group/community/${PRIMARY_COMMUNITY_ID}/select`),
  );
  expect(communityResponse.status()).toBe(204);

  const groupResponse = await page.request.put(buildE2eUrl(`/dashboard/group/${groupId}/select`));
  expect(groupResponse.status()).toBe(204);
}

/** Sends a dashboard request with form data and redirect handling. */
async function sendDashboardRequest(page, operation, expectedStatus) {
  const options = { method: operation.method };

  if (operation.form) {
    options.form = operation.form;
  }
  if (expectedStatus === INVITATION_REDIRECT_STATUS) {
    options.maxRedirects = 0;
  }

  return page.request.fetch(buildE2eUrl(operation.path), options);
}

/** Creates event, event_ticket_type, event_ticket_price_window, and event_attendee rows. */
function setupCheckInGraph() {
  const eventId = randomUUID();
  const attendee = setupTemporaryUser("check-in-attendee");
  const ticketPriceWindowId = randomUUID();
  const ticketTypeId = randomUUID();
  const userId = attendee.userId;
  const name = uniqueName("permission check-in");
  const slug = `permission-check-in-${shortId(eventId)}`;

  queryE2eDatabase(`
    insert into event (
      event_id,
      group_id,
      name,
      slug,
      description,
      description_short,
      timezone,
      event_category_id,
      event_kind_id,
      published,
      published_at,
      starts_at,
      ends_at,
      created_by
    ) values (
      ${sqlUuid(eventId)},
      ${sqlUuid(PRIMARY_GROUP_ID)},
      ${sqlString(name)},
      ${sqlString(slug)},
      'Temporary event owned by dashboard permission coverage.',
      'Temporary event owned by dashboard permission coverage.',
      'UTC',
      ${sqlUuid(EVENT_CATEGORY_ID)},
      'virtual',
      true,
      current_timestamp,
      current_timestamp + interval '1 day',
      current_timestamp + interval '1 day 2 hours',
      ${sqlUuid(ADMIN1_USER_ID)}
    );

    insert into event_ticket_type (
      event_ticket_type_id,
      active,
      availability,
      event_id,
      "order",
      seats_total,
      title,
      description
    ) values (
      ${sqlUuid(ticketTypeId)},
      true,
      'public',
      ${sqlUuid(eventId)},
      1,
      500,
      'General Admission',
      'Temporary free admission used by dashboard permission coverage.'
    );

    insert into event_ticket_price_window (
      event_ticket_price_window_id,
      amount_minor,
      event_ticket_type_id
    ) values (
      ${sqlUuid(ticketPriceWindowId)},
      0,
      ${sqlUuid(ticketTypeId)}
    );

    insert into event_attendee (event_id, user_id, status)
    values (${sqlUuid(eventId)}, ${sqlUuid(userId)}, 'confirmed');
  `);

  return {
    eventId,
    userId,
    cleanup: () => {
      cleanupEventsByIds([eventId]);
      attendee.cleanup();
    },
  };
}

/** Creates community, group_category, and community_team rows for permission tests. */
function setupTemporaryCommunity(role, label) {
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
      'Temporary community owned by dashboard permission coverage.',
      ${sqlString(COMMUNITY_BANNER_URL)},
      ${sqlString(COMMUNITY_BANNER_MOBILE_URL)},
      ${sqlString(COMMUNITY_LOGO_URL)}
    );

    insert into group_category (group_category_id, name, community_id)
    values (${sqlUuid(groupCategoryId)}, ${sqlString(uniqueName("permission group category"))}, ${sqlUuid(communityId)});

    insert into community_team (community_id, user_id, accepted, role)
    values (${sqlUuid(communityId)}, ${sqlUuid(role.userId)}, true, ${sqlString(role.roleName === "groups-manager" ? "groups-manager" : "admin")});
  `);

  return {
    communityId,
    displayName,
    groupCategoryId,
    cleanup: () => cleanupTemporaryCommunity(communityId),
  };
}

/** Creates group, group_team, group_member, and optional badge_artwork rows. */
function setupTemporaryGroup(role, { memberUserId, withArtwork = false } = {}) {
  const groupId = randomUUID();
  const groupName = uniqueName("permission group");
  const slug = `permission-group-${shortId(groupId)}`;
  const roleInsert = role.groupRole
    ? `insert into group_team (group_id, user_id, accepted, role, "order")
       values (${sqlUuid(groupId)}, ${sqlUuid(role.userId)}, true, ${sqlString(role.groupRole)}, 1);`
    : "";
  const memberInsert = memberUserId
    ? `insert into group_member (group_id, user_id) values (${sqlUuid(groupId)}, ${sqlUuid(memberUserId)});`
    : "";
  const artworkInsert = withArtwork
    ? `insert into badge_artwork (badge_artwork_id, file_name, group_id)
       values (${sqlUuid(randomUUID())}, ${sqlString(BADGE_ARTWORK_FILE_NAME)}, ${sqlUuid(groupId)});`
    : "";

  queryE2eDatabase(`
    insert into "group" (
      group_id,
      community_id,
      group_category_id,
      name,
      slug,
      description,
      active
    ) values (
      ${sqlUuid(groupId)},
      ${sqlUuid(PRIMARY_COMMUNITY_ID)},
      ${sqlUuid(GROUP_CATEGORY_ID)},
      ${sqlString(groupName)},
      ${sqlString(slug)},
      'Temporary group owned by dashboard permission coverage.',
      true
    );

    ${roleInsert}
    ${memberInsert}
    ${artworkInsert}
  `);

  return {
    groupId,
    groupName,
    cleanup: () => cleanupTemporaryGroup(groupId),
  };
}

/** Creates a temporary user row for permission test ownership. */
function setupTemporaryUser(label) {
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
      ${sqlString(`permission-${suffix}`)}
    );
  `);

  return {
    userId,
    cleanup: () => cleanupTemporaryUser(userId),
  };
}

/** Returns a compact ID suffix from a UUID string. */
function shortId(value) {
  return value.replace(/-/gu, "").slice(0, 12);
}

/** Escapes a value as a SQL string literal. */
function sqlString(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

/** Escapes a value as a SQL uuid literal. */
function sqlUuid(value) {
  return `${sqlString(value)}::uuid`;
}

/** Returns comma-separated SQL uuid literals. */
function sqlUuidList(values) {
  return values.map((value) => sqlUuid(value)).join(", ");
}
