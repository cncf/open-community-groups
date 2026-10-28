import { expect, test } from "../../fixtures.js";
import {
  queryCount,
  queryE2eDatabase,
  queryE2eDatabaseRows,
  queryScalar,
  sqlString,
  sqlUuid,
} from "../../database.js";
import { cleanupCohostEvents, readCohostStatus, setupCohostEvent } from "../../data-graphs/cohosts.js";
import { cleanupTemporaryCommunity, setupTemporaryCommunity } from "../../data-graphs/communities.js";
import { cleanupEventsByIds, setupCheckInEventGraph } from "../../data-graphs/events.js";
import {
  BADGE_ARTWORK_FILE_NAME,
  cleanupGroupCustomNotificationsBySubject,
  cleanupTemporaryGroup,
  setupTemporaryGroup,
} from "../../data-graphs/groups.js";
import { cleanupInboxConversations, setupInboxConversation } from "../../data-graphs/inbox.js";
import { cleanupOwnedPaymentPurchase, setupExternalRefundRequestGraph } from "../../data-graphs/payments.js";
import { TEST_EVENT_SURVEYS } from "../../data-graphs/surveys.js";
import { cleanupTemporaryUser, setupTemporaryUser } from "../../data-graphs/users.js";
import {
  TEST_COMMUNITY_BANNER_MOBILE_URL,
  TEST_COMMUNITY_BANNER_URL,
  TEST_COMMUNITY_DESCRIPTION,
  TEST_COMMUNITY_IDS,
  TEST_COMMUNITY_LOGO_URL,
  TEST_COMMUNITY_TITLE,
  TEST_EVENT_CATEGORY_IDS,
  TEST_EVENT_IDS,
  TEST_GROUP_CATEGORY_IDS,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_INBOX_CONVERSATION,
  TEST_PAYMENT_EVENT_IDS,
  TEST_USER_IDS,
} from "../../seed.js";
import {
  buildE2eUrl,
  futureDate,
  selectCommunityContext,
  selectGroupContext,
  uniqueName,
} from "../../utils.js";

const INVITATION_REDIRECT_STATUS = 303;

const PRIMARY_COMMUNITY_ID = TEST_COMMUNITY_IDS.community1;

const PRIMARY_GROUP_ID = TEST_GROUP_IDS.community1.alpha;

// Seeded primary community region and primary group sponsor (10_catalog.sql, 50_membership_cfs.sql).
const PRIMARY_REGION_ID = "22222222-2222-2222-2222-222222222301";

const PRIMARY_SPONSOR_ID = "66666666-6666-6666-6666-666666666601";

const COMMUNITY_ROLES = {
  adminCommunityPage: {
    buckets: {
      groups: true,
      settings: true,
      taxonomy: true,
      team: true,
    },
    communityRole: "admin",
    roleName: "community admin",
    userId: TEST_USER_IDS.admin1,
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
    communityRole: "groups-manager",
    roleName: "groups-manager",
    userId: TEST_USER_IDS.groupsManager1,
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
      inbox: true,
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
      inbox: false,
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
  communityViewerPage: {
    buckets: {
      badges: false,
      checkIns: false,
      events: false,
      inbox: false,
      notifications: false,
      refunds: false,
      settings: false,
      sponsors: false,
      team: false,
    },
    roleName: "community viewer",
  },
  eventsManagerGroupPage: {
    buckets: {
      badges: true,
      checkIns: true,
      events: true,
      inbox: true,
      notifications: false,
      refunds: true,
      settings: false,
      sponsors: false,
      team: false,
    },
    groupRole: "events-manager",
    roleName: "events-manager",
    userId: TEST_USER_IDS.eventsManager1,
  },
  groupViewerPage: {
    buckets: {
      badges: false,
      checkIns: false,
      events: false,
      inbox: false,
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
      inbox: true,
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
      inbox: false,
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
      inbox: true,
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
    key: "inbox",
    name: "inbox",
    successStatus: 200,
    createOperation: createGroupInboxOperation,
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
  // Co-host responses are guarded by group settings access.
  {
    key: "settings",
    name: "co-host responses",
    successStatus: 204,
    createOperation: createGroupCohostResponseOperation,
  },
  // Co-host group options are guarded by group events access.
  {
    key: "events",
    name: "co-host group options",
    successStatus: 200,
    createOperation: createGroupCohostOptionsOperation,
  },
];

// Community Read bucket GET routes, checked against the selected primary community.
const COMMUNITY_READ_ROUTES = [
  { path: "/dashboard/community/analytics" },
  { path: "/dashboard/community/contact" },
  { path: "/dashboard/community/event-categories" },
  { path: "/dashboard/community/event-categories/add" },
  { path: `/dashboard/community/event-categories/${TEST_EVENT_CATEGORY_IDS.general}/update` },
  { path: "/dashboard/community/group-categories" },
  { path: "/dashboard/community/group-categories/add" },
  { path: `/dashboard/community/group-categories/${TEST_GROUP_CATEGORY_IDS.one}/update` },
  { path: "/dashboard/community/groups" },
  { path: "/dashboard/community/groups/add" },
  { path: `/dashboard/community/groups/${PRIMARY_GROUP_ID}/update` },
  { path: "/dashboard/community/logs" },
  { path: "/dashboard/community/regions" },
  { path: "/dashboard/community/regions/add" },
  { path: `/dashboard/community/regions/${PRIMARY_REGION_ID}/update` },
  { path: "/dashboard/community/settings/update" },
  { path: "/dashboard/community/team" },
];

// Group GET routes guarded by Read or by the bucket named in `bucket`, checked against the
// selected primary group. The CSV exports are covered by their own specs, and `events/tax-rates`
// is left out because it calls Stripe, which the e2e stack does not configure.
const GROUP_READ_ROUTES = (() => {
  const eventId = TEST_EVENT_IDS.alpha.one;
  const { attendeeIds, event, surveys } = TEST_EVENT_SURVEYS;
  const surveyPath = `/dashboard/group/events/${event.id}/surveys/${surveys.openIdentified.id}`;

  return [
    { path: "/dashboard/group" },
    { path: "/dashboard/group/analytics" },
    { path: "/dashboard/group/cohosts" },
    { path: "/dashboard/group/events" },
    { path: "/dashboard/group/events/add" },
    { path: "/dashboard/group/events/search" },
    { path: `/dashboard/group/events/${eventId}/analytics` },
    { path: `/dashboard/group/events/${eventId}/attendees` },
    { path: `/dashboard/group/events/${eventId}/details` },
    { path: `/dashboard/group/events/${eventId}/invitation-requests` },
    { path: `/dashboard/group/events/${eventId}/submissions` },
    { path: `/dashboard/group/events/${eventId}/update` },
    { path: `/dashboard/group/events/${eventId}/waitlist` },
    { path: `/dashboard/group/events/${event.id}/surveys` },
    { path: `/dashboard/group/events/${event.id}/surveys/add` },
    { path: `/dashboard/group/events/${event.id}/surveys/${surveys.draft.id}/update` },
    { path: `${surveyPath}/responses` },
    { path: `${surveyPath}/responses/${attendeeIds.checkedIn1}` },
    { path: `${surveyPath}/results` },
    { path: `${surveyPath}/results/questions/${surveys.openIdentified.questionIds.improve}/answers` },
    { path: "/dashboard/group/logs" },
    { path: "/dashboard/group/members" },
    { path: "/dashboard/group/refunds" },
    { path: "/dashboard/group/settings/update" },
    { path: "/dashboard/group/sponsors" },
    { path: "/dashboard/group/sponsors/add" },
    { path: `/dashboard/group/sponsors/${PRIMARY_SPONSOR_ID}/update` },
    { path: "/dashboard/group/team" },
    { bucket: "badges", path: "/dashboard/group/artwork" },
    { bucket: "badges", path: "/dashboard/group/awards" },
    { bucket: "badges", path: "/dashboard/group/badges" },
    { bucket: "badges", path: "/dashboard/group/badges/options" },
    { bucket: "badges", path: `/dashboard/group/events/${eventId}/badges/recipients?scope=all-attendees` },
    { bucket: "checkIns", path: "/dashboard/group/check-in" },
    { bucket: "inbox", path: "/dashboard/group/inbox" },
    { bucket: "inbox", path: `/dashboard/group/inbox/${TEST_INBOX_CONVERSATION.id}` },
  ];
})();

/** Builds a community group POST operation that creates or preserves a group and cleans up. */
function createCommunityGroupOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const community = allowed
    ? setupTemporaryCommunity({ label: "community group", teamRole: role.communityRole, userId: role.userId })
    : null;
  const name = uniqueName("permission community group");
  let groupId;

  return {
    communityId: community?.communityId ?? (role.redirectsWithoutContext ? null : PRIMARY_COMMUNITY_ID),
    form: communityGroupForm(name, community?.groupCategoryId ?? TEST_GROUP_CATEGORY_IDS.one),
    method: "POST",
    path: "/dashboard/community/groups/add",
    assertEffect: async (before, { page }) => {
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
      if (community) {
        cleanupTemporaryCommunity(community.communityId);
      }
    },
    readEffect: () => countGroupsByName(name),
  };
}

/** Builds a community settings PUT operation that updates new group details and cleans up. */
function createCommunitySettingsOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const community = allowed
    ? setupTemporaryCommunity({
        label: "community settings",
        teamRole: role.communityRole,
        userId: role.userId,
      })
    : null;
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
    cleanup: () => {
      if (community) {
        cleanupTemporaryCommunity(community.communityId);
      }
    },
    readEffect: () => communityNewGroupDetails(communityId),
  };
}

/** Builds a community taxonomy POST operation that creates a category and cleans up. */
function createCommunityTaxonomyOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const community = allowed
    ? setupTemporaryCommunity({
        label: "community taxonomy",
        teamRole: role.communityRole,
        userId: role.userId,
      })
    : null;
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
      if (community) {
        cleanupTemporaryCommunity(community.communityId);
      }
    },
    readEffect: () => countEventCategoriesByName(name),
  };
}

/** Builds a community team POST operation that invites a user and cleans up. */
function createCommunityTeamOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const community = allowed
    ? setupTemporaryCommunity({ label: "community team", teamRole: role.communityRole, userId: role.userId })
    : null;
  const communityId = community?.communityId ?? PRIMARY_COMMUNITY_ID;
  const targetUser = setupTemporaryUser({ label: "community-team-target" });

  return {
    communityId: role.redirectsWithoutContext ? null : communityId,
    form: { role: "viewer", user_id: targetUser.userId },
    method: "POST",
    path: "/dashboard/community/team/add",
    assertEffect: (before) => {
      const after = countCommunityTeamMember(communityId, targetUser.userId);
      expect(after).toBe(allowed ? 1 : before);
    },
    cleanup: () => {
      queryE2eDatabase(`
        delete from community_team
        where community_id = ${sqlUuid(communityId)}
        and user_id = ${sqlUuid(targetUser.userId)};
      `);
      if (community) {
        cleanupTemporaryCommunity(community.communityId);
      }
      cleanupTemporaryUser(targetUser.userId);
    },
    readEffect: () => countCommunityTeamMember(communityId, targetUser.userId),
  };
}

/** Builds a group badges POST operation that creates a badge and cleans up. */
function createGroupBadgesOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const group = allowed
    ? setupTemporaryGroup({ teamRole: role.groupRole, teamUserId: role.userId, withArtwork: true })
    : null;
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
      if (group) {
        cleanupTemporaryGroup(group.groupId);
      }
    },
    readEffect: () => countBadgesByName(badgeName),
  };
}

/** Builds a group events POST operation that creates an event and cleans up. */
function createGroupEventsOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const group = allowed ? setupTemporaryGroup({ teamRole: role.groupRole, teamUserId: role.userId }) : null;
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
      if (group) {
        cleanupTemporaryGroup(group.groupId);
      }
    },
    readEffect: () => countEventsByName(eventName),
  };
}

/** Builds a co-host group options GET operation that lists another community's groups. */
function createGroupCohostOptionsOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const group = allowed ? setupTemporaryGroup({ teamRole: role.groupRole, teamUserId: role.userId }) : null;
  const communityId = TEST_COMMUNITY_IDS.community2;
  let optionIds = [];

  return {
    groupId: group?.groupId ?? (role.redirectsWithoutContext ? null : PRIMARY_GROUP_ID),
    method: "GET",
    path: `/dashboard/group/events/cohosts/groups?community_id=${communityId}`,
    assertEffect: () => {},
    assertResponse: async (response) => {
      if (!allowed) {
        return;
      }

      optionIds = (await response.json()).map((option) => option.group_id);
      expect(optionIds).toContain(TEST_GROUP_IDS.community2.delta);
    },
    cleanup: () => {
      if (group) {
        cleanupTemporaryGroup(group.groupId);
      }
    },
    readEffect: () => null,
  };
}

/** Builds a co-host response PUT operation that rejects a pending invitation and cleans up. */
function createGroupCohostResponseOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const group = allowed ? setupTemporaryGroup({ teamRole: role.groupRole, teamUserId: role.userId }) : null;
  const cohostGroupId = group?.groupId ?? PRIMARY_GROUP_ID;
  const scenario = setupCohostEvent({
    cohosts: [{ groupId: cohostGroupId }],
    ownerGroupId: allowed ? PRIMARY_GROUP_ID : TEST_GROUP_IDS.community1.gamma,
  });

  return {
    groupId: role.redirectsWithoutContext ? null : cohostGroupId,
    method: "PUT",
    path: `/dashboard/group/cohosts/${scenario.invitationIds[cohostGroupId]}/reject`,
    assertEffect: (before) => {
      const after = readCohostStatus(scenario.eventId, cohostGroupId);
      expect(after).toBe(allowed ? "rejected" : before);
    },
    cleanup: () => {
      cleanupCohostEvents([scenario.eventId]);
      if (group) {
        cleanupTemporaryGroup(group.groupId);
      }
    },
    readEffect: () => readCohostStatus(scenario.eventId, cohostGroupId),
  };
}

/** Builds a group inbox PUT operation that closes a conversation and cleans up. */
function createGroupInboxOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const group = allowed ? setupTemporaryGroup({ teamRole: role.groupRole, teamUserId: role.userId }) : null;
  const groupId = group?.groupId ?? PRIMARY_GROUP_ID;
  // Denied roles target a primary group conversation, which must stay open.
  const conversation = setupInboxConversation({
    groupId,
    messages: [{ body: uniqueName("permission inbox message") }],
  });

  return {
    groupId: role.redirectsWithoutContext ? null : groupId,
    method: "PUT",
    path: `/dashboard/group/inbox/${conversation.id}/close`,
    assertEffect: (before) => {
      const after = inboxConversationStatus(conversation.id);
      expect(after).toBe(allowed ? "closed" : before);
    },
    cleanup: () => {
      cleanupInboxConversations([conversation.id]);
      if (group) {
        cleanupTemporaryGroup(group.groupId);
      }
    },
    readEffect: () => inboxConversationStatus(conversation.id),
  };
}

/** Builds a group notifications POST operation that sends notices and cleans up. */
function createGroupNotificationsOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const notificationTarget = allowed ? setupTemporaryUser({ label: "group-notification-target" }) : null;
  const group = allowed
    ? setupTemporaryGroup({
        memberUserId: notificationTarget.userId,
        teamRole: role.groupRole,
        teamUserId: role.userId,
      })
    : null;
  const subject = uniqueName("permission notification");

  return {
    form: {
      body: "This notification verifies the group members permission bucket.",
      subject,
    },
    groupId: group?.groupId ?? (role.redirectsWithoutContext ? null : PRIMARY_GROUP_ID),
    method: "POST",
    path: "/dashboard/group/notifications",
    assertEffect: (before, { notifications }) => {
      const after = countGroupCustomNotificationsBySubject(subject);
      if (!allowed) {
        expect(after).toBe(before);
        return;
      }

      expect(after).toBe(1);
      const sent = notifications.list().filter(({ templateData }) => templateData?.subject === subject);
      expect(sent.length).toBeGreaterThan(0);
    },
    cleanup: () => {
      cleanupGroupCustomNotificationsBySubject(subject);
      if (group) {
        cleanupTemporaryGroup(group.groupId);
      }
      if (notificationTarget) {
        cleanupTemporaryUser(notificationTarget.userId);
      }
    },
    readEffect: () => countGroupCustomNotificationsBySubject(subject),
  };
}

/** Builds a group settings PUT operation that updates the description and cleans up. */
function createGroupSettingsOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const group = allowed ? setupTemporaryGroup({ teamRole: role.groupRole, teamUserId: role.userId }) : null;
  const groupId = group?.groupId ?? PRIMARY_GROUP_ID;
  const description = uniqueName("permission group settings");

  return {
    form: groupForm({
      categoryId: TEST_GROUP_CATEGORY_IDS.one,
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
    cleanup: () => {
      if (group) {
        cleanupTemporaryGroup(group.groupId);
      }
    },
    readEffect: () => groupDescription(groupId),
  };
}

/** Builds a group sponsors POST operation that creates a sponsor and cleans up. */
function createGroupSponsorsOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const group = allowed ? setupTemporaryGroup({ teamRole: role.groupRole, teamUserId: role.userId }) : null;
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
      if (group) {
        cleanupTemporaryGroup(group.groupId);
      }
    },
    readEffect: () => countSponsorsByName(sponsorName),
  };
}

/** Builds a group team POST operation that invites a user and cleans up. */
function createGroupTeamOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const group = allowed ? setupTemporaryGroup({ teamRole: role.groupRole, teamUserId: role.userId }) : null;
  const groupId = group?.groupId ?? PRIMARY_GROUP_ID;
  const targetUser = setupTemporaryUser({ label: "group-team-target" });

  return {
    form: { role: "viewer", user_id: targetUser.userId },
    groupId: role.redirectsWithoutContext ? null : groupId,
    method: "POST",
    path: "/dashboard/group/team/add",
    assertEffect: (before) => {
      const after = countGroupTeamMember(groupId, targetUser.userId);
      expect(after).toBe(allowed ? 1 : before);
    },
    cleanup: () => {
      queryE2eDatabase(`
        delete from group_team
        where group_id = ${sqlUuid(groupId)}
        and user_id = ${sqlUuid(targetUser.userId)};
      `);
      if (group) {
        cleanupTemporaryGroup(group.groupId);
      }
      cleanupTemporaryUser(targetUser.userId);
    },
    readEffect: () => countGroupTeamMember(groupId, targetUser.userId),
  };
}

/** Builds a group check-in POST operation that marks attendance and cleans up. */
function createGroupCheckInsOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const graph = setupCheckInEventGraph({ groupId: PRIMARY_GROUP_ID });

  return {
    groupId: role.redirectsWithoutContext ? null : PRIMARY_GROUP_ID,
    method: "POST",
    path: `/dashboard/group/events/${graph.eventId}/attendees/${graph.userId}/check-in`,
    assertEffect: (before) => {
      const after = attendeeCheckedIn(graph.eventId, graph.userId);
      expect(after).toBe(allowed ? "true" : before);
    },
    cleanup: () => {
      cleanupEventsByIds([graph.eventId]);
      cleanupTemporaryUser(graph.userId);
    },
    readEffect: () => attendeeCheckedIn(graph.eventId, graph.userId),
  };
}

/** Builds a group refunds PUT operation that approves a refund and cleans up. */
function createGroupRefundsOperation(role, expectedStatus) {
  const allowed = isAllowed(expectedStatus);
  const refundUser = setupTemporaryUser({ label: "refund-request-owner" });
  const graph = setupExternalRefundRequestGraph({
    eventId: TEST_PAYMENT_EVENT_IDS.refunds,
    requestedReason: uniqueName("permission refund"),
    userId: refundUser.userId,
  });

  return {
    form: { review_note: "Approved by permission matrix" },
    groupId: role.redirectsWithoutContext ? null : PRIMARY_GROUP_ID,
    method: "PUT",
    path: `/dashboard/group/refunds/${graph.purchaseId}/approve`,
    assertEffect: (before) => {
      const after = refundRequestStatus(graph.purchaseId);
      expect(after).toBe(allowed ? "approved" : before);
    },
    cleanup: () => {
      cleanupOwnedPaymentPurchase(graph);
      cleanupTemporaryUser(refundUser.userId);
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

  test("community select forbids a pending community invitation", async ({ pending1Page }) => {
    // The first pending user only holds an unaccepted primary community team invitation.
    const response = await pending1Page.request.put(
      buildE2eUrl(`/dashboard/community/${PRIMARY_COMMUNITY_ID}/select`),
    );

    // Verify a pending community_team row grants no community read access.
    expect(response.status()).toBe(403);
  });

  test("group community select forbids a user with only pending group invitations", async ({
    pending2Page,
  }) => {
    // The second pending user only holds an unaccepted primary group team invitation.
    const response = await pending2Page.request.put(
      buildE2eUrl(`/dashboard/group/community/${PRIMARY_COMMUNITY_ID}/select`),
    );

    // Verify a pending group_team row leaves no selectable group in the community.
    expect(response.status()).toBe(403);
  });

  for (const [fixture, role] of Object.entries(COMMUNITY_ROLES)) {
    test(`${role.roleName} gets its bucket status from every community read route`, async ({ pageAs }) => {
      const page = await pageAs(fixture);
      if (!role.redirectsWithoutContext) {
        await selectCommunityContext(page, PRIMARY_COMMUNITY_ID);
      }

      // Request every route without following redirects and report all mismatches together.
      for (const route of COMMUNITY_READ_ROUTES) {
        const response = await page.request.get(buildE2eUrl(route.path), { maxRedirects: 0 });
        expect.soft(response.status(), `GET ${route.path}`).toBe(expectedReadStatus(role, route));
      }
    });
  }

  for (const [fixture, role] of Object.entries(GROUP_ROLES)) {
    test(`${role.roleName} gets its bucket status from every group read route`, async ({ pageAs }) => {
      const page = await pageAs(fixture);
      if (!role.redirectsWithoutContext) {
        await selectGroupContext(page, PRIMARY_COMMUNITY_ID, PRIMARY_GROUP_ID);
      }

      // Request every route without following redirects and report all mismatches together.
      for (const route of GROUP_READ_ROUTES) {
        const response = await page.request.get(buildE2eUrl(route.path), { maxRedirects: 0 });
        expect.soft(response.status(), `GET ${route.path}`).toBe(expectedReadStatus(role, route));
      }
    });
  }

  for (const [fixture, role] of Object.entries(COMMUNITY_ROLES)) {
    for (const bucket of COMMUNITY_BUCKETS) {
      const status = expectedStatus(role, bucket);

      test(`${role.roleName} ${statusLabel(status)} community ${bucket.name} writes`, async ({
        notifications,
        pageAs,
      }) => {
        await runCommunityCase(
          { bucket, expectedStatus: status, role },
          await pageAs(fixture),
          notifications,
        );
      });
    }
  }

  for (const [fixture, role] of Object.entries(GROUP_ROLES)) {
    for (const bucket of GROUP_BUCKETS) {
      const status = expectedStatus(role, bucket);

      test(`${role.roleName} ${statusLabel(status)} group ${bucket.name} writes`, async ({
        notifications,
        pageAs,
      }) => {
        await runGroupCase({ bucket, expectedStatus: status, role }, await pageAs(fixture), notifications);
      });
    }
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
    banner_mobile_url: community ? TEST_COMMUNITY_BANNER_MOBILE_URL : TEST_COMMUNITY_BANNER_MOBILE_URL,
    banner_url: community ? TEST_COMMUNITY_BANNER_URL : TEST_COMMUNITY_BANNER_URL,
    description: community?.displayName ?? TEST_COMMUNITY_DESCRIPTION,
    display_name: community?.displayName ?? TEST_COMMUNITY_TITLE,
    group_team_management_restricted: "false",
    logo_url: TEST_COMMUNITY_LOGO_URL,
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

/** Builds the event creation form payload. */
function eventForm(name) {
  return {
    category_id: TEST_EVENT_CATEGORY_IDS.general,
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

/** Returns the expected status of a read route: Read, or the route bucket when it names one. */
function expectedReadStatus(role, route) {
  if (role.redirectsWithoutContext) {
    return INVITATION_REDIRECT_STATUS;
  }

  return !route.bucket || role.buckets[route.bucket] ? 200 : 403;
}

/** Returns the expected permission status for a role and bucket. */
function expectedStatus(role, bucket) {
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

/** Returns the inbox_conversation_status_id value from inbox_conversation. */
function inboxConversationStatus(conversationId) {
  return queryScalar(`
    select inbox_conversation_status_id
    from inbox_conversation
    where inbox_conversation_id = ${sqlUuid(conversationId)};
  `);
}

/** Returns whether a response status represents an allowed write. */
function isAllowed(status) {
  return status === 200 || status === 201 || status === 204;
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
const runCommunityCase = async (matrixCase, page, notifications) => {
  const operation = matrixCase.bucket.createOperation(matrixCase.role, matrixCase.expectedStatus);
  let before;

  try {
    if (operation.communityId) {
      await selectCommunityContext(page, operation.communityId);
    }

    before = operation.readEffect();

    // Send the representative request through the selected community context.
    const response = await sendDashboardRequest(page, operation, matrixCase.expectedStatus);

    expect(response.status(), await response.text()).toBe(matrixCase.expectedStatus);
    await operation.assertEffect(before, { notifications, page });
  } finally {
    operation.cleanup?.();
  }
};

/** Runs a group permission request and cleans up its representative effect. */
const runGroupCase = async (matrixCase, page, notifications) => {
  const operation = matrixCase.bucket.createOperation(matrixCase.role, matrixCase.expectedStatus);
  let before;

  try {
    if (operation.groupId) {
      await selectGroupContext(page, PRIMARY_COMMUNITY_ID, operation.groupId);
    }

    before = operation.readEffect();

    // Send the representative request through the selected group context.
    const response = await sendDashboardRequest(page, operation, matrixCase.expectedStatus);

    expect(response.status(), await response.text()).toBe(matrixCase.expectedStatus);
    await operation.assertResponse?.(response);
    await operation.assertEffect(before, { notifications, page });
  } finally {
    operation.cleanup?.();
  }
};

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
