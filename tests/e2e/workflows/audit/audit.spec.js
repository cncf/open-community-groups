import { expect, test } from "../../fixtures.js";
import {
  queryE2eDatabase,
  queryE2eDatabaseRows,
  queryScalar,
  restoreRow,
  snapshotRow,
  sqlString,
  withRowRestore,
} from "../../database.js";
import { cleanupRegionsByName } from "../../data-graphs/communities.js";
import { cleanupGroupSponsor, setupGroupSponsor } from "../../data-graphs/groups.js";
import { cleanupGroupTeamInvitation } from "../../data-graphs/invitations.js";
import { cleanupGroupMute } from "../../data-graphs/notification-preferences.js";
import { TEST_COMMUNITY_IDS, TEST_GROUP_IDS, TEST_USER_IDS } from "../../seed.js";
import { buildE2eUrl, navigateToPath, uniqueName, waitForActionResponse } from "../../utils.js";
import { fillMarkdownEditor } from "../../dashboard/form-helpers.js";
import { respondToCohostInvitation } from "../../dashboard/group/cohosts/helpers.js";
import { inviteTeamMember } from "../../dashboard/team-helpers.js";

const COMMUNITY_LOGS_PATH = "/dashboard/community?tab=logs";

const GROUP_LOGS_PATH = "/dashboard/group?tab=logs";

const GROUPS_MANAGER_TEAM_ROW = {
  key: { community_id: TEST_COMMUNITY_IDS.community1, user_id: TEST_USER_IDS.groupsManager1 },
  table: "community_team",
};

// Group-scoped co-host audit filter labels.
const COHOST_AUDIT_ACTION_LABELS = [
  "Event co-host approved",
  "Event co-host canceled",
  "Event co-host closed",
  "Event co-host invited",
  "Event co-host rejected",
  "Event co-host removed",
];

const USER_ACCOUNT_PATH = "/dashboard/user?tab=account";

const USER_LOGS_PATH = "/dashboard/user?tab=logs";

test.describe("dashboard audit workflow", () => {
  test("community settings mutation appears in community logs", async ({ adminCommunityPage }) => {
    // Snapshot the seeded community row, its description and the audit baseline.
    const originalDescription = await readMarkdownValue(adminCommunityPage, {
      editorId: "description",
      path: "/dashboard/community?tab=settings",
    });
    const updatedDescription = `${originalDescription}\n\nE2E audit community update.`;
    const communitySnapshot = snapshotRow({
      key: { community_id: TEST_COMMUNITY_IDS.community1 },
      table: "community",
    });
    const auditSnapshot = snapshotAuditLogs();
    let auditLogId;

    try {
      // Save the updated community description and locate its audit entry.
      await saveCommunityDescription(adminCommunityPage, updatedDescription);
      auditLogId = latestAuditLogId({
        action: "community_updated",
        actorUserId: TEST_USER_IDS.admin1,
        createdAfter: auditSnapshot.createdAfter,
        resourceId: TEST_COMMUNITY_IDS.community1,
      });

      // Verify the community log row exposes the saved audit details.
      await expectAuditRow(adminCommunityPage, {
        action: "community_updated",
        actionLabel: "Community updated",
        actorUsername: "e2e-admin-1",
        auditLogId,
        path: `${COMMUNITY_LOGS_PATH}&action=community_updated&actor=e2e-admin-1`,
        resourceName: "Platform Engineering Community",
        resourceType: "Community",
      });
    } finally {
      // Restore the seeded community row; a form save also writes defaults it did not edit.
      restoreRow(communitySnapshot);
    }
  });

  test("group settings mutation appears in group logs", async ({ organizerGroupPage }) => {
    // Snapshot the seeded group row, its description and the audit baseline.
    const originalDescription = await readMarkdownValue(organizerGroupPage, {
      editorId: "description",
      path: "/dashboard/group?tab=settings",
    });
    const updatedDescription = `${originalDescription}\n\nE2E audit group update.`;
    const groupSnapshot = snapshotRow({ key: { group_id: TEST_GROUP_IDS.community1.alpha }, table: "group" });
    const auditSnapshot = snapshotAuditLogs();
    let auditLogId;

    try {
      // Save the updated group description and locate its audit entry.
      await saveGroupDescription(organizerGroupPage, updatedDescription);
      auditLogId = latestAuditLogId({
        action: "group_updated",
        actorUserId: TEST_USER_IDS.organizer1,
        createdAfter: auditSnapshot.createdAfter,
        resourceId: TEST_GROUP_IDS.community1.alpha,
      });

      // Verify the group log row exposes the saved audit details.
      await expectAuditRow(organizerGroupPage, {
        action: "group_updated",
        actionLabel: "Group updated",
        actorUsername: "e2e-organizer-1",
        auditLogId,
        path: `${GROUP_LOGS_PATH}&action=group_updated&actor=e2e-organizer-1`,
        resourceName: "Platform Ops Meetup",
        resourceType: "Group",
      });
    } finally {
      // Restore the seeded group row; a form save also writes defaults it did not edit.
      restoreRow(groupSnapshot);
    }
  });

  test("co-host approval appears in owner and co-host group logs", async ({
    organizerGroupPage,
    organizerGroupWithoutPaymentsPage,
    owned,
  }) => {
    const cohostGroupId = TEST_GROUP_IDS.community2.delta;
    const scenario = owned.cohostEvent({ cohosts: [{ groupId: cohostGroupId }] });
    const auditSnapshot = snapshotAuditLogs();

    // Approve the invitation from the co-host group dashboard.
    await respondToCohostInvitation(organizerGroupWithoutPaymentsPage, scenario.name, "approve");

    // Verify each group sees the approval in its own logs.
    for (const [page, groupId] of [
      [organizerGroupPage, TEST_GROUP_IDS.community1.alpha],
      [organizerGroupWithoutPaymentsPage, cohostGroupId],
    ]) {
      const auditLogId = latestAuditLogId({
        action: "event_cohost_approved",
        actorUserId: TEST_USER_IDS.organizer2,
        createdAfter: auditSnapshot.createdAfter,
        groupId,
        resourceId: scenario.eventId,
      });
      await expectAuditRow(page, {
        action: "event_cohost_approved",
        actionLabel: "Event co-host approved",
        actorUsername: "e2e-organizer-2",
        auditLogId,
        path: `${GROUP_LOGS_PATH}&action=event_cohost_approved`,
        resourceName: scenario.name,
        resourceType: "Event",
      });
    }

    // Verify every co-host transition can be used as a group log filter.
    await organizerGroupPage.getByRole("button", { name: "Filters" }).click();
    const actionFilter = organizerGroupPage.locator("#audit-log-filters-modal #audit-action");
    await expect(actionFilter).toHaveValue("event_cohost_approved");
    for (const label of COHOST_AUDIT_ACTION_LABELS) {
      await expect(actionFilter.getByRole("option", { name: label, exact: true })).toHaveCount(1);
    }
  });

  test("user profile mutation appears in user logs", async ({ member1Page }) => {
    // Snapshot the seeded user row, its name and the audit baseline.
    const originalName = await readUserName(member1Page);
    const updatedName = `${originalName} Audit`;
    const userSnapshot = snapshotRow({ key: { user_id: TEST_USER_IDS.member1 }, table: "user" });
    const auditSnapshot = snapshotAuditLogs();
    let auditLogId;

    try {
      // Save the updated user name and locate its audit entry.
      await saveUserName(member1Page, updatedName);
      auditLogId = latestAuditLogId({
        action: "user_details_updated",
        actorUserId: TEST_USER_IDS.member1,
        createdAfter: auditSnapshot.createdAfter,
        resourceId: TEST_USER_IDS.member1,
      });

      // Verify the user log row exposes the saved audit details.
      await expectAuditRow(member1Page, {
        action: "user_details_updated",
        actionLabel: "User details updated",
        auditLogId,
        path: `${USER_LOGS_PATH}&action=user_details_updated`,
        resourceName: updatedName,
        resourceType: "User",
      });
    } finally {
      // Restore the seeded user row.
      restoreRow(userSnapshot);
    }
  });

  test("region addition and team role change appear in community logs", async ({
    adminCommunityPage,
    owned,
  }) => {
    const regionName = uniqueName("Audit Region");
    const auditSnapshot = snapshotAuditLogs();
    owned.defer(() => cleanupRegionsByName(regionName));

    // Add a region to the selected community.
    const addRegionResponse = await adminCommunityPage.request.post(
      buildE2eUrl("/dashboard/community/regions/add"),
      { form: { name: regionName } },
    );
    expect(addRegionResponse.status(), "add region status").toBe(201);
    const regionId = queryScalar(`select region_id from region where name = ${sqlString(regionName)}`);

    // Verify the region log row while the region still exists.
    await expectAuditRow(adminCommunityPage, {
      action: "region_added",
      actionLabel: "Region added",
      actorUsername: "e2e-admin-1",
      auditLogId: latestAuditLogId({
        action: "region_added",
        actorUserId: TEST_USER_IDS.admin1,
        createdAfter: auditSnapshot.createdAfter,
        resourceId: regionId,
      }),
      path: `${COMMUNITY_LOGS_PATH}&action=region_added&actor=e2e-admin-1`,
      resourceName: regionName,
      resourceType: "Region",
    });

    // Change the seeded groups manager role, restoring the team row afterwards.
    await withRowRestore(GROUPS_MANAGER_TEAM_ROW, async () => {
      const updateRoleResponse = await adminCommunityPage.request.put(
        buildE2eUrl(`/dashboard/community/team/${TEST_USER_IDS.groupsManager1}/role`),
        { form: { role: "viewer" } },
      );
      expect(updateRoleResponse.status(), "update community team role status").toBe(204);

      // Verify the role change log row.
      await expectAuditRow(adminCommunityPage, {
        action: "community_team_member_role_updated",
        actionLabel: "Community team member role updated",
        actorUsername: "e2e-admin-1",
        auditLogId: latestAuditLogId({
          action: "community_team_member_role_updated",
          actorUserId: TEST_USER_IDS.admin1,
          createdAfter: auditSnapshot.createdAfter,
          resourceId: TEST_USER_IDS.groupsManager1,
        }),
        path: `${COMMUNITY_LOGS_PATH}&action=community_team_member_role_updated&actor=e2e-admin-1`,
        resourceName: "E2E Groups Manager One",
        resourceType: "User",
      });
    });
  });

  test("team member addition and sponsor deletion appear in group logs", async ({
    organizerGroupPage,
    owned,
  }) => {
    const groupId = TEST_GROUP_IDS.community1.alpha;
    const sponsor = owned.track(setupGroupSponsor({ groupId }), cleanupGroupSponsor);
    owned.track({ groupId, userId: TEST_USER_IDS.pending1 }, cleanupGroupTeamInvitation);
    const auditSnapshot = snapshotAuditLogs();

    // Invite a pending user to the group team.
    await inviteTeamMember(organizerGroupPage, {
      fullName: "E2E Pending One",
      role: "viewer",
      scope: "group",
      username: "e2e-pending-1",
    });

    // Verify the team member log row.
    await expectAuditRow(organizerGroupPage, {
      action: "group_team_member_added",
      actionLabel: "Group team member added",
      actorUsername: "e2e-organizer-1",
      auditLogId: latestAuditLogId({
        action: "group_team_member_added",
        actorUserId: TEST_USER_IDS.organizer1,
        createdAfter: auditSnapshot.createdAfter,
        groupId,
        resourceId: TEST_USER_IDS.pending1,
      }),
      path: `${GROUP_LOGS_PATH}&action=group_team_member_added&actor=e2e-organizer-1`,
      resourceName: "E2E Pending One",
      resourceType: "User",
    });

    // Delete the owned sponsor from the selected group.
    const deleteSponsorResponse = await organizerGroupPage.request.delete(
      buildE2eUrl(`/dashboard/group/sponsors/${sponsor.sponsorId}/delete`),
    );
    expect(deleteSponsorResponse.status(), "delete sponsor status").toBe(204);

    // Verify the sponsor log row keeps the deleted sponsor name.
    await expectAuditRow(organizerGroupPage, {
      action: "group_sponsor_deleted",
      actionLabel: "Group sponsor deleted",
      actorUsername: "e2e-organizer-1",
      auditLogId: latestAuditLogId({
        action: "group_sponsor_deleted",
        actorUserId: TEST_USER_IDS.organizer1,
        createdAfter: auditSnapshot.createdAfter,
        groupId,
        resourceId: sponsor.sponsorId,
      }),
      path: `${GROUP_LOGS_PATH}&action=group_sponsor_deleted&actor=e2e-organizer-1`,
      resourceName: sponsor.name,
      resourceType: "Group sponsor",
    });
  });

  test("group mute and unmute appear in user logs", async ({ member1Page }) => {
    const mute = { groupId: TEST_GROUP_IDS.community1.alpha, userId: TEST_USER_IDS.member1 };
    const mutePath = `/dashboard/user/notifications/muted-groups/${mute.groupId}`;
    const auditSnapshot = snapshotAuditLogs();

    try {
      // Mute and unmute the group through the user notification endpoints.
      const muteResponse = await member1Page.request.put(buildE2eUrl(mutePath));
      expect(muteResponse.status(), "mute group status").toBe(204);
      const unmuteResponse = await member1Page.request.delete(buildE2eUrl(mutePath));
      expect(unmuteResponse.status(), "unmute group status").toBe(204);

      // Verify each transition has its own user log row.
      for (const [action, actionLabel] of [
        ["group_notifications_muted", "Group notifications muted"],
        ["group_notifications_unmuted", "Group notifications unmuted"],
      ]) {
        await expectAuditRow(member1Page, {
          action,
          actionLabel,
          auditLogId: latestAuditLogId({
            action,
            actorUserId: TEST_USER_IDS.member1,
            createdAfter: auditSnapshot.createdAfter,
            resourceId: TEST_USER_IDS.member1,
          }),
          path: `${USER_LOGS_PATH}&action=${action}`,
          resourceName: "E2E Member One",
          resourceType: "User",
        });
      }
    } finally {
      // Remove the mute if the unmute did not complete.
      cleanupGroupMute(mute);
    }
  });
});

/** Opens the logs page and asserts the new audit row and its details card. */
const expectAuditRow = async (
  page,
  { action, actionLabel, actorUsername, auditLogId, path, resourceName, resourceType },
) => {
  await navigateToPath(page, path);
  const dashboardContent = page.locator("#dashboard-content");
  const detailsCard = dashboardContent.locator(`#audit-log-details-${auditLogId}`);
  const auditRow = detailsCard.locator("xpath=ancestor::tr[contains(@class, 'audit-log-row')]");

  await expect(dashboardContent.getByText("Logs", { exact: true })).toBeVisible();
  await expect(detailsCard, `new ${action} audit details ${auditLogId}`).toBeAttached();
  await expect(auditRow, `new ${action} audit row ${auditLogId}`).toBeVisible();
  await expect(auditRow).toContainText(actionLabel);
  await expect(auditRow).toContainText(resourceName);
  await expect(auditRow).toContainText(resourceType);

  if (actorUsername) {
    await expect(auditRow).toContainText(actorUsername);
  }
};

/** Returns the latest matching audit_log identifier created after the snapshot, optionally per group. */
const latestAuditLogId = ({ action, actorUserId, createdAfter, groupId, resourceId }) => {
  const groupFilter = groupId ? `and group_id = '${groupId}'::uuid` : "";
  const [row] = queryE2eDatabaseRows(`
    select audit_log_id
    from audit_log
    where action = '${action}'
    and actor_user_id = '${actorUserId}'::uuid
    and created_at >= '${createdAfter}'::timestamptz
    and resource_id = '${resourceId}'::uuid
    ${groupFilter}
    order by created_at desc, audit_log_id desc
    limit 1
  `);

  if (!row) {
    throw new Error(`Expected a new ${action} audit log row`);
  }

  return row[0];
};

/** Returns the markdown editor content after opening the target path. */
const readMarkdownValue = async (page, { editorId, path }) => {
  await navigateToPath(page, path);
  const editor = page.locator(`markdown-editor#${editorId}`);
  await expect(editor).toBeVisible();

  return (await editor.getAttribute("content")) ?? "";
};

/** Returns the account name field value from the user dashboard. */
const readUserName = async (page) => {
  await navigateToPath(page, USER_ACCOUNT_PATH);
  const nameInput = page.locator("#name");
  await expect(nameInput).toBeVisible();

  return nameInput.inputValue();
};

/** Saves the community description through the dashboard form. */
const saveCommunityDescription = async (page, description) => {
  await navigateToPath(page, "/dashboard/community?tab=settings");
  await fillMarkdownEditor(page, "description", description);
  await waitForActionResponse(page, () => page.getByRole("button", { name: "Update Settings" }).click(), {
    method: "PUT",
    urlIncludes: "/dashboard/community/settings/update",
  });
};

/** Saves the group description through the dashboard form. */
const saveGroupDescription = async (page, description) => {
  await navigateToPath(page, "/dashboard/group?tab=settings");
  await fillMarkdownEditor(page, "description", description);
  await waitForActionResponse(page, () => page.getByRole("button", { name: "Update Group" }).click(), {
    method: "PUT",
    urlIncludes: "/dashboard/group/settings/update",
  });
};

/** Saves the account name through the user dashboard form. */
const saveUserName = async (page, name) => {
  await navigateToPath(page, USER_ACCOUNT_PATH);
  const detailsForm = page.locator("#user-details-form");
  await expect(detailsForm).toBeVisible();
  await detailsForm.locator("#name").fill(name);
  await waitForActionResponse(page, () => detailsForm.getByRole("button", { name: "Save" }).click(), {
    method: "PUT",
    urlIncludes: "/dashboard/account/update/details",
  });
};

/** Returns an audit_log timestamp snapshot for later assertions. */
const snapshotAuditLogs = () => ({ createdAfter: queryE2eDatabase("select clock_timestamp()") });
