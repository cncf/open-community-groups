import { expect, test } from "../../fixtures";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_GROUP_SLUGS,
  navigateToEvent,
  navigateToPath,
} from "../../utils";

test.describe("group dashboard waitlist views", () => {
  test("organizer can open the waitlist tab for an event with waitlist disabled", async ({
    organizerGroupPage,
  }) => {
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Upcoming In-Person Event",
    });
    await expect(eventRow).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`) &&
          response.ok(),
      ),
      eventRow
        .locator('td button[aria-label="Edit event: Upcoming In-Person Event"]')
        .click(),
    ]);

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/waitlist`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="waitlist"]').click(),
    ]);

    const waitlistContent = organizerGroupPage.locator("#waitlist-content");
    await expect(
      waitlistContent
        .locator('p.text-sm.lg\\:text-md.text-stone-700:visible')
        .filter({
          hasText: "Enable waitlist to allow full events to add people to the queue.",
        }),
    ).toBeVisible();
  });

  test("organizer can enable waitlist for an event and then restore it", async ({
    organizerGroupPage,
  }) => {
    const openAlphaEventEditor = async () => {
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

      const eventRow = organizerGroupPage.locator("tr", {
        hasText: "Upcoming In-Person Event",
      });
      await expect(eventRow).toBeVisible();

      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`) &&
            response.ok(),
        ),
        eventRow
          .locator('td button[aria-label="Edit event: Upcoming In-Person Event"]')
          .click(),
      ]);
    };

    const submitWaitlistValue = async (nextValue: "true" | "false") => {
      await organizerGroupPage.locator('button[data-section="details"]').click();

      const waitlistToggle = organizerGroupPage.locator("#toggle_waitlist_enabled");
      const waitlistToggleLabel = organizerGroupPage.locator("#waitlist-toggle-label");

      await expect(waitlistToggleLabel).toBeVisible();
      await expect(waitlistToggle).toBeEnabled();

      if ((await waitlistToggle.isChecked()) !== (nextValue === "true")) {
        await waitlistToggleLabel.click();
      }

      await expect(waitlistToggle).toBeChecked({ checked: nextValue === "true" });
      await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue(nextValue);

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

    await openAlphaEventEditor();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("false");

    await submitWaitlistValue("true");

    await openAlphaEventEditor();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("true");

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/waitlist`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="waitlist"]').click(),
    ]);

    const waitlistContent = organizerGroupPage.locator("#waitlist-content");
    await expect(
      waitlistContent
        .locator('p.text-sm.lg\\:text-md.text-stone-700:visible')
        .filter({ hasText: "Waitlist entries for this event will appear here." }),
    ).toBeVisible();

    await submitWaitlistValue("false");

    await openAlphaEventEditor();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("false");
  });

  test("organizer can see a public waitlist entry in the event dashboard", async ({
    member2Page,
    organizerGroupPage,
  }) => {
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      "alpha-waitlist-lab",
    );

    const attendButton = member2Page.locator('[data-attendance-role="attend-btn"]');
    const leaveButton = member2Page.locator('[data-attendance-role="leave-btn"]');

    await expect(attendButton).toContainText("Join waiting list");

    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.waitlistLab}/attend`) &&
          response.ok(),
      ),
      attendButton.click(),
    ]);

    await expect(leaveButton).toContainText("Leave waiting list");

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Full Event With Waitlist",
    });
    await expect(eventRow).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/update`) &&
          response.ok(),
      ),
      eventRow
        .locator('td button[aria-label="Edit event: Full Event With Waitlist"]')
        .click(),
    ]);

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/waitlist`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="waitlist"]').click(),
    ]);

    const waitlistContent = organizerGroupPage.locator("#waitlist-content");
    const waitlistRow = waitlistContent.locator("tr", {
      hasText: "E2E Member Two",
    });

    await expect(waitlistContent.getByRole("table", { name: "Waitlist entries" })).toBeVisible();
    await expect(waitlistRow).toBeVisible();
    await expect(waitlistRow).toContainText("e2e-member-2");
    await expect(waitlistRow).toContainText("1");

    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      "alpha-waitlist-lab",
    );

    await leaveButton.click();
    await expect(member2Page.getByRole("button", { name: "Yes" })).toBeVisible();

    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.waitlistLab}/leave`) &&
          response.ok(),
      ),
      member2Page.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(attendButton).toContainText("Join waiting list");
  });
});
