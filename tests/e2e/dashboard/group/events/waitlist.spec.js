import { expect, test } from "../../../fixtures.js";

import { TEST_EVENT_IDS, navigateToPath } from "../../../utils.js";
import { expectUserProfileModalFromRow } from "./user-profile-modal-helpers.js";

const DASHBOARD_WAITLIST_EVENT_NAME = "Dashboard Waitlist Table Lab";

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
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`,
            ) &&
          response.ok(),
      ),
      eventRow
        .locator('td button[aria-label="Edit event: Upcoming In-Person Event"]')
        .click(),
    ]);

    // Submit and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/waitlist`,
            ) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="waitlist"]').click(),
    ]);

    // Find the waitlist content.
    const waitlistContent = organizerGroupPage.locator("#waitlist-content");
    await expect(
      waitlistContent
        .locator("p.text-sm.lg\\:text-md.text-stone-700:visible")
        .filter({
          hasText:
            "Enable waitlist to allow full events to add people to the queue.",
        }),
    ).toBeVisible();
  });

  test("organizer can enable waitlist for an event and then restore it", async ({
    organizerGroupPage,
  }) => {
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
            response
              .url()
              .includes(
                `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`,
              ) &&
            response.ok(),
        ),
        eventRow
          .locator(
            'td button[aria-label="Edit event: Upcoming In-Person Event"]',
          )
          .click(),
      ]);
    };

    // Submit the next waitlist value and verify it persisted.
    const submitWaitlistValue = async (nextValue) => {
      await organizerGroupPage
        .locator('button[data-section="details"]')
        .click();

      // Find the waitlist toggle.
      const waitlistToggle = organizerGroupPage.locator(
        "#toggle_waitlist_enabled",
      );
      const waitlistToggleLabel = organizerGroupPage.locator(
        '[data-enrollment-toggle-label="waitlist"]',
      );

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
      await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue(
        nextValue,
      );

      // Submit and wait for the server response.
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response
              .url()
              .includes(
                `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`,
              ) &&
            response.ok(),
        ),
        organizerGroupPage.locator("#update-event-button").click(),
      ]);
    };

    // Reopen the Alpha event editor.
    await openAlphaEventEditor();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue(
      "false",
    );

    // Enable the waitlist setting.
    await submitWaitlistValue("true");

    // Reopen the Alpha event editor.
    await openAlphaEventEditor();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue(
      "true",
    );

    // Submit and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/waitlist`,
            ) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="waitlist"]').click(),
    ]);

    // Find the waitlist content.
    const waitlistContent = organizerGroupPage.locator("#waitlist-content");
    await expect(
      waitlistContent
        .locator("p.text-sm.lg\\:text-md.text-stone-700:visible")
        .filter({
          hasText: "Waitlist entries for this event will appear here.",
        }),
    ).toBeVisible();

    // Disable the waitlist setting.
    await submitWaitlistValue("false");

    // Reopen the Alpha event editor.
    await openAlphaEventEditor();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue(
      "false",
    );
  });

  test("organizer can see a waitlist entry on the waitlist tab", async ({
    organizerGroupPage,
  }) => {
    // Give the seeded waitlist dashboard filter flow room on slower runs.
    test.setTimeout(60_000);

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
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/update`,
            ) &&
          response.ok(),
      ),
      eventRow
        .locator(
          `td button[aria-label="Edit event: ${DASHBOARD_WAITLIST_EVENT_NAME}"]`,
        )
        .click(),
    ]);

    // Submit and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`,
            ) &&
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
    await expect(
      waitlistContent.getByRole("table", { name: "Waitlist entries" }),
    ).toBeVisible();
    await expect(waitlistRow).toBeVisible();
    await expect(waitlistRow).toContainText("e2e-member-2");
    await expect(waitlistRow.locator("td").nth(2)).toHaveText(/[1-9]\d*/);
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
    await searchForm.evaluate((form) => {
      if (form instanceof HTMLFormElement) {
        form.requestSubmit();
      }
    });

    // Verify the matching result is shown with a queue position.
    await expect(waitlistRow).toBeVisible();
    await expect(waitlistRow).toContainText("e2e-member-2");
    await expect(waitlistRow.locator("td").nth(2)).toHaveText(/[1-9]\d*/);
    await expect(searchInput).toHaveValue("Two");

    // Enter a query expected to return no waitlist entries.
    await searchInput.fill("");
    await searchInput.fill("zzzzzzzzzzzz");

    // Submit the empty-result search and wait for the empty state.
    await searchForm.evaluate((form) => {
      if (form instanceof HTMLFormElement) {
        form.requestSubmit();
      }
    });

    const noResultsMessage = waitlistContent
      .locator("div.text-xl.lg\\:text-2xl.mb-4:visible")
      .filter({
        hasText: "No waitlist entries found matching your search.",
      });

    // Verify the filtered empty result message is shown.
    await expect(noResultsMessage.first()).toBeVisible();

    // Clear the waitlist search filter.
    await waitlistContent
      .getByRole("button", { name: "Clear waitlist search" })
      .click();

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
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`,
            ) &&
          response.url().includes("sort=name-asc") &&
          response.ok(),
      ),
      waitlistContent
        .getByRole("button", { name: "Sort Entry ascending" })
        .click(),
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
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`,
            ) &&
          response.url().includes("sort=name-asc") &&
          response.url().includes("title=present") &&
          response.ok(),
      ),
      waitlistContent
        .locator('#waitlist-position-filter button[name="title"][value="present"]')
        .click(),
    ]);

    // Verify active filter badges remain visible with the filtered row.
    await expect(waitlistContent.getByText("Present")).toBeVisible();
    await expect(waitlistRow).toBeVisible();
  });
});
