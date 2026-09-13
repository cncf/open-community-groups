import { expect, test } from "../../../fixtures.js";

import {
  deleteNotifications,
  expectNewNotifications,
  snapshotNotifications,
} from "../../../notifications.js";
import { TEST_EVENT_IDS, TEST_USER_IDS } from "../../../seed.js";
import { navigateToPath, waitForActionResponse } from "../../../utils.js";

import { ATTENDEE_NOTIFICATION_BODY, ATTENDEE_NOTIFICATION_SUBJECT } from "../helpers.js";
import { openAttendeesTab } from "./attendees-helpers.js";

test.describe("group dashboard attendees tab — notifications", () => {
  test("organizer can open and close the attendee email modal from the attendees tab", async ({
    organizerGroupPage,
  }) => {
    // Load the group events dashboard before opening the seeded event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Find the event row.
    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Full Event With Waitlist",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
    await waitForActionResponse(
      organizerGroupPage,
      () => eventRow.locator('td button[aria-label="Edit event: Full Event With Waitlist"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/update`,
      },
    );

    // Load the attendees tab for the event.
    await waitForActionResponse(
      organizerGroupPage,
      () => organizerGroupPage.locator('button[data-section="attendees"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees`,
      },
    );

    // Open the attendee email modal.
    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const openModalButton = attendeesContent.getByRole("button", {
      name: "Send email",
    });

    // Assert that the answers modal can open.
    await expect(openModalButton).toBeEnabled();
    await openModalButton.click();
    await attendeesContent.getByRole("menuitem", { name: "All eligible attendees" }).click();

    // Verify the modal opens with the default message fields.
    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();
    await expect(modal.getByRole("heading", { name: "Send email" })).toBeVisible();
    await expect(modal.getByText("This email will be sent to 1 eligible attendee.")).toBeVisible();
    await expect(modal.locator("#attendee-subject")).toHaveValue(
      "Platform Ops Meetup: Full Event With Waitlist",
    );
    await expect(modal.locator("#attendee-body")).toHaveValue("");

    // Close the attendee email modal without sending.
    await modal.getByRole("button", { name: "Cancel" }).click();
    await expect(modal).toBeHidden();
  });

  test("organizer can send an attendee email from the attendees tab", async ({ organizerGroupPage }) => {
    // Load the group events dashboard before opening the seeded event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Find the event row.
    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Full Event With Waitlist",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
    await waitForActionResponse(
      organizerGroupPage,
      () => eventRow.locator('td button[aria-label="Edit event: Full Event With Waitlist"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/update`,
      },
    );

    // Load the attendees tab for the event.
    await waitForActionResponse(
      organizerGroupPage,
      () => organizerGroupPage.locator('button[data-section="attendees"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees`,
      },
    );

    // Open the attendee email modal.
    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const openModalButton = attendeesContent.getByRole("button", {
      name: "Send email",
    });

    // Assert that the answers modal can open.
    await expect(openModalButton).toBeEnabled();
    await openModalButton.click();
    await attendeesContent.getByRole("menuitem", { name: "All eligible attendees" }).click();

    // Find the modal.
    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();

    // Fill and submit the attendee email.
    await modal.locator("#attendee-subject").fill(ATTENDEE_NOTIFICATION_SUBJECT);
    await modal.locator("#attendee-body").fill(ATTENDEE_NOTIFICATION_BODY);

    // Click Send email.
    await waitForActionResponse(
      organizerGroupPage,
      () => modal.getByRole("button", { name: "Send email" }).click(),
      {
        method: "POST",
        urlIncludes: `/dashboard/group/notifications/${TEST_EVENT_IDS.alpha.waitlistLab}`,
      },
    );

    // Verify the email modal closes after a successful send.
    await expect(modal).toBeHidden();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Email sent successfully to all event attendees!",
    );
    await organizerGroupPage.getByRole("button", { name: "OK" }).click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toBeHidden();
  });

  test("organizer can choose attendees for attendee email", async ({ organizerGroupPage }) => {
    // Load the attendees tab for the seeded waitlist event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Full Event With Waitlist",
      TEST_EVENT_IDS.alpha.waitlistLab,
    );

    // Open attendee email actions and enter selection mode.
    const openEmailActionsButton = attendeesContent.getByRole("button", {
      name: "Send email",
    });
    await expect(openEmailActionsButton).toBeEnabled();
    await openEmailActionsButton.click();
    await attendeesContent.getByRole("menuitem", { name: "Choose attendees" }).click();

    // Find the attendee email selection controls.
    const selectionBar = attendeesContent.locator("[data-attendee-email-selection-bar]");
    const selectionCheckboxes = attendeesContent.locator("[data-attendee-email-selection-checkbox]");
    const selectionSendButton = selectionBar.getByRole("button", {
      name: "Continue",
    });

    // Verify selection mode starts empty and cannot send without a selection.
    await expect(selectionBar).toBeVisible();
    await expect(selectionBar).toContainText("0 attendees selected");
    await expect(openEmailActionsButton).toBeDisabled();
    await expect(selectionSendButton).toBeDisabled();
    await expect(selectionCheckboxes).toHaveCount(1);
    await expect(selectionCheckboxes).toBeVisible();

    // Select the eligible attendee and open the email modal.
    await selectionCheckboxes.check();
    await expect(selectionBar).toContainText("1 attendee selected");
    await expect(selectionSendButton).toBeEnabled();

    // Open the selected-recipient email modal.
    await selectionSendButton.click();

    // Verify the email modal is configured for selected recipients.
    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();
    await expect(modal.getByText("This email will be sent to 1 selected attendee.")).toBeVisible();
    await expect(modal.locator("#attendee-notification-recipient-scope")).toHaveValue("selected");
    await expect(modal.locator("#attendee-notification-selected-fields input")).toHaveCount(1);

    // Close the modal and exit selection mode.
    await modal.getByRole("button", { name: "Cancel" }).click();
    await expect(modal).toBeHidden();
    await selectionBar.getByRole("button", { name: "Cancel" }).click();
    await expect(selectionBar).toBeHidden();
    await expect(openEmailActionsButton).toBeEnabled();
  });

  test("organizer can send an attendee email to selected attendees", async ({ organizerGroupPage }) => {
    let notificationIds = [];

    // Load the attendees tab for the seeded waitlist event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Full Event With Waitlist",
      TEST_EVENT_IDS.alpha.waitlistLab,
    );

    // Open attendee email actions and enter selection mode.
    await attendeesContent.getByRole("button", { name: "Send email" }).click();
    await attendeesContent.getByRole("menuitem", { name: "Choose attendees" }).click();

    // Find the attendee email selection controls.
    const selectionBar = attendeesContent.locator("[data-attendee-email-selection-bar]");
    const selectionCheckboxes = attendeesContent.locator("[data-attendee-email-selection-checkbox]");

    // Select the eligible attendee and open the email modal.
    await expect(selectionCheckboxes).toHaveCount(1);
    await selectionCheckboxes.check();
    await selectionBar.getByRole("button", { name: "Continue" }).click();

    // Verify the email modal is configured for selected recipients.
    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();
    await expect(modal.getByText("This email will be sent to 1 selected attendee.")).toBeVisible();
    await expect(modal.locator("#attendee-notification-recipient-scope")).toHaveValue("selected");

    // Fill and submit the selected attendee email.
    await modal.locator("#attendee-subject").fill(ATTENDEE_NOTIFICATION_SUBJECT);
    await modal.locator("#attendee-body").fill(ATTENDEE_NOTIFICATION_BODY);

    try {
      // Send the email and capture the generated attendee notification.
      const snapshot = snapshotNotifications();
      const notificationResponse = await waitForActionResponse(
        organizerGroupPage,
        () => modal.getByRole("button", { name: "Send email" }).click(),
        {
          method: "POST",
          urlIncludes: `/dashboard/group/notifications/${TEST_EVENT_IDS.alpha.waitlistLab}`,
        },
      );
      notificationIds = expectNewNotifications(snapshot, [
        {
          kind: "event-custom",
          templateDataContains: {
            body: ATTENDEE_NOTIFICATION_BODY,
            event: { event_id: TEST_EVENT_IDS.alpha.waitlistLab },
            subject: ATTENDEE_NOTIFICATION_SUBJECT,
          },
          userIds: [TEST_USER_IDS.organizer1],
        },
      ]);

      // Verify the selected-recipient parameters were submitted.
      expect(notificationResponse.request().postData()).toContain("recipient_scope=selected");
      expect(notificationResponse.request().postData()).toContain("recipient_user_ids%5B0%5D=");

      // Verify the selected email send closes the modal and clears selection mode.
      await expect(modal).toBeHidden();
      await expect(selectionBar).toBeHidden();
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Email sent successfully to selected attendees!",
      );
      await organizerGroupPage.getByRole("button", { name: "OK" }).click();
      await expect(organizerGroupPage.locator(".swal2-popup")).toBeHidden();
    } finally {
      // Delete generated attendee notifications.
      deleteNotifications(notificationIds);
    }
  });

  test("organizer can open attendee email from an attendee row", async ({ organizerGroupPage }) => {
    // Load the attendees tab for the seeded waitlist event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Full Event With Waitlist",
      TEST_EVENT_IDS.alpha.waitlistLab,
    );

    // Find the eligible attendee row.
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Organizer One",
    });
    await expect(attendeeRow).toBeVisible();

    // Open the attendee row actions and choose the row-level email action.
    const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");
    await rowActionsMenu.locator("summary").click();
    await rowActionsMenu.getByRole("menuitem", { name: "Send email" }).click();

    // Verify the email modal is configured for the selected attendee.
    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();
    await expect(modal.getByText("This email will be sent to 1 selected attendee.")).toBeVisible();
    await expect(modal.locator("#attendee-notification-recipient-scope")).toHaveValue("selected");
    await expect(modal.locator("#attendee-notification-selected-fields input")).toHaveCount(1);

    // Close the attendee email modal without sending.
    await modal.getByRole("button", { name: "Cancel" }).click();
    await expect(modal).toBeHidden();
  });
});
