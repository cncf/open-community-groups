import { expect, test } from "../../fixtures.js";
import { queryCount, queryScalar, sqlString, sqlUuid } from "../../database.js";
import { cleanupEventCategoriesByName } from "../../data-graphs/communities.js";
import { cleanupGroupSponsor, setupGroupSponsor } from "../../data-graphs/groups.js";
import {
  TEST_COMMUNITY_IDS,
  TEST_COMMUNITY_TITLE_2,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
} from "../../seed.js";
import {
  confirmAlert,
  dismissAlert,
  navigateToPath,
  selectCommunityContext,
  selectGroupContext,
  uniqueName,
  waitForActionResponse,
  waitForResponseMatching,
} from "../../utils.js";

// Alert shown once after a stale dashboard context reload (`static/js/common/dashboard-context.js`).
const DASHBOARD_CONTEXT_REFRESH_MESSAGE = "Your dashboard selection changed, so this page was refreshed.";

test.describe("stale dashboard context guard", () => {
  test("a group action from a tab rendered for another group reloads without running", async ({
    organizerGroupPage,
    owned,
  }) => {
    const sponsor = owned.track(
      setupGroupSponsor({ groupId: TEST_GROUP_IDS.community1.alpha }),
      cleanupGroupSponsor,
    );
    let otherTab;

    try {
      // Load the sponsors tab for the primary group in tab A.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=sponsors");
      const featuredToggle = organizerGroupPage
        .locator("#dashboard-content tr", { hasText: sponsor.name })
        .getByRole("checkbox", { name: `Visible on group page for ${sponsor.name}` });
      await expect(featuredToggle).toBeChecked();

      // Select another group from tab B of the same browser session.
      otherTab = await organizerGroupPage.context().newPage();
      await navigateToPath(otherTab, "/dashboard/group?tab=events");
      await otherTab.locator("#group-selector-button").click();
      await waitForActionResponse(
        otherTab,
        () => otherTab.locator(`#group-option-${TEST_GROUP_IDS.community1.gamma}`).click(),
        {
          method: "PUT",
          status: 204,
          urlEndsWith: `/dashboard/group/${TEST_GROUP_IDS.community1.gamma}/select`,
        },
      );
      await expect(otherTab.locator("#group-selector-button")).toContainText(TEST_GROUP_NAMES.gamma);

      // Hide the sponsor from tab A; the page reloads, so HTMX is not settled.
      const featuredResponse = waitForResponseMatching(organizerGroupPage, {
        method: "PUT",
        pathname: `/dashboard/group/sponsors/${sponsor.sponsorId}/featured`,
        status: 204,
      });
      await featuredToggle.click({ force: true });
      await confirmAlert(organizerGroupPage, {
        button: "Continue",
        message: "This sponsor will no longer be visible on the public group page.",
      });
      const response = await featuredResponse;

      // Verify the server refused the request issued for the primary group.
      expect(response.headers()["x-ocg-stale-dashboard-context"]).toBe("true");
      expect(await response.request().headerValue("x-ocg-selected-group-id")).toBe(
        TEST_GROUP_IDS.community1.alpha,
      );

      // Verify tab A reloads the dashboard root once for the selected group.
      await expect(organizerGroupPage).toHaveURL(/\/dashboard\/group$/);
      await expect(organizerGroupPage.locator(".swal2-popup")).toHaveCount(1);
      await dismissAlert(organizerGroupPage, { message: DASHBOARD_CONTEXT_REFRESH_MESSAGE });
      await expect(organizerGroupPage.locator("#group-selector-button")).toContainText(
        TEST_GROUP_NAMES.gamma,
      );
      await expect(organizerGroupPage.locator("#dashboard-content")).toHaveAttribute(
        "data-group-slug",
        TEST_GROUP_SLUGS.community1.gamma,
      );

      // Verify the handler never ran: the sponsor is still featured.
      expect(
        queryScalar(
          `select featured from group_sponsor where group_sponsor_id = ${sqlUuid(sponsor.sponsorId)};`,
        ),
      ).toBe("t");
    } finally {
      // Close tab B and restore the primary group for later scenarios.
      await otherTab?.close();
      await selectGroupContext(
        organizerGroupPage,
        TEST_COMMUNITY_IDS.community1,
        TEST_GROUP_IDS.community1.alpha,
      );
    }
  });

  test("a community form submitted from a tab rendered for another community reloads without saving", async ({
    adminCommunityPage,
    owned,
  }) => {
    const categoryName = uniqueName("Event Category");
    owned.defer(() => cleanupEventCategoriesByName(categoryName));
    let otherTab;

    try {
      // Open the event category add form for the primary community in tab A.
      await navigateToPath(adminCommunityPage, "/dashboard/community?tab=event-categories");
      const dashboardContent = adminCommunityPage.locator("#dashboard-content");
      await dashboardContent.getByRole("button", { name: "Add Event Category" }).click();
      await expect(dashboardContent.getByText("Event Category Details", { exact: true })).toBeVisible();
      await adminCommunityPage.getByLabel("Name").fill(categoryName);

      // Select the secondary community from tab B of the same browser session.
      otherTab = await adminCommunityPage.context().newPage();
      await navigateToPath(otherTab, "/dashboard/community?tab=groups");
      await otherTab.locator("#community-selector-button").click();
      await waitForActionResponse(
        otherTab,
        () => otherTab.locator(`#community-option-${TEST_COMMUNITY_IDS.community2}`).click(),
        {
          method: "PUT",
          status: 204,
          urlEndsWith: `/dashboard/community/${TEST_COMMUNITY_IDS.community2}/select`,
        },
      );
      await expect(otherTab.locator("#community-selector-button")).toContainText(TEST_COMMUNITY_TITLE_2);

      // Submit the form from tab A; the page reloads, so HTMX is not settled.
      const addResponse = waitForResponseMatching(adminCommunityPage, {
        method: "POST",
        pathname: "/dashboard/community/event-categories/add",
        status: 204,
      });
      await adminCommunityPage.getByRole("button", { name: "Add Event Category" }).click();
      const response = await addResponse;

      // Verify the server refused the request issued for the primary community.
      expect(response.headers()["x-ocg-stale-dashboard-context"]).toBe("true");
      expect(await response.request().headerValue("x-ocg-selected-community-id")).toBe(
        TEST_COMMUNITY_IDS.community1,
      );

      // Verify tab A reloads the dashboard root once for the selected community.
      await expect(adminCommunityPage).toHaveURL(/\/dashboard\/community$/);
      await expect(adminCommunityPage.locator(".swal2-popup")).toHaveCount(1);
      await dismissAlert(adminCommunityPage, { message: DASHBOARD_CONTEXT_REFRESH_MESSAGE });
      await expect(adminCommunityPage.locator("#community-selector-button")).toContainText(
        TEST_COMMUNITY_TITLE_2,
      );

      // Verify the handler never ran: no category was saved in any community.
      expect(queryCount(`select count(*) from event_category where name = ${sqlString(categoryName)};`)).toBe(
        0,
      );
    } finally {
      // Close tab B and restore the primary community for later scenarios.
      await otherTab?.close();
      await selectCommunityContext(adminCommunityPage, TEST_COMMUNITY_IDS.community1);
    }
  });
});
