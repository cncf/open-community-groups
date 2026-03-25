import { expect, test } from "../../fixtures";

import { TEST_EVENT_IDS, navigateToPath } from "../../utils";

test.describe("group dashboard submissions view", () => {
  test("events manager can review CFS submissions with labels and ratings", async ({
    eventsManagerGroupPage,
  }) => {
    await navigateToPath(eventsManagerGroupPage, "/dashboard/group?tab=events");

    const cfsEventRow = eventsManagerGroupPage.locator("tr", {
      hasText: "Event With Active CFS",
    });
    await expect(cfsEventRow).toBeVisible();

    await Promise.all([
      eventsManagerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`) &&
          response.ok(),
      ),
      cfsEventRow
        .locator('td button[aria-label="Edit event: Event With Active CFS"]')
        .click(),
    ]);

    await Promise.all([
      eventsManagerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(
            `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions`,
          ) &&
          response.ok(),
      ),
      eventsManagerGroupPage.locator('button[data-section="submissions"]').click(),
    ]);

    await expect(
      eventsManagerGroupPage.locator("#submissions-content").getByText("Submissions", {
        exact: true,
      }),
    ).toBeVisible();
    const sortBy = eventsManagerGroupPage.getByLabel("Sort by");
    await expect(sortBy).toBeVisible();
    await expect(sortBy).toContainText("Stars (high to low)");
    await expect(sortBy).toContainText("Ratings count (high to low)");

    const notReviewedRow = eventsManagerGroupPage.locator("tr", {
      hasText: "Platform Reliability Patterns",
    });
    await expect(notReviewedRow).toContainText("Platform");

    const informationRequestedRow = eventsManagerGroupPage.locator("tr", {
      hasText: "Observability in Practice",
    });
    await expect(informationRequestedRow).toContainText("Workshop");
    await expect(informationRequestedRow).toContainText("1 rating");

    const approvedRow = eventsManagerGroupPage.locator("tr", {
      hasText: "Scaling Community Workshops",
    });
    await expect(approvedRow).toContainText("Platform");
    await expect(approvedRow).toContainText("Workshop");
    await expect(approvedRow).toContainText("2 ratings");
    await expect(approvedRow).toContainText("Approved");
    await expect(approvedRow.getByTitle("Review submission")).toBeEnabled();
  });

  test("viewer sees read-only event and submission controls", async ({
    groupViewerPage,
  }) => {
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=events");

    const dashboardContent = groupViewerPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: "Add Event" }),
    ).toBeDisabled();

    const cfsEventRow = groupViewerPage.locator("tr", {
      hasText: "Event With Active CFS",
    });
    await expect(cfsEventRow).toBeVisible();

    await Promise.all([
      groupViewerPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`) &&
          response.ok(),
      ),
      cfsEventRow
        .locator('td button[aria-label="Edit event: Event With Active CFS"]')
        .click(),
    ]);

    await Promise.all([
      groupViewerPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(
            `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions`,
          ) &&
          response.ok(),
      ),
      groupViewerPage.locator('button[data-section="submissions"]').click(),
    ]);

    const reviewButtons = groupViewerPage.getByTitle("Your role cannot manage events.");
    await expect(reviewButtons.first()).toBeDisabled();
  });
});
