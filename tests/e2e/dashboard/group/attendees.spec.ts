import { expect, test } from "../../fixtures";

import {
  buildE2eUrl,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  TEST_USER_IDS,
  navigateToEvent,
  navigateToPath,
} from "../../utils";

import {
  ATTENDEE_NOTIFICATION_BODY,
  ATTENDEE_NOTIFICATION_TITLE,
} from "./helpers";

test.describe("group dashboard attendees views", () => {
  test("viewer sees read-only attendee controls in the event dashboard", async ({
    groupViewerPage,
  }) => {
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=events");

    const eventRow = groupViewerPage.locator("tr", {
      hasText: "Full Event With Waitlist",
    });
    await expect(eventRow).toBeVisible();

    await Promise.all([
      groupViewerPage.waitForResponse(
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
      groupViewerPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees`) &&
          response.ok(),
      ),
      groupViewerPage.locator('button[data-section="attendees"]').click(),
    ]);

    const attendeesContent = groupViewerPage.locator("#attendees-content");
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Organizer One",
    });

    await expect(attendeesContent.getByRole("table", { name: "Attendees list" })).toBeVisible();
    await expect(attendeeRow).toBeVisible();
    await expect(
      attendeesContent.getByRole("button", { name: "Send email" }),
    ).toBeDisabled();
    await expect(
      attendeesContent.getByRole("button", { name: "Send email" }),
    ).toHaveAttribute("title", "Your role cannot send emails to attendees.");
    await expect(attendeeRow.locator(".check-in-toggle")).toBeDisabled();
  });

  test("organizer can see a public attendee in the event dashboard", async ({
    member2Page,
    organizerGroupPage,
  }) => {
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    const attendButton = member2Page.locator('[data-attendance-role="attend-btn"]');
    const leaveButton = member2Page.locator('[data-attendance-role="leave-btn"]');

    await expect(attendButton).toContainText("Attend event");

    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.one}/attend`) &&
          response.ok(),
      ),
      attendButton.click(),
    ]);

    await expect(leaveButton).toContainText("Cancel attendance");

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
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Member Two",
    });

    await expect(attendeesContent.getByRole("table", { name: "Attendees list" })).toBeVisible();
    await expect(attendeeRow).toBeVisible();
    await expect(attendeeRow).toContainText("e2e-member-2");
    await expect(
      attendeesContent.getByRole("button", { name: "Send email" }),
    ).toBeEnabled();

    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    await leaveButton.click();
    await expect(member2Page.getByRole("button", { name: "Yes" })).toBeVisible();

    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.one}/leave`) &&
          response.ok(),
      ),
      member2Page.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(attendButton).toContainText("Attend event");
  });

  test("organizer can check in an attendee from the event dashboard", async ({
    member2Page,
    organizerGroupPage,
  }) => {
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    const attendButton = member2Page.locator('[data-attendance-role="attend-btn"]');
    const leaveButton = member2Page.locator('[data-attendance-role="leave-btn"]');

    await expect(attendButton).toContainText("Attend event");

    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.one}/attend`) &&
          response.ok(),
      ),
      attendButton.click(),
    ]);

    await expect(leaveButton).toContainText("Cancel attendance");

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
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Member Two",
    });
    const checkInToggle = attendeeRow.locator(".check-in-toggle");

    await expect(attendeeRow).toBeVisible();
    await expect(checkInToggle).toBeEnabled();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees/${TEST_USER_IDS.member2}/check-in`,
            ) &&
          response.ok(),
      ),
      attendeeRow.locator("label").click(),
    ]);

    await expect(checkInToggle).toBeChecked();
    await expect(checkInToggle).toBeDisabled();

    await navigateToPath(
      member2Page,
      `/${TEST_COMMUNITY_NAME}/check-in/${TEST_EVENT_IDS.alpha.one}`,
    );
    await expect(member2Page.getByText("You're checked in")).toBeVisible();

    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    await leaveButton.click();
    await expect(member2Page.getByRole("button", { name: "Yes" })).toBeVisible();

    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.one}/leave`) &&
          response.ok(),
      ),
      member2Page.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(attendButton).toContainText("Attend event");
  });

  test("organizer sees the empty attendees state for an event without RSVPs", async ({
    organizerGroupPage,
  }) => {
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Upcoming Virtual Event",
    });
    await expect(eventRow).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.two}/update`) &&
          response.ok(),
      ),
      eventRow
        .locator('td button[aria-label="Edit event: Upcoming Virtual Event"]')
        .click(),
    ]);

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.two}/attendees`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    const attendeesContent = organizerGroupPage.locator("#attendees-content");

    await expect(attendeesContent.getByRole("table", { name: "Attendees list" })).toBeVisible();
    await expect(
      attendeesContent.locator('div.text-xl.lg\\:text-2xl:visible').filter({
        hasText: "No attendees found for this event.",
      }),
    ).toBeVisible();
    await expect(
      attendeesContent.getByRole("button", { name: "Send email" }),
    ).toBeDisabled();
    await expect(
      attendeesContent.getByRole("button", { name: "Send email" }),
    ).toHaveAttribute("title", "No attendees to send emails to.");
  });

  test("organizer can open and close the attendee email modal", async ({
    organizerGroupPage,
  }) => {
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
          response
            .url()
            .includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const openModalButton = attendeesContent.getByRole("button", {
      name: "Send email",
    });

    await expect(openModalButton).toBeEnabled();
    await openModalButton.click();

    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();
    await expect(modal.getByRole("heading", { name: "Send email" })).toBeVisible();
    await expect(
      modal.getByText("This email will be sent to all event attendees."),
    ).toBeVisible();
    await expect(modal.locator("#attendee-title")).toHaveValue("");
    await expect(modal.locator("#attendee-body")).toHaveValue("");

    await modal.getByRole("button", { name: "Cancel" }).click();
    await expect(modal).toBeHidden();
  });

  test("organizer can send an attendee email from the event dashboard", async ({
    organizerGroupPage,
  }) => {
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
          response
            .url()
            .includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const openModalButton = attendeesContent.getByRole("button", {
      name: "Send email",
    });

    await expect(openModalButton).toBeEnabled();
    await openModalButton.click();

    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();

    await modal.locator("#attendee-title").fill(ATTENDEE_NOTIFICATION_TITLE);
    await modal.locator("#attendee-body").fill(ATTENDEE_NOTIFICATION_BODY);

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes(`/dashboard/group/notifications/${TEST_EVENT_IDS.alpha.waitlistLab}`) &&
          response.ok(),
      ),
      modal.getByRole("button", { name: "Send email" }).click(),
    ]);

    await expect(modal).toBeHidden();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Email sent successfully to all event attendees!",
    );
  });

  test("organizer can open the event QR code modal with populated details", async ({
    organizerGroupPage,
  }) => {
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
          response
            .url()
            .includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const openModalButton = attendeesContent.locator("#open-event-qr-code-modal");

    await expect(openModalButton).toBeVisible();
    await openModalButton.click();

    const modal = organizerGroupPage.locator("#event-qr-code-modal");
    await expect(modal).toBeVisible();
    await expect(
      modal.getByRole("heading", { name: "Event check-in QR code" }),
    ).toBeVisible();
    await expect(modal.locator("#event-qr-code-group-name")).toHaveText(
      "Platform Ops Meetup",
    );
    await expect(modal.locator("#event-qr-code-name")).toHaveText("Full Event With Waitlist");
    await expect(modal.locator("#event-qr-code-start")).not.toHaveText("");
    await expect(modal.locator("#event-qr-code-link")).toHaveAttribute(
      "href",
      buildE2eUrl(`/${TEST_COMMUNITY_NAME}/check-in/${TEST_EVENT_IDS.alpha.waitlistLab}`),
    );
    await expect(modal.locator("#event-qr-code-image")).toHaveAttribute(
      "src",
      `/dashboard/group/check-in/${TEST_EVENT_IDS.alpha.waitlistLab}/qr-code`,
    );
    await expect(modal.locator("#print-event-qr-code")).toBeEnabled();

    await modal.locator("#close-event-qr-code-modal").click();
    await expect(modal).toBeHidden();
  });
});
