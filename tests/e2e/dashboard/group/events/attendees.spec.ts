import { readFile } from "node:fs/promises";
import type { Page } from "@playwright/test";

import { expect, test } from "../../../fixtures";

import {
  buildE2eUrl,
  E2E_PAYMENTS_ENABLED,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  TEST_USER_IDS,
  navigateToEvent,
  navigateToPath,
} from "../../../utils";

import {
  ATTENDEE_NOTIFICATION_BODY,
  ATTENDEE_NOTIFICATION_SUBJECT,
} from "../helpers";

const openAttendeesTab = async (page: Page, eventName: string, eventId: string) => {
  await navigateToPath(page, "/dashboard/group?tab=events");

  const eventRow = page.locator("tr", {
    hasText: eventName,
  });
  await expect(eventRow).toBeVisible();

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "GET" &&
        response.url().includes(`/dashboard/group/events/${eventId}/update`) &&
        response.ok(),
    ),
    eventRow.locator('td button[aria-label^="Edit event:"]').click(),
  ]);

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "GET" &&
        response.url().includes(`/dashboard/group/events/${eventId}/attendees`) &&
        response.ok(),
    ),
    page.locator('button[data-section="attendees"]').click(),
  ]);

  return page.locator("#attendees-content");
};

test.describe("group dashboard attendees tab", () => {
  test("viewer sees read-only attendee controls on the attendees tab", async ({
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

  test("organizer can see a public attendee on the attendees tab", async ({
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

  test("organizer can check in an attendee from the attendees tab", async ({
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

  test("organizer sees the empty state on the attendees tab for an event without RSVPs", async ({
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

  test("organizer can download attendees as CSV from the attendees tab", async ({
    organizerGroupPage,
  }) => {
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Full Event With Waitlist",
      TEST_EVENT_IDS.alpha.waitlistLab,
    );

    const actionsButton = attendeesContent.getByRole("button", {
      name: "Open attendee actions menu",
    });
    await expect(actionsButton).toBeVisible();
    await actionsButton.click();

    const downloadCsvLink = attendeesContent.getByRole("menuitem", {
      name: "Download CSV",
    });
    await expect(downloadCsvLink).toBeVisible();
    await expect(downloadCsvLink).toHaveAttribute(
      "href",
      `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees.csv`,
    );

    const [download] = await Promise.all([
      organizerGroupPage.waitForEvent("download"),
      downloadCsvLink.click(),
    ]);
    const downloadPath = await download.path();

    if (!downloadPath) {
      throw new Error("Expected attendee CSV download to have a local file path.");
    }

    expect(download.suggestedFilename()).toBe(
      "event-alpha-waitlist-lab-attendees.csv",
    );
    const csvContents = await readFile(downloadPath, "utf8");
    expect(csvContents).toContain(
      "Name,Company,Title\nE2E Organizer One,,\n",
    );
  });

  test.describe("payment-enabled attendee refund flows", () => {
    test.skip(!E2E_PAYMENTS_ENABLED, "Payments are disabled in this environment.");

    test("organizer can review a pending refund request from the attendees tab", async ({
      organizerGroupPage,
    }) => {
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Member One",
      });

      await attendeeRow.locator("[data-refund-review-trigger]").click();

      const refundModal = organizerGroupPage.locator("#attendee-refund-modal");
      await expect(refundModal).toBeVisible();
      await expect(refundModal.locator("#attendee-refund-ticket")).toHaveText("VIP pass");
      await expect(refundModal.locator("#attendee-refund-amount")).toHaveText("USD 40.00");
      await expect(refundModal.locator("#attendee-refund-name")).toHaveText("E2E Member One");
      await expect(refundModal.locator("#attendee-refund-approve")).toContainText(
        "Approve refund",
      );
      await expect(refundModal.locator("#attendee-refund-reject")).toContainText(
        "Reject refund",
      );
    });

    test("organizer sees retry refund finalization for processing refunds", async ({
      organizerGroupPage,
    }) => {
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Member Two",
      });

      await attendeeRow.locator("[data-refund-review-trigger]").click();

      const refundModal = organizerGroupPage.locator("#attendee-refund-modal");
      await expect(refundModal).toBeVisible();
      await expect(refundModal.locator("#attendee-refund-ticket")).toHaveText("VIP pass");
      await expect(refundModal.locator("#attendee-refund-amount")).toHaveText("USD 50.00");
      await expect(refundModal.locator("#attendee-refund-name")).toHaveText("E2E Member Two");
      await expect(refundModal.locator("#attendee-refund-approve")).toContainText(
        "Retry refund finalization",
      );
      await expect(refundModal.locator("#attendee-refund-reject")).toBeHidden();
    });

    test("viewer cannot review or approve attendee refunds", async ({
      groupViewerPage,
    }) => {
      const attendeesContent = await openAttendeesTab(
        groupViewerPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );

      await expect(attendeesContent.locator("[data-refund-review-trigger]")).toHaveCount(0);
      await expect(groupViewerPage.locator("#attendee-refund-modal")).toBeHidden();
    });
  });

  test("organizer can open and close the attendee email modal from the attendees tab", async ({
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
    await expect(modal.locator("#attendee-subject")).toHaveValue(
      "Platform Ops Meetup: Full Event With Waitlist",
    );
    await expect(modal.locator("#attendee-body")).toHaveValue("");

    await modal.getByRole("button", { name: "Cancel" }).click();
    await expect(modal).toBeHidden();
  });

  test("organizer can send an attendee email from the attendees tab", async ({
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

    await modal.locator("#attendee-subject").fill(ATTENDEE_NOTIFICATION_SUBJECT);
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

  test("organizer can open the event QR code modal from the attendees tab", async ({
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
