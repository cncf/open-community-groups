import { expect, test } from "../../../fixtures.js";

import { TEST_EVENT_IDS, TEST_INVITATION_CANCELLATION, navigateToPath } from "../../../utils.js";
import { expectUserProfileModalFromRow } from "./user-profile-modal-helpers.js";

const DASHBOARD_WAITLIST_EVENT_NAME = "Dashboard Waitlist Table Lab";
const PAST_WAITLIST_EVENT_NAME = "Past Event For Filtering";

// Open an event's waitlist tab from the requested dashboard event list.
const openWaitlistTab = async (page, eventName, eventId, { past = false } = {}) => {
  await navigateToPath(page, "/dashboard/group?tab=events");

  if (past) {
    await page.locator("#past-tab").click();
    await expect(page.locator("#past-content")).toBeVisible();
  }

  const eventsContent = page.locator(past ? "#past-content" : "#upcoming-content");
  const eventRow = eventsContent.locator("tr", { hasText: eventName });
  await expect(eventRow).toBeVisible();

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "GET" &&
        response.url().includes(`/dashboard/group/events/${eventId}/update`) &&
        response.ok(),
    ),
    eventRow.locator(`td button[aria-label="Edit event: ${eventName}"]`).click(),
  ]);

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "GET" &&
        response.url().includes(`/dashboard/group/events/${eventId}/waitlist`) &&
        response.ok(),
    ),
    page.locator('button[data-section="waitlist"]').click(),
  ]);

  const waitlistContent = page.locator("#waitlist-content");
  await expect(waitlistContent.getByRole("table", { name: "Waitlist entries" })).toBeVisible();

  return waitlistContent;
};

test.describe("group dashboard waitlist tab", () => {
  test("organizer can open the waitlist tab for an event with waitlist disabled", async ({
    organizerGroupPage,
  }) => {
    // Load the group events dashboard before opening the seeded event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Find the event row.
    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Upcoming In-Person Event",
    });

    // Verify organizer can open the waitlist tab for an event with waitlist disabled.
    await expect(eventRow).toBeVisible();

    // Submit and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`) &&
          response.ok(),
      ),
      eventRow.locator('td button[aria-label="Edit event: Upcoming In-Person Event"]').click(),
    ]);

    // Submit and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/waitlist`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="waitlist"]').click(),
    ]);

    // Find the waitlist content.
    const waitlistContent = organizerGroupPage.locator("#waitlist-content");
    await expect(
      waitlistContent.locator("p.text-sm.lg\\:text-md.text-stone-700:visible").filter({
        hasText: "Enable waitlist to allow full events to add people to the queue.",
      }),
    ).toBeVisible();
  });

  test("organizer can enable waitlist for an event and then restore it", async ({ organizerGroupPage }) => {
    // Open the seeded alpha event editor from the events list.
    const openAlphaEventEditor = async () => {
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

      // Find the event row.
      const eventRow = organizerGroupPage.locator("tr", {
        hasText: "Upcoming In-Person Event",
      });
      await expect(eventRow).toBeVisible();

      // Submit and wait for the server response.
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`) &&
            response.ok(),
        ),
        eventRow.locator('td button[aria-label="Edit event: Upcoming In-Person Event"]').click(),
      ]);
    };

    // Submit the next waitlist value and verify it persisted.
    const submitWaitlistValue = async (nextValue) => {
      await organizerGroupPage.locator('button[data-section="details"]').click();

      // Find the waitlist toggle.
      const waitlistToggle = organizerGroupPage.locator("#toggle_waitlist_enabled");
      const waitlistToggleLabel = organizerGroupPage.locator('[data-enrollment-toggle-label="waitlist"]');

      // Assert the expected content is visible.
      await expect(waitlistToggleLabel).toBeVisible();
      await expect(waitlistToggle).toBeEnabled();

      // Click the waitlist toggle label.
      if ((await waitlistToggle.isChecked()) !== (nextValue === "true")) {
        await waitlistToggleLabel.click();
      }

      // Assert the saved waitlist toggle state.
      await expect(waitlistToggle).toBeChecked({
        checked: nextValue === "true",
      });
      await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue(nextValue);

      // Submit and wait for the server response.
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`) &&
            response.ok(),
        ),
        organizerGroupPage.locator("#update-event-button").click(),
      ]);
    };

    // Reopen the Alpha event editor.
    await openAlphaEventEditor();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("false");

    // Enable the waitlist setting.
    await submitWaitlistValue("true");

    // Reopen the Alpha event editor.
    await openAlphaEventEditor();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("true");

    // Submit and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/waitlist`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="waitlist"]').click(),
    ]);

    // Find the waitlist content.
    const waitlistContent = organizerGroupPage.locator("#waitlist-content");
    await expect(
      waitlistContent.locator("p.text-sm.lg\\:text-md.text-stone-700:visible").filter({
        hasText: "Waitlist entries for this event will appear here.",
      }),
    ).toBeVisible();

    // Disable the waitlist setting.
    await submitWaitlistValue("false");

    // Reopen the Alpha event editor.
    await openAlphaEventEditor();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("false");
  });

  test("organizer can see a waitlist entry on the waitlist tab", async ({ organizerGroupPage }) => {
    // Give the seeded waitlist dashboard filter flow room on slower runs.
    test.setTimeout(60_000);

    // Use the wide table layout because the Position filter is 2xl-only.
    await organizerGroupPage.setViewportSize({ width: 1600, height: 900 });

    // Return to the group events dashboard.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Find the event row.
    const eventRow = organizerGroupPage.locator("tr", {
      hasText: DASHBOARD_WAITLIST_EVENT_NAME,
    });
    await expect(eventRow).toBeVisible();

    // Submit and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/update`) &&
          response.ok(),
      ),
      eventRow.locator(`td button[aria-label="Edit event: ${DASHBOARD_WAITLIST_EVENT_NAME}"]`).click(),
    ]);

    // Submit and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="waitlist"]').click(),
    ]);

    // Find the waitlist content.
    const waitlistContent = organizerGroupPage.locator("#waitlist-content");
    const waitlistRow = waitlistContent.locator("tr", {
      hasText: "E2E Member Two",
    });

    // Assert that Waitlist entries is visible.
    await expect(waitlistContent.getByRole("table", { name: "Waitlist entries" })).toBeVisible();
    await expect(waitlistRow).toBeVisible();
    await expect(waitlistRow).toContainText("e2e-member-2");
    await expect(waitlistRow.locator("td").nth(2)).toContainText("Queue #1");
    const unavailableWaitlistAction = waitlistRow.getByRole("button", {
      name: "Waitlist actions unavailable for E2E Member Two",
    });
    await expect(unavailableWaitlistAction).toBeDisabled();
    await expect(unavailableWaitlistAction).toHaveAttribute(
      "title",
      "No active waiting list offer to cancel.",
    );
    const inactiveOfferRow = waitlistContent.locator("tr", {
      hasText: "E2E Admin One",
    });
    const inactiveOfferAction = inactiveOfferRow.getByRole("button", {
      name: "Waitlist actions unavailable for E2E Admin One",
    });
    await expect(inactiveOfferRow).toBeVisible();
    await expect(inactiveOfferAction).toBeDisabled();
    await expect(inactiveOfferAction).toHaveAttribute(
      "title",
      "This waiting list offer is no longer active.",
    );
    await expectUserProfileModalFromRow(
      organizerGroupPage,
      waitlistRow,
      "View profile for E2E Member Two",
      "E2E Member Two",
      [
        "Member Experience Engineer at Platform Ops Lab",
        "Member Two profile for dashboard modal coverage.",
        "openprofile.dev",
      ],
    );

    // Target the search controls used to submit waitlist filters.
    const searchInput = waitlistContent.getByRole("textbox", {
      name: "Search waitlist",
    });
    const searchForm = waitlistContent.locator("#waitlist-search-form");

    // Enter a query expected to match the visible waitlist entry.
    await searchInput.fill("Two");

    // Submit the matching search and wait for filtered results.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`) &&
          response.url().includes("ts_query=Two") &&
          response.ok(),
      ),
      searchForm.evaluate((form) => {
        if (form instanceof HTMLFormElement) {
          form.requestSubmit();
        }
      }),
    ]);

    // Verify the matching result is shown with a queue position.
    await expect(waitlistRow).toBeVisible();
    await expect(waitlistRow).toContainText("e2e-member-2");
    await expect(waitlistRow.locator("td").nth(2)).toContainText("Queue #1");
    await expect(searchInput).toHaveValue("Two");

    // Enter a query expected to return no waitlist entries.
    await searchInput.fill("");
    await searchInput.fill("zzzzzzzzzzzz");

    // Submit the empty-result search and wait for the empty state.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`) &&
          response.url().includes("ts_query=zzzzzzzzzzzz") &&
          response.ok(),
      ),
      searchForm.evaluate((form) => {
        if (form instanceof HTMLFormElement) {
          form.requestSubmit();
        }
      }),
    ]);

    const noResultsMessage = waitlistContent.locator("div.text-xl.lg\\:text-2xl.mb-4:visible").filter({
      hasText: "No waitlist entries found matching your search.",
    });

    // Verify the filtered empty result message is shown.
    await expect(noResultsMessage.first()).toBeVisible();

    // Clear the waitlist search filter.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`) &&
          !response.url().includes("ts_query") &&
          response.ok(),
      ),
      waitlistContent.getByRole("button", { name: "Clear waitlist search" }).click(),
    ]);

    // Verify clearing removes the empty state and restores the waitlist entry.
    await expect(noResultsMessage).toHaveCount(0);
    await expect(waitlistRow).toBeVisible();
    await expect(waitlistRow).toContainText("e2e-member-2");
    await expect(searchInput).toHaveValue("");

    // Sort the waitlist by entry name and keep the row visible.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`) &&
          response.url().includes("sort=name-desc") &&
          response.ok(),
      ),
      waitlistContent.getByLabel("Sort by").selectOption("name-desc"),
    ]);

    // Verify the sorted waitlist row remains visible.
    await expect(waitlistRow).toBeVisible();

    // Apply the title-present table filter while preserving the sort.
    await waitlistContent.getByLabel("Position filters").click();
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`) &&
          response.url().includes("sort=name-desc") &&
          response.url().includes("title=present") &&
          response.ok(),
      ),
      waitlistContent.locator('#waitlist-position-filter button[name="title"][value="present"]').click(),
    ]);

    const activeFilters = waitlistContent.getByText("Active filters", { exact: true }).locator("xpath=..");

    // Verify active filter badges remain visible with the filtered row.
    await expect(activeFilters.getByText("Present", { exact: true })).toBeVisible();
    await expect(activeFilters.getByRole("button", { name: "Remove title filter" })).toBeVisible();
    await expect(waitlistRow).toBeVisible();
  });

  test("organizer sees event-state reasons for unavailable waitlist actions", async ({
    organizerGroupPage,
  }) => {
    // Verify canceled events explain why their offer history is read-only.
    const canceledWaitlistContent = await openWaitlistTab(
      organizerGroupPage,
      TEST_INVITATION_CANCELLATION.name,
      TEST_INVITATION_CANCELLATION.id,
    );
    const canceledOfferAction = canceledWaitlistContent.getByRole("button", {
      name: "Waitlist actions unavailable for E2E Member One",
    });
    await expect(canceledOfferAction).toBeDisabled();
    await expect(canceledOfferAction).toHaveAttribute(
      "title",
      "Canceled events have no available waiting list actions.",
    );

    // Verify past events explain why their offer history is read-only.
    const pastWaitlistContent = await openWaitlistTab(
      organizerGroupPage,
      PAST_WAITLIST_EVENT_NAME,
      TEST_EVENT_IDS.alpha.pastFiltering,
      { past: true },
    );
    const pastOfferAction = pastWaitlistContent.getByRole("button", {
      name: "Waitlist actions unavailable for E2E Admin Two",
    });
    await expect(pastOfferAction).toBeDisabled();
    await expect(pastOfferAction).toHaveAttribute(
      "title",
      "Past events have no available waiting list actions.",
    );
  });

  test("viewer sees why waitlist actions are unavailable", async ({ groupViewerPage }) => {
    // Load the group events dashboard as a read-only viewer.
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=events");

    // Open the seeded event used for waitlist action checks.
    const eventRow = groupViewerPage.locator("tr", {
      hasText: DASHBOARD_WAITLIST_EVENT_NAME,
    });
    await expect(eventRow).toBeVisible();
    await Promise.all([
      groupViewerPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/update`) &&
          response.ok(),
      ),
      eventRow.locator(`td button[aria-label="Edit event: ${DASHBOARD_WAITLIST_EVENT_NAME}"]`).click(),
    ]);

    // Load the waitlist tab and target its seeded entry.
    await Promise.all([
      groupViewerPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`) &&
          response.ok(),
      ),
      groupViewerPage.locator('button[data-section="waitlist"]').click(),
    ]);
    const waitlistRow = groupViewerPage.locator("#waitlist-content tr", {
      hasText: "E2E Member Two",
    });
    const unavailableWaitlistAction = waitlistRow.getByRole("button", {
      name: "Waitlist actions unavailable for E2E Member Two",
    });

    // Verify the disabled action explains the viewer's permission limit.
    await expect(waitlistRow).toBeVisible();
    await expect(unavailableWaitlistAction).toBeDisabled();
    await expect(unavailableWaitlistAction).toHaveAttribute(
      "title",
      "Your role cannot manage waiting list offers.",
    );
  });
});
