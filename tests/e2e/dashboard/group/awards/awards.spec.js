import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabaseRows } from "../../../database.js";
import { deleteNotifications, snapshotNotifications } from "../../../notifications.js";
import { cleanupCredential, setupRevocableCredential } from "../../../data-graphs/badges.js";
import { TEST_EVENT_IDS, TEST_GROUP_IDS, TEST_USER_IDS } from "../../../seed.js";
import { expectPaginationNavigation, navigateToPath, waitForActionResponse } from "../../../utils.js";

const AWARDS_PATH = "/dashboard/group?tab=awards";

test.describe("group badge award history", () => {
  test("empty state explains where award history will appear", async ({ organizerEmptyGroupPage }) => {
    // Load award history for the dedicated group without credentials.
    await navigateToPath(organizerEmptyGroupPage, AWARDS_PATH);
    const dashboardContent = organizerEmptyGroupPage.locator("#dashboard-content");

    // Verify the zero count and durable-history guidance remain visible.
    await expect(dashboardContent).toContainText("0 awards");
    await expect(dashboardContent).toContainText("No awards matched");
    await expect(dashboardContent).toContainText("Awarded badges and revoked history appear here.");
  });

  test("organizer can move between badge award result pages", async ({ organizerGroupPage }) => {
    // Paginate the seeded award rows with one result per page.
    await expectPaginationNavigation(
      organizerGroupPage,
      `${AWARDS_PATH}&limit=1&offset=0`,
      "#dashboard-content tbody tr",
    );
  });

  test("organizer can search and combine award filters", async ({ organizerGroupPage }) => {
    // Search by recipient and verify the result set.
    await navigateToPath(organizerGroupPage, AWARDS_PATH);
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    const awardsTable = dashboardContent.getByRole("table", {
      name: "Awards list",
    });

    // Search for a seeded recipient and verify only matching awards remain.
    const searchInput = dashboardContent.getByRole("textbox", {
      name: "Search awards",
    });
    await searchInput.fill("E2E Member Two");
    await waitForAwardsRefresh(organizerGroupPage, () => searchInput.press("Enter"));
    await expect(awardsTable.getByText("E2E Member Two", { exact: true }).first()).toBeVisible();
    await expect(awardsTable.getByText("E2E Organizer One", { exact: true })).toHaveCount(0);

    // Combine status, badge, source, and date filters in one form submission.
    const filtersForm = dashboardContent.locator("#awards-filters");
    await waitForAwardsRefresh(organizerGroupPage, () =>
      filtersForm.evaluate((form) => {
        const selectOptionByLabel = (select, label) => {
          const option = [...select.options].find((candidate) => candidate.textContent.trim() === label);

          if (!option) {
            throw new Error(`Missing filter option: ${label}`);
          }
          select.value = option.value;
        };

        selectOptionByLabel(form.elements.namedItem("status"), "Revoked");
        selectOptionByLabel(form.elements.namedItem("badge_id"), "Speaker");
        selectOptionByLabel(form.elements.namedItem("source"), "Upcoming In-Person Event");
        form.elements.namedItem("from").value = "2000-01-01";
        form.elements.namedItem("to").value = "2100-01-01";
        form.requestSubmit();
      }),
    );

    // Verify the active filter chips describe the submitted filters.
    await expect(dashboardContent.getByText("Status: Revoked")).toBeVisible();
    await expect(dashboardContent.getByText("Badge: Speaker")).toBeVisible();
    await expect(dashboardContent.getByText("Source: Upcoming In-Person Event")).toBeVisible();
    await expect(dashboardContent.getByText("Awarded from: 2000-01-01")).toBeVisible();
    await expect(dashboardContent.getByText("Through: 2100-01-01")).toBeVisible();

    // Verify the revoked result row disables duplicate revocation.
    const revokedRow = awardsTable.getByRole("row", {
      name: /E2E Member Two Speaker Upcoming In-Person Event/u,
    });
    await expect(revokedRow).toContainText("Revoked");
    await expect(
      revokedRow.getByRole("button", {
        name: "Revoke credential: Speaker (already revoked)",
      }),
    ).toBeDisabled();

    // Clear every filter and restore the complete history.
    await dashboardContent.getByRole("link", { name: "Clear all" }).click();
    await expect(dashboardContent.getByText("Status: Revoked")).toHaveCount(0);
    await expect(awardsTable.getByText("E2E Organizer One", { exact: true }).first()).toBeVisible();
  });

  test("organizer can permanently revoke an active credential with a reason", async ({
    organizerGroupPage,
  }) => {
    const credential = setupRevocableCredential({
      eventId: TEST_EVENT_IDS.alpha.one,
      groupId: TEST_GROUP_IDS.community1.alpha,
      userId: TEST_USER_IDS.member2,
    });
    const revocationReason = "Credential revoked by the manager E2E scenario.";
    const notificationsSnapshot = snapshotNotifications();

    try {
      // Find the owned active credential.
      await navigateToPath(organizerGroupPage, AWARDS_PATH);
      const dashboardContent = organizerGroupPage.locator("#dashboard-content");
      const searchInput = dashboardContent.getByRole("textbox", {
        name: "Search awards",
      });
      await searchInput.fill(credential.badgeName);
      await waitForAwardsRefresh(organizerGroupPage, () => searchInput.press("Enter"));
      const credentialLink = dashboardContent.locator(
        `a[href="/badges/credentials/${credential.userBadgeId}"]`,
      );
      const credentialRow = credentialLink.locator("xpath=ancestor::tr");

      // Verify the active credential row exposes the expected link and state.
      await expect(credentialLink).toBeVisible();
      await expect(credentialRow).toContainText("E2E Member Two");
      await expect(credentialRow).toContainText("Active");
      await expect(
        credentialRow.getByRole("link", { name: `View credential: ${credential.badgeName}` }),
      ).toHaveAttribute("href", `/badges/credentials/${credential.userBadgeId}`);
      await expect(dashboardContent.locator("[data-group-badges]")).toHaveAttribute(
        "data-group-badges-ready",
        "true",
      );

      // Revoke it and supply the required private reason.
      await credentialRow.getByRole("button", { name: `Revoke credential: ${credential.badgeName}` }).click();
      const revokeDialog = organizerGroupPage.getByRole("dialog", {
        name: `Revoke ${credential.badgeName}`,
      });
      await revokeDialog.getByLabel("Internal reason").fill(revocationReason);
      await waitForActionResponse(
        organizerGroupPage,
        () => revokeDialog.getByRole("button", { name: "Permanently revoke" }).click(),
        {
          method: "POST",
          urlEndsWith: `/badges/awards/${credential.userBadgeId}/revoke`,
          status: 204,
        },
      );

      // Verify the durable history retains the reason and disables the action.
      await expect(credentialRow).toContainText("Revoked");
      await expect(credentialRow).toContainText(revocationReason);
      await expect(
        credentialRow.getByRole("button", {
          name: `Revoke credential: ${credential.badgeName} (already revoked)`,
        }),
      ).toBeDisabled();
    } finally {
      // Remove revocation notifications and temporary credential data.
      deleteNotifications(listRevocationNotificationIds(notificationsSnapshot, TEST_USER_IDS.member2));
      cleanupCredential(credential);
    }
  });
});

/** Returns badge-revoked notification IDs from the notification table. */
const listRevocationNotificationIds = ({ createdAfter }, userId) =>
  queryE2eDatabaseRows(`
    select notification_id
    from notification
    where created_at >= '${createdAfter}'::timestamptz
    and kind = 'badge-revoked'
    and user_id = '${userId}'::uuid
  `).map(([notificationId]) => notificationId);

/** Runs an awards filter action and waits for its HTMX refresh to settle. */
const waitForAwardsRefresh = async (page, action) => {
  await page.evaluate(() => {
    window.__e2eAwardsRefreshSettled = new Promise((resolve) => {
      const handleAwardsRefreshSettled = (event) => {
        const responseUrl = new URL(event.detail.xhr.responseURL);

        if (responseUrl.pathname !== "/dashboard/group/awards") {
          return;
        }

        document.body.removeEventListener("htmx:afterSettle", handleAwardsRefreshSettled);
        resolve();
      };

      document.body.addEventListener("htmx:afterSettle", handleAwardsRefreshSettled);
    });
  });

  const [response] = await Promise.all([
    page.waitForResponse((response) => {
      const responseUrl = new URL(response.url());

      return (
        response.request().method() === "GET" &&
        responseUrl.pathname === "/dashboard/group/awards" &&
        response.ok()
      );
    }),
    action(),
  ]);

  await page.evaluate(() => window.__e2eAwardsRefreshSettled);
  await page.evaluate(() => {
    delete window.__e2eAwardsRefreshSettled;
  });

  return response;
};
