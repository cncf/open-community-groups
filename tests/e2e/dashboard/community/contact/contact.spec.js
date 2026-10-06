import { queryE2eDatabase, queryE2eDatabaseRows } from "../../../database.js";
import { expect, test } from "../../../fixtures.js";
import {
  deleteNotifications,
  expectNewNotifications,
  snapshotNotifications,
} from "../../../notifications.js";
import { TEST_COMMUNITY_IDS } from "../../../seed.js";
import { navigateToPath, uniqueName, waitForActionResponse } from "../../../utils.js";
import { ensureCommunityGroupsManagerRole } from "../helpers.js";

const COMMUNITY_ID = TEST_COMMUNITY_IDS.community1;
const CONTACT_PATH = "/dashboard/community?tab=contact";
const CONTACT_LOGS_PATH = "/dashboard/community?tab=logs&action=community_custom_notification_sent";
const RECIPIENTS_URL = "/dashboard/community/contact/recipients";
const SEND_URL = "/dashboard/community/notifications";

test.describe("community dashboard contact view", () => {
  test("contact menu item appears below groups", async ({ adminCommunityPage }) => {
    // Load the contact tab.
    await navigateToPath(adminCommunityPage, CONTACT_PATH);

    // Verify the Contact item directly follows the Groups item.
    const menuItems = await adminCommunityPage.locator("#dashboard-menu a").allInnerTexts();
    const labels = menuItems.map((label) => label.trim());
    expect(labels.indexOf("Contact")).toBe(labels.indexOf("Groups") + 1);
    await expect(adminCommunityPage.locator("#community-contact-form")).toBeVisible();
  });

  test("community viewer can review recipients but cannot send", async ({ communityViewerPage }) => {
    // Load the contact tab as a read-only community member.
    await navigateToPath(communityViewerPage, CONTACT_PATH);
    const dashboardContent = communityViewerPage.locator("#dashboard-content");

    // Verify the summary is visible while sending is disabled.
    await expect(dashboardContent).toContainText("Your role can review recipients but cannot send emails");
    await expect(summary(communityViewerPage)).toHaveAttribute(
      "data-people-count",
      String(expectedSummary({}).people_count),
    );
    await expect(communityViewerPage.locator("#community-contact-submit")).toBeDisabled();
  });

  test("live counts follow the selected filters", async ({ adminCommunityPage }) => {
    // Load the contact tab and check the unfiltered audience.
    await navigateToPath(adminCommunityPage, CONTACT_PATH);
    await expect(summary(adminCommunityPage)).toHaveAttribute(
      "data-people-count",
      String(expectedSummary({}).people_count),
    );

    // Select the admin role and wait for the refreshed preview.
    await selectOption(adminCommunityPage, "Team roles", "Admin");

    // Verify the preview matches the admin-only audience.
    await expect(summary(adminCommunityPage)).toHaveAttribute(
      "data-people-count",
      String(expectedSummary({ roles: ["admin"] }).people_count),
    );
  });

  test("no region option filters groups without a region", async ({ adminCommunityPage }) => {
    test.skip(countRegions() === 0, "the seeded community has no regions");

    // Load the contact tab and select the no region option.
    await navigateToPath(adminCommunityPage, CONTACT_PATH);
    await selectOption(adminCommunityPage, "Regions", /^No region/);

    // Verify the preview matches the groups without a region.
    await expect(summary(adminCommunityPage)).toHaveAttribute(
      "data-people-count",
      String(expectedSummary({ regions: ["none"] }).people_count),
    );
  });

  test("cancelling the confirmation sends nothing", async ({ adminCommunityPage }) => {
    // Load the contact tab and write a message.
    await navigateToPath(adminCommunityPage, CONTACT_PATH);
    await adminCommunityPage.locator("#community-contact-body").fill("This message is never sent");
    const snapshot = snapshotNotifications();

    // Open and cancel the confirmation dialog.
    await adminCommunityPage.locator("#community-contact-submit").click();
    const dialog = adminCommunityPage.locator(".swal2-popup");
    await expect(dialog).toContainText(`Send this email to ${expectedSummary({}).people_count}`);
    await dialog.getByRole("button", { name: "No" }).click();

    // Verify nothing was queued and the message is kept.
    expectNewNotifications(snapshot, []);
    await expect(adminCommunityPage.locator("#community-contact-body")).toHaveValue(
      "This message is never sent",
    );
  });

  test("admin sends one email per person and the logs name the filters", async ({ adminCommunityPage }) => {
    // Load the contact tab and select the admin role.
    await navigateToPath(adminCommunityPage, CONTACT_PATH);
    await selectOption(adminCommunityPage, "Team roles", "Admin");
    const recipients = expectedRecipients({ roles: ["admin"] });
    expect(recipients.length).toBeGreaterThan(0);

    // Send the message after confirming the audience.
    const subject = uniqueName("contact admins");
    const snapshot = snapshotNotifications();
    await sendMessage(adminCommunityPage, subject);

    // Verify the message is cleared while the filters are kept.
    await expect(adminCommunityPage.locator("#community-contact-subject")).toHaveValue("");
    await expect(adminCommunityPage.locator("#community-contact-body")).toHaveValue("");
    await expect(
      adminCommunityPage.locator('#community-contact-filters input[name="filters[roles][]"]'),
    ).toHaveValue("admin");

    // Verify one notification was queued per deduplicated person.
    const notificationIds = expectNewNotifications(snapshot, [
      { kind: "community-custom", templateDataContains: { subject }, userIds: recipients },
    ]);
    deleteNotifications(notificationIds);

    // Verify the audit log names the filters used.
    await navigateToPath(adminCommunityPage, CONTACT_LOGS_PATH);
    const auditLogRow = adminCommunityPage
      .locator("#dashboard-content tr.audit-log-row", { hasText: "Community custom notification sent" })
      .first();
    await expect(auditLogRow).toBeVisible();
    const detailsButton = auditLogRow.getByRole("button", { name: "View log details" });
    await detailsButton.click();
    const detailsPopover = adminCommunityPage.locator(
      `#${await detailsButton.getAttribute("aria-controls")}`,
    );
    await expect(detailsPopover).toContainText(subject);
    await expect(detailsPopover).toContainText("Admin");
    await expect(detailsPopover).toContainText("All");
  });

  test("groups manager can send to group teams", async ({ adminCommunityPage, groupsManagerPage }) => {
    // Make sure the seeded manager holds the groups-manager role.
    await ensureCommunityGroupsManagerRole("groups-manager", adminCommunityPage);

    // Load the contact tab and select the admin role.
    await navigateToPath(groupsManagerPage, CONTACT_PATH);
    await selectOption(groupsManagerPage, "Team roles", "Admin");

    // Send the message and clean up the queued notifications.
    const subject = uniqueName("contact from groups manager");
    const snapshot = snapshotNotifications();
    await sendMessage(groupsManagerPage, subject);
    const notificationIds = expectNewNotifications(snapshot, [
      {
        kind: "community-custom",
        templateDataContains: { subject },
        userIds: expectedRecipients({ roles: ["admin"] }),
      },
    ]);
    deleteNotifications(notificationIds);
  });
});

/** Returns the number of regions of the seeded community. */
const countRegions = () =>
  Number(queryE2eDatabase(`select count(*) from region where community_id = '${COMMUNITY_ID}'`));

/** Returns the distinct users the database resolves for the filters. */
const expectedRecipients = (filters) =>
  queryE2eDatabaseRows(`
    select distinct user_id
    from community_contact_team_seats('${COMMUNITY_ID}', '${JSON.stringify(filters)}'::jsonb)
  `).map(([userId]) => userId);

/** Returns the recipients summary the database computes for the filters. */
const expectedSummary = (filters) =>
  JSON.parse(
    queryE2eDatabase(
      `select get_community_contact_recipients_summary('${COMMUNITY_ID}', '${JSON.stringify(filters)}'::jsonb)`,
    ),
  );

/** Selects an option of a contact filter and waits for the refreshed preview. */
const selectOption = async (page, filterName, optionName) => {
  await page.getByRole("combobox", { name: filterName }).click();
  await waitForActionResponse(page, () => page.getByRole("option", { name: optionName }).click(), {
    method: "GET",
    urlIncludes: RECIPIENTS_URL,
  });
  await page.keyboard.press("Escape");
};

/** Writes and sends a contact message, confirming the dialog. */
const sendMessage = async (page, subject) => {
  await page.locator("#community-contact-subject").fill(subject);
  await page.locator("#community-contact-body").fill("Hello group teams");
  await expect(page.locator("#community-contact-submit")).toBeEnabled();
  await page.locator("#community-contact-submit").click();
  await waitForActionResponse(
    page,
    () => page.locator(".swal2-popup").getByRole("button", { name: "Send", exact: true }).click(),
    { method: "POST", status: 204, urlEndsWith: SEND_URL },
  );
};

/** Returns the recipients summary element. */
const summary = (page) => page.locator("#community-contact-summary");
