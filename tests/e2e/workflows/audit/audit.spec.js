import { expect, test } from "../../fixtures.js";
import { queryE2eDatabase, queryE2eDatabaseRows } from "../../database.js";
import { TEST_COMMUNITY_IDS, TEST_GROUP_IDS, TEST_USER_IDS } from "../../seed.js";
import { navigateToPath, waitForActionResponse } from "../../utils.js";
import { fillMarkdownEditor } from "../../dashboard/form-helpers.js";

const COMMUNITY_LOGS_PATH = "/dashboard/community?tab=logs";

const GROUP_LOGS_PATH = "/dashboard/group?tab=logs";

const USER_ACCOUNT_PATH = "/dashboard/user?tab=account";

const USER_LOGS_PATH = "/dashboard/user?tab=logs";

const ADMIN_ONE_ID = "77777777-7777-7777-7777-777777777701";

test.describe("dashboard audit workflow", () => {
  test("community settings mutation appears in community logs", async ({ adminCommunityPage }) => {
    // Snapshot the original community description and audit baseline.
    const originalDescription = await readMarkdownValue(adminCommunityPage, {
      editorId: "description",
      path: "/dashboard/community?tab=settings",
    });
    const updatedDescription = `${originalDescription}\n\nE2E audit community update.`;
    const auditSnapshot = snapshotAuditLogs();
    let auditLogId;

    try {
      // Save the updated community description and locate its audit entry.
      await saveCommunityDescription(adminCommunityPage, updatedDescription);
      auditLogId = latestAuditLogId({
        action: "community_updated",
        actorUserId: ADMIN_ONE_ID,
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
      // Restore the original community description.
      await saveCommunityDescription(adminCommunityPage, originalDescription);
    }
  });

  test("group settings mutation appears in group logs", async ({ organizerGroupPage }) => {
    // Snapshot the original group description and audit baseline.
    const originalDescription = await readMarkdownValue(organizerGroupPage, {
      editorId: "description",
      path: "/dashboard/group?tab=settings",
    });
    const updatedDescription = `${originalDescription}\n\nE2E audit group update.`;
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
      // Restore the original group description.
      await saveGroupDescription(organizerGroupPage, originalDescription);
    }
  });

  test("user profile mutation appears in user logs", async ({ member1Page }) => {
    // Snapshot the original user name and audit baseline.
    const originalName = await readUserName(member1Page);
    const updatedName = `${originalName} Audit`;
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
      // Restore the original user name.
      await saveUserName(member1Page, originalName);
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

/** Returns the latest matching audit_log identifier created after the snapshot. */
const latestAuditLogId = ({ action, actorUserId, createdAfter, resourceId }) => {
  const [row] = queryE2eDatabaseRows(`
    select audit_log_id
    from audit_log
    where action = '${action}'
    and actor_user_id = '${actorUserId}'::uuid
    and created_at >= '${createdAfter}'::timestamptz
    and resource_id = '${resourceId}'::uuid
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
