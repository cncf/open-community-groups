import { readFile } from "node:fs/promises";

import { expect, test } from "../../../fixtures.js";

import {
  buildE2eUrl,
  E2E_PAYMENTS_ENABLED,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_REGISTRATION_QUESTIONS_EVENT,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  TEST_USER_IDS,
  navigateToEvent,
  navigateToPath,
} from "../../../utils.js";

import {
  ATTENDEE_NOTIFICATION_BODY,
  ATTENDEE_NOTIFICATION_SUBJECT,
} from "../helpers.js";

// Open the attendees tab for a specific event and return its content.
const openAttendeesTab = async (page, eventName, eventId) => {
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
        response
          .url()
          .includes(`/dashboard/group/events/${eventId}/attendees`) &&
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
    // Load the group events dashboard as a read-only viewer.
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=events");

    // Target the seeded event used for attendee permission checks.
    const eventRow = groupViewerPage.locator("tr", {
      hasText: "Full Event With Waitlist",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
    await Promise.all([
      groupViewerPage.waitForResponse(
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

    // Load the attendees tab for the seeded event.
    await Promise.all([
      groupViewerPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees`,
            ) &&
          response.ok(),
      ),
      groupViewerPage.locator('button[data-section="attendees"]').click(),
    ]);

    // Target the attendee row and verify controls remain read-only.
    const attendeesContent = groupViewerPage.locator("#attendees-content");
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Organizer One",
    });

    await expect(
      attendeesContent.getByRole("table", { name: "Attendees list" }),
    ).toBeVisible();
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
    // Load the public event page before creating attendance.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    const attendButton = member2Page.locator(
      '[data-attendance-role="attend-btn"]',
    );
    const leaveButton = member2Page.locator(
      '[data-attendance-role="leave-btn"]',
    );

    // Attend the event as a member.
    await expect(attendButton).toContainText("Attend event");

    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes(`/event/${TEST_EVENT_IDS.alpha.one}/attend`) &&
          response.ok(),
      ),
      attendButton.click(),
    ]);

    await expect(leaveButton).toContainText("Cancel attendance");

    // Load the group events dashboard as the organizer.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Upcoming In-Person Event",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
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

    // Load the attendees tab for the event.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees`,
            ) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    // Verify the organizer sees the public attendee.
    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Member Two",
    });

    await expect(
      attendeesContent.getByRole("table", { name: "Attendees list" }),
    ).toBeVisible();
    await expect(attendeeRow).toBeVisible();
    await expect(attendeeRow).toContainText("e2e-member-2");
    await expect(
      attendeesContent.getByRole("button", { name: "Send email" }),
    ).toBeEnabled();

    // Return to the public event page to restore attendance state.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Cancel the temporary attendance record.
    await leaveButton.click();
    await expect(
      member2Page.getByRole("button", { name: "Yes" }),
    ).toBeVisible();

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
    // Load the public event page before creating attendance.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    const attendButton = member2Page.locator(
      '[data-attendance-role="attend-btn"]',
    );
    const leaveButton = member2Page.locator(
      '[data-attendance-role="leave-btn"]',
    );

    // Attend the event as a member.
    await expect(attendButton).toContainText("Attend event");

    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes(`/event/${TEST_EVENT_IDS.alpha.one}/attend`) &&
          response.ok(),
      ),
      attendButton.click(),
    ]);

    await expect(leaveButton).toContainText("Cancel attendance");

    // Load the group events dashboard as the organizer.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Upcoming In-Person Event",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
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

    // Load the attendees tab for the event.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees`,
            ) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    // Target the attendee check-in toggle.
    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Member Two",
    });
    const checkInToggle = attendeeRow.locator(".check-in-toggle");

    await expect(attendeeRow).toBeVisible();
    await expect(checkInToggle).toBeEnabled();

    // Check in the attendee from the attendees tab.
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

    // Verify the checked-in attendee can access the check-in page.
    await navigateToPath(
      member2Page,
      `/${TEST_COMMUNITY_NAME}/check-in/${TEST_EVENT_IDS.alpha.one}`,
    );
    await expect(member2Page.getByText("You're checked in")).toBeVisible();

    // Return to the public event page to restore attendance state.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Cancel the temporary attendance record.
    await leaveButton.click();
    await expect(
      member2Page.getByRole("button", { name: "Yes" }),
    ).toBeVisible();

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
    // Load the group events dashboard before opening the seeded event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Upcoming Virtual Event",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.two}/update`,
            ) &&
          response.ok(),
      ),
      eventRow
        .locator('td button[aria-label="Edit event: Upcoming Virtual Event"]')
        .click(),
    ]);

    // Load the attendees tab for an event without RSVPs.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.two}/attendees`,
            ) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    // Verify the empty state and disabled email action.
    const attendeesContent = organizerGroupPage.locator("#attendees-content");

    await expect(
      attendeesContent.getByRole("table", { name: "Attendees list" }),
    ).toBeVisible();
    await expect(
      attendeesContent.locator("div.text-xl.lg\\:text-2xl:visible").filter({
        hasText: "No attendees found for this event.",
      }),
    ).toBeVisible();
    await expect(
      attendeesContent.getByRole("button", { name: "Send email" }),
    ).toBeDisabled();
    await expect(
      attendeesContent.getByRole("button", { name: "Send email" }),
    ).toHaveAttribute(
      "title",
      "No confirmed attendees with verified email addresses.",
    );
  });

  test("organizer can download attendees as CSV from the attendees tab", async ({
    organizerGroupPage,
  }) => {
    // Load the attendees tab for the seeded waitlist event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Full Event With Waitlist",
      TEST_EVENT_IDS.alpha.waitlistLab,
    );

    // Open attendee actions before selecting the CSV download.
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

    // Download the CSV and verify the seeded attendee row.
    const [download] = await Promise.all([
      organizerGroupPage.waitForEvent("download"),
      downloadCsvLink.click(),
    ]);
    const downloadPath = await download.path();

    if (!downloadPath) {
      throw new Error(
        "Expected attendee CSV download to have a local file path.",
      );
    }

    expect(download.suggestedFilename()).toBe(
      "event-alpha-waitlist-lab-attendees.csv",
    );
    const csvContents = await readFile(downloadPath, "utf8");
    expect(csvContents).toContain(
      "Name,Company,Title,Invited\nE2E Organizer One,,,No\n",
    );
  });

  test("organizer can review attendee registration answers", async ({
    organizerGroupPage,
  }) => {
    // Load the attendees tab for the seeded registration questions event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      TEST_REGISTRATION_QUESTIONS_EVENT.name,
      TEST_REGISTRATION_QUESTIONS_EVENT.id,
    );
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Member One",
    });
    const rowActionsMenu = attendeeRow.locator(
      "[data-attendee-row-actions-menu]",
    );

    await expect(attendeeRow).toBeVisible();
    await expect(rowActionsMenu).toBeVisible();

    // Open the row actions menu and show the attendee answers modal.
    await rowActionsMenu.locator("summary").click();
    await rowActionsMenu
      .getByRole("menuitem", { name: "View answers" })
      .click();

    // Verify the modal renders all seeded question answers.
    const answersModal = organizerGroupPage.locator("#attendee-answers-modal");
    await expect(answersModal).toBeVisible();
    await expect(
      answersModal.getByRole("heading", { name: "Registration answers" }),
    ).toBeVisible();
    await expect(answersModal.locator("#attendee-answers-name")).toHaveText(
      "E2E Member One",
    );
    await expect(answersModal).toContainText(
      "What are you hoping to learn from this event?",
    );
    await expect(answersModal).toContainText(
      "practical patterns for incident readiness",
    );
    await expect(answersModal).toContainText("Preferred session format");
    await expect(answersModal).toContainText("Hands-on workshop");
    await expect(answersModal).toContainText("Topics you want covered");
    await expect(answersModal).toContainText("Platform reliability");
    await expect(answersModal).toContainText("Developer experience");
    await expect(answersModal).toContainText("Open source governance");
    await expect(answersModal).toContainText(
      "Anything the organizers should know?",
    );
    await expect(answersModal).toContainText("Vegetarian lunch");

    // Close the answers modal after the review.
    await answersModal.locator("#cancel-attendee-answers-modal").click();
    await expect(answersModal).toBeHidden();
  });

  test("organizer can download attendee answers as CSV", async ({
    organizerGroupPage,
  }) => {
    // Load the attendees tab for the seeded registration questions event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      TEST_REGISTRATION_QUESTIONS_EVENT.name,
      TEST_REGISTRATION_QUESTIONS_EVENT.id,
    );

    // Open attendee actions before selecting the answers CSV download.
    const actionsButton = attendeesContent.getByRole("button", {
      name: "Open attendee actions menu",
    });
    await expect(actionsButton).toBeVisible();
    await actionsButton.click();

    const downloadCsvLink = attendeesContent.getByRole("menuitem", {
      name: "Attendees list CSV (including answers)",
    });
    await expect(downloadCsvLink).toBeVisible();
    await expect(downloadCsvLink).toHaveAttribute(
      "href",
      `/dashboard/group/events/${TEST_REGISTRATION_QUESTIONS_EVENT.id}/attendees-with-answers.csv`,
    );

    // Download the CSV and verify seeded question answers are included.
    const [download] = await Promise.all([
      organizerGroupPage.waitForEvent("download"),
      downloadCsvLink.click(),
    ]);
    const downloadPath = await download.path();

    if (!downloadPath) {
      throw new Error(
        "Expected attendee answers CSV download to have a local file path.",
      );
    }

    expect(download.suggestedFilename()).toBe(
      "event-alpha-registration-answers-lab-attendees-with-answers.csv",
    );
    const csvContents = await readFile(downloadPath, "utf8");
    expect(csvContents).toContain(
      "What are you hoping to learn from this event?",
    );
    expect(csvContents).toContain(
      "I want practical patterns for incident readiness",
    );
    expect(csvContents).toContain("Hands-on workshop");
    expect(csvContents).toContain("Platform reliability");
    expect(csvContents).toContain("Open source governance");
    expect(csvContents).toContain("Vegetarian lunch");
  });

  test("organizer can invite and cancel an attendee invitation", async ({
    organizerGroupPage,
  }) => {
    // Load the attendees tab for a seeded event without RSVPs.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Upcoming Virtual Event",
      TEST_EVENT_IDS.alpha.two,
    );

    // Open the manual invitation modal for an event without RSVPs.
    await attendeesContent
      .getByRole("button", { name: "Invite attendee" })
      .click();

    const modal = organizerGroupPage.locator("#attendee-invitation-modal");
    const searchField = modal.locator(
      "user-search-field[data-attendee-invitation-search]",
    );
    const searchInput = searchField.locator(
      "#attendee-invitation-search-input",
    );

    await expect(modal).toBeVisible();
    await expect(
      modal.getByRole("heading", { name: "Invite attendee" }),
    ).toBeVisible();
    await expect(modal.locator("#submit-attendee-invitation")).toBeDisabled();

    // Keep invalid free-form input from enabling the invitation form.
    await searchInput.fill("not-an-email");
    await expect(modal.locator("#submit-attendee-invitation")).toBeDisabled();

    // Select a seeded user and submit the invitation.
    await searchInput.fill("e2e-pending-2");
    await expect(searchField.getByText("E2E Pending Two")).toBeVisible();
    await searchField.getByText("E2E Pending Two").click();
    await expect(
      modal.locator("#attendee-invitation-selected-user"),
    ).toContainText("E2E Pending Two");
    await expect(modal.locator("#submit-attendee-invitation")).toBeEnabled();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.two}/attendees/invite`,
            ) &&
          response.ok(),
      ),
      modal.locator("#submit-attendee-invitation").click(),
    ]);

    await expect(modal).toBeHidden();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Invitation sent.",
    );

    // Verify the invitation appears in the attendees table.
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Pending Two",
    });
    await expect(attendeeRow).toBeVisible();
    await expect(attendeeRow).toContainText("Invitation sent");

    // Cancel the temporary invitation and wait for the table to refresh.
    const rowActionsMenu = attendeeRow.locator(
      "[data-attendee-row-actions-menu]",
    );
    await rowActionsMenu.locator("summary").click();
    await rowActionsMenu
      .getByRole("menuitem", { name: "Cancel invitation" })
      .click();
    await expect(
      organizerGroupPage.getByRole("button", { name: "Yes" }),
    ).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.two}/attendees/${TEST_USER_IDS.pending2}/invitation/cancel`,
            ) &&
          response.ok(),
      ),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(attendeeRow).toHaveCount(0);
    await expect(
      attendeesContent.locator("div.text-xl.lg\\:text-2xl:visible").filter({
        hasText: "No attendees found for this event.",
      }),
    ).toBeVisible();
  });

  test.describe("payment-enabled attendee refund flows", () => {
    test.skip(
      !E2E_PAYMENTS_ENABLED,
      "Payments are disabled in this environment.",
    );

    test("organizer can act on a pending refund request from the attendee row menu", async ({
      organizerGroupPage,
    }) => {
      // Load the attendees tab for the seeded refund review event.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Member One",
      });
      const rowActionsMenu = attendeeRow.locator(
        "[data-attendee-row-actions-menu]",
      );

      await expect(
        attendeeRow.getByText("Refund requested", { exact: true }),
      ).toBeVisible();
      await expect(rowActionsMenu).toBeVisible();

      // Verify pending refunds expose approve and reject actions.
      await rowActionsMenu.locator("summary").click();
      await expect(
        rowActionsMenu.getByRole("menuitem", { name: "Approve refund" }),
      ).toHaveAttribute("hx-put", /\/refund\/approve$/);
      await expect(
        rowActionsMenu.getByRole("menuitem", { name: "Reject refund" }),
      ).toHaveAttribute("hx-put", /\/refund\/reject$/);
    });

    test("organizer sees retry refund finalization for processing refunds in the row menu", async ({
      organizerGroupPage,
    }) => {
      // Load the attendees tab for the seeded refund review event.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Member Two",
      });
      const rowActionsMenu = attendeeRow.locator(
        "[data-attendee-row-actions-menu]",
      );

      await expect(
        attendeeRow.getByText("Refund processing", { exact: true }),
      ).toBeVisible();
      await expect(rowActionsMenu).toBeVisible();

      // Verify processing refunds only expose retry finalization.
      await rowActionsMenu.locator("summary").click();
      await expect(
        rowActionsMenu.getByRole("menuitem", {
          name: "Retry refund finalization",
        }),
      ).toHaveAttribute("hx-put", /\/refund\/approve$/);
      await expect(
        rowActionsMenu.getByRole("menuitem", { name: "Reject refund" }),
      ).toHaveCount(0);
    });

    test("organizer sees rejected refunds with disabled attendance cancellation", async ({
      organizerGroupPage,
    }) => {
      // Load the attendees tab for the seeded refund review event.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Pending One",
      });
      const rowActionsMenu = attendeeRow.locator(
        "[data-attendee-row-actions-menu]",
      );

      await expect(
        attendeeRow.getByText("Refund rejected", { exact: true }),
      ).toBeVisible();
      await expect(rowActionsMenu).toBeVisible();

      // Verify rejected paid attendees cannot be canceled manually.
      await rowActionsMenu.locator("summary").click();
      const cancelAttendance = rowActionsMenu.getByRole("menuitem", {
        name: "Cancel attendance",
      });
      await expect(cancelAttendance).toBeDisabled();
      await expect(cancelAttendance).toHaveAttribute(
        "title",
        "Paid attendee attendance cannot be canceled from attendee actions.",
      );
    });

    test("organizer sees approved refunds with disabled attendance cancellation", async ({
      organizerGroupPage,
    }) => {
      // Load the attendees tab for the seeded refund review event.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Group Viewer One",
      });
      const rowActionsMenu = attendeeRow.locator(
        "[data-attendee-row-actions-menu]",
      );

      await expect(
        attendeeRow.getByText("Refund approved", { exact: true }),
      ).toBeVisible();
      await expect(rowActionsMenu).toBeVisible();

      // Verify approved paid attendees cannot be canceled manually.
      await rowActionsMenu.locator("summary").click();
      const cancelAttendance = rowActionsMenu.getByRole("menuitem", {
        name: "Cancel attendance",
      });
      await expect(cancelAttendance).toBeDisabled();
      await expect(cancelAttendance).toHaveAttribute(
        "title",
        "Paid attendee attendance cannot be canceled from attendee actions.",
      );
    });

    test("viewer cannot review or approve attendee refunds", async ({
      groupViewerPage,
    }) => {
      // Load the attendees tab for the seeded refund review event.
      const attendeesContent = await openAttendeesTab(
        groupViewerPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );

      // Verify refund review controls are hidden for read-only viewers.
      await expect(
        attendeesContent.locator("[data-refund-review-trigger]"),
      ).toHaveCount(0);
      await expect(
        groupViewerPage.locator("#attendee-refund-modal"),
      ).toBeHidden();
    });
  });

  test("organizer can open and close the attendee email modal from the attendees tab", async ({
    organizerGroupPage,
  }) => {
    // Load the group events dashboard before opening the seeded event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Full Event With Waitlist",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
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

    // Load the attendees tab for the event.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees`,
            ) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    // Open the attendee email modal.
    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const openModalButton = attendeesContent.getByRole("button", {
      name: "Send email",
    });

    await expect(openModalButton).toBeEnabled();
    await openModalButton.click();

    // Verify the modal opens with the default message fields.
    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();
    await expect(
      modal.getByRole("heading", { name: "Send email" }),
    ).toBeVisible();
    await expect(
      modal.getByText("This email will be sent to all event attendees."),
    ).toBeVisible();
    await expect(modal.locator("#attendee-subject")).toHaveValue(
      "Platform Ops Meetup: Full Event With Waitlist",
    );
    await expect(modal.locator("#attendee-body")).toHaveValue("");

    // Close the attendee email modal without sending.
    await modal.getByRole("button", { name: "Cancel" }).click();
    await expect(modal).toBeHidden();
  });

  test("organizer can send an attendee email from the attendees tab", async ({
    organizerGroupPage,
  }) => {
    // Load the group events dashboard before opening the seeded event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Full Event With Waitlist",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
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

    // Load the attendees tab for the event.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees`,
            ) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    // Open the attendee email modal.
    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const openModalButton = attendeesContent.getByRole("button", {
      name: "Send email",
    });

    await expect(openModalButton).toBeEnabled();
    await openModalButton.click();

    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();

    // Fill and submit the attendee email.
    await modal
      .locator("#attendee-subject")
      .fill(ATTENDEE_NOTIFICATION_SUBJECT);
    await modal.locator("#attendee-body").fill(ATTENDEE_NOTIFICATION_BODY);

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes(
              `/dashboard/group/notifications/${TEST_EVENT_IDS.alpha.waitlistLab}`,
            ) &&
          response.ok(),
      ),
      modal.getByRole("button", { name: "Send email" }).click(),
    ]);

    // Verify the email modal closes after a successful send.
    await expect(modal).toBeHidden();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Email sent successfully to all event attendees!",
    );
  });

  test("organizer can open the event QR code modal from the attendees tab", async ({
    organizerGroupPage,
  }) => {
    // Load the group events dashboard before opening the seeded event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Full Event With Waitlist",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
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

    // Load the attendees tab for the event.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees`,
            ) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    // Open the event QR code modal.
    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const openModalButton = attendeesContent.locator(
      "#open-event-qr-code-modal",
    );

    await expect(openModalButton).toBeVisible();
    await openModalButton.click();

    // Verify the QR code modal content points at the check-in page.
    const modal = organizerGroupPage.locator("#event-qr-code-modal");
    await expect(modal).toBeVisible();
    await expect(
      modal.getByRole("heading", { name: "Event check-in QR code" }),
    ).toBeVisible();
    await expect(modal.locator("#event-qr-code-group-name")).toHaveText(
      "Platform Ops Meetup",
    );
    await expect(modal.locator("#event-qr-code-name")).toHaveText(
      "Full Event With Waitlist",
    );
    await expect(modal.locator("#event-qr-code-start")).not.toHaveText("");
    await expect(modal.locator("#event-qr-code-link")).toHaveAttribute(
      "href",
      buildE2eUrl(
        `/${TEST_COMMUNITY_NAME}/check-in/${TEST_EVENT_IDS.alpha.waitlistLab}`,
      ),
    );
    await expect(modal.locator("#event-qr-code-image")).toHaveAttribute(
      "src",
      `/dashboard/group/check-in/${TEST_EVENT_IDS.alpha.waitlistLab}/qr-code`,
    );
    await expect(modal.locator("#print-event-qr-code")).toBeEnabled();

    // Close the QR code modal after verifying its content.
    await modal.locator("#close-event-qr-code-modal").click();
    await expect(modal).toBeHidden();
  });
});
