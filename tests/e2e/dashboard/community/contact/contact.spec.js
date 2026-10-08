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

  test("going back to the contact tab reloads a current preview", async ({ adminCommunityPage }) => {
    // Load the contact tab and narrow the audience to admins.
    await navigateToPath(adminCommunityPage, CONTACT_PATH);
    await selectOption(adminCommunityPage, "Team roles", "Admin");

    // Leave the tab through the dashboard menu.
    const groupsLink = adminCommunityPage
      .locator("#dashboard-menu")
      .getByRole("link", { name: "Groups", exact: true });
    await waitForActionResponse(adminCommunityPage, () => groupsLink.click(), {
      method: "GET",
      urlIncludes: "tab=groups",
    });

    // Return through browser history and wait for the page to reload.
    await waitForActionResponse(adminCommunityPage, () => adminCommunityPage.goBack(), {
      method: "GET",
      urlIncludes: "tab=contact",
    });

    // Verify the filters are reset and the preview matches them.
    await expect(adminCommunityPage.locator('input[name="filters[roles][]"]')).toHaveCount(0);
    await expect(summary(adminCommunityPage)).toHaveAttribute(
      "data-people-count",
      String(expectedSummary({}).people_count),
    );
    await expect(adminCommunityPage.locator("#community-contact-submit")).toBeEnabled();
  });

  test("a failed preview can be retried", async ({ adminCommunityPage }) => {
    // Load the contact tab and make the next previews fail.
    await navigateToPath(adminCommunityPage, CONTACT_PATH);
    await adminCommunityPage.route(`**${RECIPIENTS_URL}*`, (route) => route.fulfill({ status: 500 }));

    // Change a filter and wait for the failed preview.
    await adminCommunityPage.getByRole("combobox", { name: "Team roles" }).click();
    await adminCommunityPage.getByRole("option", { name: "Admin" }).click();
    const recipients = adminCommunityPage.locator("#community-contact-recipients");
    await expect(recipients.getByRole("alert")).toContainText(
      "Something went wrong while loading the recipients",
    );
    await expect(adminCommunityPage.locator("#community-contact-submit")).toBeDisabled();

    // Let the previews through again and retry.
    await adminCommunityPage.unroute(`**${RECIPIENTS_URL}*`);
    await waitForActionResponse(
      adminCommunityPage,
      () => recipients.getByRole("button", { name: "Retry" }).click(),
      { method: "GET", urlIncludes: RECIPIENTS_URL },
    );

    // Verify the preview matches the filters and focus stays in the summary.
    await expect(summary(adminCommunityPage)).toHaveAttribute(
      "data-people-count",
      String(expectedSummary({ roles: ["admin"] }).people_count),
    );
    await expect(recipients).toBeFocused();
    await expect(recipients).not.toHaveAttribute("aria-busy");
    await expect(adminCommunityPage.locator("#community-contact-submit")).toBeEnabled();
  });

  test("the groups list toggle names its next action", async ({ adminCommunityPage }) => {
    // Load the contact tab with the unfiltered audience.
    await navigateToPath(adminCommunityPage, CONTACT_PATH);
    const toggle = summary(adminCommunityPage).locator("summary");

    // Verify the toggle reads Hide groups when open and Show groups when closed.
    await expect(toggle.getByText("Show groups")).toBeVisible();
    await toggle.click();
    await expect(toggle.getByText("Hide groups")).toBeVisible();
    await expect(toggle.getByText("Show groups")).toBeHidden();
    await toggle.click();
    await expect(toggle.getByText("Show groups")).toBeVisible();
    await expect(toggle.getByText("Hide groups")).toBeHidden();
  });

  test("a whitespace-only message is reported before confirming", async ({ adminCommunityPage }) => {
    // Load the contact tab and write a blank message.
    await navigateToPath(adminCommunityPage, CONTACT_PATH);
    const body = adminCommunityPage.locator("#community-contact-body");
    await body.fill("   ");
    const snapshot = snapshotNotifications();

    // Try to send the blank message.
    await adminCommunityPage.locator("#community-contact-submit").click();

    // Verify the field is reported, no dialog opens and sending stays available.
    await expect(body).toHaveValue("");
    expect(await body.evaluate((field) => field.validity.valueMissing)).toBe(true);
    await expect(adminCommunityPage.locator(".swal2-popup")).toHaveCount(0);
    await expect(adminCommunityPage.locator("#community-contact-submit")).toBeEnabled();
    expectNewNotifications(snapshot, []);
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

/** Selects an option of a contact filter, waits for the refreshed preview and checks the list closed. */
const selectOption = async (page, filterName, optionName) => {
  await page.getByRole("combobox", { name: filterName }).click();
  await waitForActionResponse(page, () => page.getByRole("option", { name: optionName }).click(), {
    method: "GET",
    urlIncludes: RECIPIENTS_URL,
  });
  await expect(page.getByRole("listbox")).toHaveCount(0);
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
