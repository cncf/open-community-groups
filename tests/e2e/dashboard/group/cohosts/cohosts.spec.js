import { expect, test } from "../../../fixtures.js";

import { cleanupCohostEvents, setupCohostEvent } from "../../../data-graphs/cohosts.js";
import { TEST_COHOSTED_EVENT, TEST_COMMUNITY_IDS, TEST_GROUP_IDS, TEST_GROUP_NAMES } from "../../../seed.js";
import {
  buildE2eUrl,
  expectPaginationNavigation,
  navigateToPath,
  selectGroupContext,
  waitForActionResponse,
} from "../../../utils.js";
import { expectCohostDashboardRow, getCohostDashboardRows } from "./helpers.js";

// Group co-hosts dashboard tab path.
const COHOSTS_PATH = "/dashboard/group?tab=cohosts";
// Owning group shown for the seeded cross-community event.
const SEEDED_OWNER_GROUP_NAME = "E2E Second Group Epsilon";

test.describe("group dashboard co-hosts", () => {
  test("menu opens the empty co-hosts list", async ({ organizerEmptyGroupPage }) => {
    // Open the co-hosts tab from the dashboard menu.
    await navigateToPath(organizerEmptyGroupPage, "/dashboard/group?tab=events");
    const cohostsLink = organizerEmptyGroupPage.locator(`a[hx-get="${COHOSTS_PATH}"]`);
    await expect(cohostsLink).toContainText("Co-hosts");
    await waitForActionResponse(organizerEmptyGroupPage, () => cohostsLink.click(), {
      method: "GET",
      urlIncludes: COHOSTS_PATH,
    });

    // Verify the empty state and pushed URL.
    await expect(organizerEmptyGroupPage).toHaveURL(/\/dashboard\/group\?tab=cohosts$/u);
    await expect(organizerEmptyGroupPage.getByRole("table", { name: "Co-hosted events list" })).toBeVisible();
    await expect(
      organizerEmptyGroupPage.getByText("No co-hosted events found").filter({ visible: true }),
    ).toBeVisible();
  });

  test("read-only co-host team members see approved invitations without actions", async ({
    organizerGroupPage,
  }) => {
    // Switch the organizer into the group where they only have viewer access.
    await selectGroupContext(
      organizerGroupPage,
      TEST_COMMUNITY_IDS.community1,
      TEST_GROUP_IDS.community1.gamma,
    );

    // Verify the seeded co-hosted event row and its owner details.
    await navigateToPath(organizerGroupPage, COHOSTS_PATH);
    const row = await expectCohostDashboardRow(organizerGroupPage, TEST_COHOSTED_EVENT.name, "Approved");
    await expect(row).toContainText(SEEDED_OWNER_GROUP_NAME);
    await expect(row.getByRole("link", { name: TEST_COHOSTED_EVENT.name })).toHaveAttribute(
      "href",
      new RegExp(`/group/second-group-epsilon/event/${TEST_COHOSTED_EVENT.slug}$`, "u"),
    );
    await expect(row.getByLabel(`Open co-host actions for ${TEST_COHOSTED_EVENT.name}`)).toHaveCount(0);

    // Verify co-hosted events stay out of the co-host group's own events list.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events&events_tab=upcoming&limit=100");
    await expect(organizerGroupPage.getByRole("button", { name: "Add Event" })).toBeVisible();
    await expect(
      organizerGroupPage.locator("#dashboard-content tbody tr", { hasText: TEST_COHOSTED_EVENT.name }),
    ).toHaveCount(0);
  });

  test("team members without settings access cannot respond to pending invitations", async ({
    eventsManagerGroupPage,
    groupViewerPage,
  }) => {
    const scenario = setupCohostEvent({
      cohosts: [{ groupId: TEST_GROUP_IDS.community1.alpha }],
      ownerGroupId: TEST_GROUP_IDS.community2.delta,
    });

    try {
      for (const page of [eventsManagerGroupPage, groupViewerPage]) {
        // Verify the pending invitation is visible without row actions.
        await navigateToPath(page, COHOSTS_PATH);
        const row = await expectCohostDashboardRow(page, scenario.name, "Pending");
        await expect(row.getByLabel(`Open co-host actions for ${scenario.name}`)).toHaveCount(0);
      }
    } finally {
      // Restore seeded state.
      cleanupCohostEvents([scenario.eventId]);
    }
  });

  test("stale co-host actions report the server error", async ({
    organizerGroupPage,
    organizerGroupWithoutPaymentsPage,
  }) => {
    const scenario = setupCohostEvent({ cohosts: [{ groupId: TEST_GROUP_IDS.community2.delta }] });

    try {
      // Open the pending invitation actions as the co-host.
      await navigateToPath(organizerGroupWithoutPaymentsPage, COHOSTS_PATH);
      const row = await expectCohostDashboardRow(organizerGroupWithoutPaymentsPage, scenario.name, "Pending");
      await row.getByLabel(`Open co-host actions for ${scenario.name}`).click();

      // Delete the event as the owner while the co-host list stays open.
      const deleteResponse = await organizerGroupPage.request.delete(
        buildE2eUrl(`/dashboard/group/events/${scenario.eventId}/delete`),
      );
      expect(deleteResponse.ok()).toBe(true);

      // Approve from the stale row and verify the server error is shown.
      await row.getByRole("button", { name: "Approve" }).click();
      const dialog = organizerGroupWithoutPaymentsPage.locator(".swal2-popup");
      await waitForActionResponse(
        organizerGroupWithoutPaymentsPage,
        () => dialog.getByRole("button", { name: "Approve" }).click(),
        {
          method: "PUT",
          status: 422,
          urlEndsWith: `/${scenario.invitationIds[TEST_GROUP_IDS.community2.delta]}/approve`,
        },
      );
      await expect(dialog).toContainText("co-hosting invitation not found");
      await dialog.getByRole("button", { name: "OK", exact: true }).click();

      // Verify a fresh load drops the deleted event.
      await navigateToPath(organizerGroupWithoutPaymentsPage, COHOSTS_PATH);
      await expect(getCohostDashboardRows(organizerGroupWithoutPaymentsPage, scenario.name)).toHaveCount(0);
    } finally {
      // Restore seeded state.
      cleanupCohostEvents([scenario.eventId]);
    }
  });

  test("co-hosts list paginates invitations", async ({ organizerGroupWithoutPaymentsPage }) => {
    const scenarios = [
      setupCohostEvent({ cohosts: [{ groupId: TEST_GROUP_IDS.community2.delta }], days: 210 }),
      setupCohostEvent({ cohosts: [{ groupId: TEST_GROUP_IDS.community2.delta }], days: 220 }),
    ];

    try {
      // Verify forward and backward pagination with one invitation per page.
      await expectPaginationNavigation(
        organizerGroupWithoutPaymentsPage,
        `${COHOSTS_PATH}&limit=1`,
        '[aria-label="Co-hosted events list"] tbody th[scope="row"]',
      );
    } finally {
      // Restore seeded state.
      cleanupCohostEvents(scenarios.map(({ eventId }) => eventId));
    }
  });

  test("owner group names are shown for pending invitations", async ({ organizerGroupPage }) => {
    const scenario = setupCohostEvent({
      cohosts: [{ groupId: TEST_GROUP_IDS.community1.alpha }],
      ownerGroupId: TEST_GROUP_IDS.community1.gamma,
    });

    try {
      // Verify the co-host admin can act on an invitation from another group.
      await navigateToPath(organizerGroupPage, COHOSTS_PATH);
      const row = await expectCohostDashboardRow(organizerGroupPage, scenario.name, "Pending");
      await expect(row).toContainText(TEST_GROUP_NAMES.gamma);
      await row.getByLabel(`Open co-host actions for ${scenario.name}`).click();
      await expect(row.getByRole("button", { name: "Approve" })).toBeVisible();
      await expect(row.getByRole("button", { name: "Reject" })).toBeVisible();
      await expect(row.getByRole("button", { name: "Cancel co-hosting" })).toHaveCount(0);
    } finally {
      // Restore seeded state.
      cleanupCohostEvents([scenario.eventId]);
    }
  });
});
