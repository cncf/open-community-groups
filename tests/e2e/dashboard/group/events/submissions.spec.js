import { expect, test } from "../../../fixtures.js";

import {
  TEST_EVENT_IDS,
  expectCurrentPaginationNavigation,
  expectTableColumnsAtViewport,
  expectTableHeaders,
  navigateToPath,
  routeNextRequestWithQuery,
  waitForActionResponse,
} from "../../../utils.js";

const openSubmissionsTab = async (page, query = "") => {
  await navigateToPath(page, "/dashboard/group?tab=events");

  const eventRow = page.locator("tr", {
    hasText: "Event With Active CFS",
  });
  await expect(eventRow).toBeVisible();

  await waitForActionResponse(page, () => eventRow.locator('td button[aria-label^="Edit event:"]').click(), {
    method: "GET",
    urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`,
  });

  // The tab buttons only exist once the event update form has loaded.
  const submissionsTab = page.locator('button[data-section="submissions"]');
  if (query !== "") {
    await routeNextRequestWithQuery(
      page,
      `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions`,
      query,
    );
  }

  await waitForActionResponse(page, () => submissionsTab.click(), {
    method: "GET",
    urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions`,
  });

  return page.locator("#submissions-content");
};

test.describe("group dashboard submissions tab", () => {
  test("submissions table exposes every column at its responsive breakpoint", async ({
    eventsManagerGroupPage,
  }) => {
    // Open the seeded CFS submissions tab before checking table structure.
    const submissionsContent = await openSubmissionsTab(eventsManagerGroupPage);

    // Find the submissions table.
    const submissionsTable = submissionsContent.getByRole("table");

    // Verify header order and column visibility across dashboard breakpoints.
    await expectTableColumnsAtViewport(
      eventsManagerGroupPage,
      submissionsTable,
      1024,
      ["Speaker / Proposal", "Status", "Actions"],
      ["Proposal", "Ratings", "Submitted"],
    );
    await expectTableColumnsAtViewport(
      eventsManagerGroupPage,
      submissionsTable,
      1280,
      ["Speaker / Proposal", "Status", "Ratings", "Actions"],
      ["Proposal", "Submitted"],
    );
    await expectTableColumnsAtViewport(
      eventsManagerGroupPage,
      submissionsTable,
      1536,
      ["Speaker", "Proposal", "Status", "Ratings", "Submitted", "Actions"],
      [],
    );
    await expectTableHeaders(submissionsTable, [
      "Speaker",
      "Proposal",
      "Status",
      "Ratings",
      "Submitted",
      "Actions",
    ]);
  });

  test("events manager can move between submission result pages", async ({
    eventsManagerGroupPage,
  }) => {
    // Open seeded submissions with one result per page.
    await openSubmissionsTab(eventsManagerGroupPage, "?limit=1&offset=0");

    // Verify pagination swaps submission rows in both directions.
    await expectCurrentPaginationNavigation(
      eventsManagerGroupPage,
      "#submissions-content tbody tr",
    );
  });

  test("events manager can review CFS submissions with labels and ratings", async ({
    eventsManagerGroupPage,
  }) => {
    // Load the group events dashboard before opening the CFS event.
    await navigateToPath(eventsManagerGroupPage, "/dashboard/group?tab=events");

    // Find the cfs event row.
    const cfsEventRow = eventsManagerGroupPage.locator("tr", {
      hasText: "Event With Active CFS",
    });

    // Verify events manager can review CFS submissions with labels and ratings.
    await expect(cfsEventRow).toBeVisible();

    // Submit and wait for the server response.
    await waitForActionResponse(
      eventsManagerGroupPage,
      () => cfsEventRow.locator('td button[aria-label="Edit event: Event With Active CFS"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`,
      },
    );

    // Submit and wait for the server response.
    await waitForActionResponse(
      eventsManagerGroupPage,
      () => eventsManagerGroupPage.locator('button[data-section="submissions"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions`,
      },
    );

    // Assert that Submissions is visible.
    await expect(
      eventsManagerGroupPage.locator("#submissions-content").getByText("Submissions", {
        exact: true,
      }),
    ).toBeVisible();
    const sortBy = eventsManagerGroupPage.getByLabel("Sort by");
    await expect(sortBy).toBeVisible();
    await expect(sortBy).toContainText("Stars (high to low)");
    await expect(sortBy).toContainText("Ratings count (high to low)");
    const submissionsContent = eventsManagerGroupPage.locator("#submissions-content");

    // Find the not reviewed row.
    const notReviewedRow = submissionsContent.locator("tr", {
      hasText: "Platform Reliability Patterns",
    });
    await expect(notReviewedRow).toContainText("Platform");

    // Find the information requested row.
    const informationRequestedRow = submissionsContent.locator("tr", {
      hasText: "Observability in Practice",
    });
    await expect(informationRequestedRow).toContainText("Workshop");
    await expect(informationRequestedRow).toContainText("1 rating");

    // Find the approved row.
    const approvedRow = submissionsContent.locator("tr", {
      hasText: "Scaling Community Workshops",
    });
    await expect(approvedRow).toContainText("Platform");
    await expect(approvedRow).toContainText("Workshop");
    await expect(approvedRow).toContainText("2 ratings");
    await expect(approvedRow).toContainText("Approved");
    await expect(approvedRow.getByTitle("Review submission")).toBeEnabled();
  });

  test("viewer sees read-only event and submission controls on the submissions tab", async ({
    groupViewerPage,
  }) => {
    // Load the group events dashboard as a read-only viewer.
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=events");

    // Find the dashboard content.
    const dashboardContent = groupViewerPage.locator("#dashboard-content");

    // Verify viewer sees read-only event and submission controls on the submissions tab.
    await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();
    await expect(dashboardContent.getByRole("button", { name: "Add Event" })).toBeDisabled();

    // Find the cfs event row.
    const cfsEventRow = groupViewerPage.locator("tr", {
      hasText: "Event With Active CFS",
    });
    await expect(cfsEventRow).toBeVisible();

    // Submit and wait for the server response.
    await waitForActionResponse(
      groupViewerPage,
      () => cfsEventRow.locator('td button[aria-label="Edit event: Event With Active CFS"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`,
      },
    );

    // Submit and wait for the server response.
    await waitForActionResponse(
      groupViewerPage,
      () => groupViewerPage.locator('button[data-section="submissions"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions`,
      },
    );

    // Find the review buttons.
    const reviewButtons = groupViewerPage.getByTitle("Your role cannot manage events.");
    await expect(reviewButtons.first()).toBeDisabled();
  });
});
