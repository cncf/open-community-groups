import { expect, test } from "../../../fixtures.js";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_GROUP_SLUGS,
  navigateToEvent,
  navigateToPath,
} from "../../../utils.js";

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
        "#waitlist-toggle-label",
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

  test("organizer can see a public waitlist entry on the waitlist tab", async ({
    member2Page,
    organizerGroupPage,
  }) => {
    // Load the public waitlist event before creating a waitlist entry.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      "alpha-waitlist-lab",
    );

    // Find the attend button.
    const attendButton = member2Page.locator(
      '[data-attendance-role="attend-btn"]',
    );
    const leaveButton = member2Page.locator(
      '[data-attendance-role="leave-btn"]',
    );

    // Verify organizer can see a public waitlist entry on the waitlist tab.
    await expect(attendButton).toContainText("Join waiting list");

    // Click the attend button.
    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes(`/event/${TEST_EVENT_IDS.alpha.waitlistLab}/attend`) &&
          response.ok(),
      ),
      attendButton.click(),
    ]);

    // Assert the expected text is rendered.
    await expect(leaveButton).toContainText("Leave waiting list");

    // Return to the group events dashboard.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Find the event row.
    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Full Event With Waitlist",
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
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/update`,
            ) &&
          response.ok(),
      ),
      eventRow
        .locator('td button[aria-label="Edit event: Full Event With Waitlist"]')
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
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/waitlist`,
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
    await expect(waitlistRow).toContainText("1");

    // Open the public event page.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      "alpha-waitlist-lab",
    );

    // Click the leave button.
    await leaveButton.click();
    await expect(
      member2Page.getByRole("button", { name: "Yes" }),
    ).toBeVisible();

    // Click Yes.
    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response
            .url()
            .includes(`/event/${TEST_EVENT_IDS.alpha.waitlistLab}/leave`) &&
          response.ok(),
      ),
      member2Page.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Assert the expected text is rendered.
    await expect(attendButton).toContainText("Join waiting list");
  });
});
