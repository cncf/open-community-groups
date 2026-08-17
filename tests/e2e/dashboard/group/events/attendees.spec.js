import { readFile } from "node:fs/promises";

import { expect, test } from "../../../fixtures.js";

import {
  buildE2eUrl,
  E2E_PAYMENTS_ENABLED,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_CANCELLATION,
  TEST_EVENT_IDS,
  TEST_EVENT_NAMES,
  TEST_INVITATION_CANCELLATION,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_REGISTRATION_QUESTIONS_EVENT,
  TEST_TICKETING_EVENTS,
  TEST_USER_IDS,
  expectCurrentPaginationNavigation,
  expectTableColumnsAtViewport,
  expectTableHeaders,
  navigateToPath,
  routeNextRequestWithQuery,
  waitForActionResponse,
} from "../../../utils.js";

import {
  ATTENDEE_NOTIFICATION_BODY,
  ATTENDEE_NOTIFICATION_SUBJECT,
} from "../helpers.js";
import { createApprovalRequiredEvent, deleteEventFromList } from "./helpers.js";
import {
  expectUserColumnHasRoom,
  expectUserProfileModalFromRow,
} from "./user-profile-modal-helpers.js";

// Open the attendees tab for a specific event and return its content.
const openAttendeesTab = async (page, eventName, eventId, query = "") => {
  await navigateToPath(page, "/dashboard/group?tab=events");

  const eventRow = page.locator("tr", {
    hasText: eventName,
  });
  await expect(eventRow).toBeVisible();

  await waitForActionResponse(
    page,
    () => eventRow.locator('td button[aria-label^="Edit event:"]').click(),
    {
      method: "GET",
      urlIncludes: `/dashboard/group/events/${eventId}/update`,
    },
  );

  // The tab buttons only exist once the event update form has loaded.
  const attendeesTab = page.locator('button[data-section="attendees"]');
  if (query !== "") {
    await routeNextRequestWithQuery(
      page,
      `/dashboard/group/events/${eventId}/attendees`,
      query,
    );
  }

  await waitForActionResponse(page, () => attendeesTab.click(), {
    method: "GET",
    urlIncludes: `/dashboard/group/events/${eventId}/attendees`,
  });

  const attendeesContent = page.locator("#attendees-content");

  // Wait until the attendees tab has swapped in its table.
  await expect(
    attendeesContent.getByRole("table", { name: "Attendees list" }),
  ).toBeVisible();

  return attendeesContent;
};

const getVisibleStatusBadge = (root, text) =>
  root
    .locator(".custom-badge")
    .filter({ hasText: text })
    .filter({ visible: true });

// Verify an accepted or rejected request exposes its ticket offer details.
const expectTicketOfferStatus = async (
  requestRow,
  requestStatus,
  offerStatus,
) => {
  const requestStatusButton = requestRow.getByRole("button", {
    name: requestStatus,
    exact: true,
  });
  const offerDetails = requestRow.getByRole("tooltip");

  await requestStatusButton.focus();
  await expect(offerDetails).toBeVisible();
  await expect(
    offerDetails.getByText("Offer status", { exact: true }),
  ).toBeVisible();
  await expect(
    offerDetails.getByText(offerStatus, { exact: true }),
  ).toBeVisible();
};

// Open the invitation requests tab for a specific event and return its content.
const openInvitationRequestsTab = async (page, eventName, eventId) => {
  await navigateToPath(page, "/dashboard/group?tab=events");

  const eventRow = page.locator("tr", { hasText: eventName });
  await expect(eventRow).toBeVisible();
  await waitForActionResponse(
    page,
    () => eventRow.locator('td button[aria-label^="Edit event:"]').click(),
    {
      method: "GET",
      urlIncludes: `/dashboard/group/events/${eventId}/update`,
    },
  );
  await waitForActionResponse(
    page,
    () => page.locator('button[data-section="invitation-requests"]').click(),
    {
      method: "GET",
      urlIncludes: `/dashboard/group/events/${eventId}/invitation-requests`,
    },
  );

  const requestsContent = page.locator("#invitation-requests-content");
  await expect(
    requestsContent.getByRole("table", { name: "Invitation requests" }),
  ).toBeVisible();

  return requestsContent;
};

test.describe("group dashboard attendees tab", () => {
  test("attendees table exposes every column at its responsive breakpoint", async ({
    organizerGroupPage,
  }) => {
    // Open the seeded event attendees tab before checking table structure.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      TEST_EVENT_NAMES.alpha[0],
      TEST_EVENT_IDS.alpha.one,
    );
    // Find the attendees table.
    const attendeesTable = attendeesContent.getByRole("table", {
      name: "Attendees list",
    });

    // Verify header order and column visibility across dashboard breakpoints.
    await expectTableHeaders(attendeesTable, [
      "Select for email",
      "Attendee",
      "Position",
      "Status",
      "Ticket type",
      "Enrollment Date",
      "Checked In",
      "Actions",
    ]);
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      attendeesTable,
      1024,
      ["Attendee", "Ticket type", "Checked In", "Actions"],
      ["Select for email", "Position", "Status", "Enrollment Date"],
    );
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      attendeesTable,
      1280,
      ["Attendee", "Ticket type", "Checked In", "Actions"],
      ["Select for email", "Position", "Status", "Enrollment Date"],
    );
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      attendeesTable,
      1536,
      ["Attendee", "Status", "Ticket type", "Checked In", "Actions"],
      ["Select for email", "Position", "Enrollment Date"],
    );
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      attendeesTable,
      1920,
      [
        "Attendee",
        "Position",
        "Status",
        "Ticket type",
        "Enrollment Date",
        "Checked In",
        "Actions",
      ],
      ["Select for email"],
    );
  });

  test("organizer can move between attendee result pages", async ({
    organizerGroupPage,
  }) => {
    // Open seeded attendees with one result per page.
    await openAttendeesTab(
      organizerGroupPage,
      "Upcoming In-Person Event",
      TEST_EVENT_IDS.alpha.one,
      "?limit=1&offset=0",
    );

    // Verify pagination swaps attendee rows in both directions.
    await expectCurrentPaginationNavigation(
      organizerGroupPage,
      "#attendees-content tbody tr",
    );
  });

  test("event cancellation preserves attendee history and clears check-in", async ({
    organizerGroupPage,
  }) => {
    // Cancel the seeded event through the organizer endpoint.
    const cancelResponse = await organizerGroupPage.request.put(
      buildE2eUrl(
        `/dashboard/group/events/${TEST_EVENT_CANCELLATION.id}/cancel`,
      ),
    );
    if (!cancelResponse.ok()) {
      expect(cancelResponse.status()).toBe(422);
      expect(await cancelResponse.text()).toBe(
        "one or more events were not found or inactive",
      );
    }

    // Open retained attendee history after the event transition completes.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      TEST_EVENT_CANCELLATION.name,
      TEST_EVENT_CANCELLATION.id,
    );
    const checkedInAttendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Admin One",
    });
    const pendingRegistrationRow = attendeesContent.locator("tr", {
      hasText: "E2E Admin Two",
    });

    // Verify the canceled ticket history is retained and check-in is cleared.
    await expect(
      getVisibleStatusBadge(checkedInAttendeeRow, "Refunded"),
    ).toBeVisible();
    await expect(
      checkedInAttendeeRow.locator(".check-in-toggle"),
    ).not.toBeChecked();
    await expect(
      checkedInAttendeeRow.locator(".check-in-toggle"),
    ).toBeDisabled();
    await expect(
      getVisibleStatusBadge(pendingRegistrationRow, "Offer canceled"),
    ).toBeVisible();
  });

  test("canceled invitations remain visible in attendee history", async ({
    organizerGroupPage,
  }) => {
    // Open the pre-canceled event and inspect its retained invitation.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      TEST_INVITATION_CANCELLATION.name,
      TEST_INVITATION_CANCELLATION.id,
    );
    const canceledInvitationRow = attendeesContent.locator("tr", {
      hasText: "E2E Admin Two",
    });

    // Verify canceled invitations remain discoverable with explicit status.
    await expect(canceledInvitationRow).toBeVisible();
    await expect(canceledInvitationRow).toContainText("Invitation canceled");
  });

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
    await waitForActionResponse(
      groupViewerPage,
      () =>
        eventRow
          .locator(
            'td button[aria-label="Edit event: Full Event With Waitlist"]',
          )
          .click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/update`,
      },
    );

    // Load the attendees tab for the seeded event.
    await waitForActionResponse(
      groupViewerPage,
      () => groupViewerPage.locator('button[data-section="attendees"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees`,
      },
    );

    // Target the attendee row and verify controls remain read-only.
    const attendeesContent = groupViewerPage.locator("#attendees-content");
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Organizer One",
    });

    // Assert that Attendees list is visible.
    const attendeesTable = attendeesContent.getByRole("table", {
      name: "Attendees list",
    });
    await expect(attendeesTable).toBeVisible();
    await expectUserColumnHasRoom(attendeesTable, "Attendee");
    await expect(attendeeRow).toBeVisible();
    await expect(
      attendeesContent.locator("#attendee-email-actions-button"),
    ).toBeHidden();
    await expect(attendeeRow.locator(".check-in-toggle")).toBeDisabled();
  });

  test("organizer sees the empty state on the attendees tab for an event without RSVPs", async ({
    organizerGroupPage,
  }) => {
    // Give temporary event setup and cleanup enough time on slower deep runs.
    test.setTimeout(60_000);

    // Create a temporary event without attendees.
    const eventName = `E2E Empty Attendees ${Date.now()}`;
    const { eventId } = await createApprovalRequiredEvent(
      organizerGroupPage,
      eventName,
    );

    try {
      // Load the attendees tab for the temporary event.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        eventName,
        eventId,
      );

      // Assert that Attendees list is visible.
      await expect(
        attendeesContent.getByRole("table", { name: "Attendees list" }),
      ).toBeVisible();
      await expect(attendeesContent).toContainText(
        "No attendees found for this event.",
      );
      await expect(
        attendeesContent.getByRole("button", { name: "Send email" }),
      ).toBeDisabled();
      await expect(
        attendeesContent.getByRole("button", { name: "Send email" }),
      ).toHaveAttribute(
        "title",
        "No attendees with verified email addresses and email notifications enabled.",
      );
    } finally {
      await deleteEventFromList(organizerGroupPage, eventId);
    }
  });

  test("organizer can search attendees and clear the filter", async ({
    organizerGroupPage,
  }) => {
    // Load the attendees tab for the seeded event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Upcoming In-Person Event",
      TEST_EVENT_IDS.alpha.one,
    );

    // Target the search controls used to submit attendee filters.
    const searchInput = attendeesContent.getByRole("textbox", {
      name: "Search attendees",
    });
    const searchForm = attendeesContent.locator("#attendees-search-form");

    // Enter a query expected to match a seeded attendee.
    await searchInput.fill("member");

    // Submit the matching search and wait for filtered results.
    await searchForm.evaluate((form) => {
      if (form instanceof HTMLFormElement) {
        form.requestSubmit();
      }
    });

    // Verify the matching result is shown and non-matching attendees are hidden.
    await expect(
      attendeesContent.locator("tr", { hasText: "E2E Member One" }),
    ).toBeVisible();
    await expect(
      attendeesContent.locator("tr", { hasText: "E2E Organizer One" }),
    ).toHaveCount(0);
    await expect(searchInput).toHaveValue("member");

    // Enter a query expected to return no attendees.
    await searchInput.fill("");
    await searchInput.fill("zzzzzzzzzzzz");

    // Submit the empty-result search and wait for the empty state.
    await searchForm.evaluate((form) => {
      if (form instanceof HTMLFormElement) {
        form.requestSubmit();
      }
    });

    const noResultsMessage = attendeesContent
      .locator("div.text-xl.lg\\:text-2xl.mb-4:visible")
      .filter({ hasText: "No attendees found matching your filters." });

    // Verify the filtered empty result message is shown.
    await expect(noResultsMessage.first()).toBeVisible();

    // Clear the attendee search filter.
    await attendeesContent
      .getByRole("button", { name: "Clear attendee search" })
      .click();

    // Verify clearing removes the empty state and restores seeded attendees.
    await expect(noResultsMessage).toHaveCount(0);
    await expect(
      attendeesContent.locator("tr", { hasText: "E2E Member One" }),
    ).toBeVisible();
    await expect(
      attendeesContent.locator("tr", { hasText: "E2E Organizer One" }),
    ).toBeVisible();
    await expect(searchInput).toHaveValue("");

    // Sort attendees by name.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees`,
            ) &&
          response.url().includes("sort=name-desc") &&
          response.ok(),
      ),
      attendeesContent.getByLabel("Sort by").selectOption("name-desc"),
    ]);

    // Verify the sorted table keeps both seeded attendees visible.
    await expect(
      attendeesContent.locator("tr", { hasText: "E2E Member One" }),
    ).toBeVisible();
    await expect(
      attendeesContent.locator("tr", { hasText: "E2E Organizer One" }),
    ).toBeVisible();
  });

  test("organizer retains focus while filtering enrollment status", async ({
    organizerGroupPage,
  }) => {
    // Load the attendees tab for the seeded event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Upcoming In-Person Event",
      TEST_EVENT_IDS.alpha.one,
    );
    const statusFilter = attendeesContent.getByLabel("Status", {
      exact: true,
    });

    // Select enrollment history and verify the replacement control keeps focus.
    await statusFilter.focus();
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees`,
            ) &&
          response.url().includes("status=history") &&
          response.ok(),
      ),
      statusFilter.selectOption("history"),
    ]);
    await expect(statusFilter).toBeFocused();
    await expect(statusFilter).toHaveValue("history");

    // Return to current enrollments and preserve the same focus contract.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees`,
            ) &&
          response.url().includes("status=current") &&
          response.ok(),
      ),
      statusFilter.selectOption("current"),
    ]);
    await expect(statusFilter).toBeFocused();
    await expect(statusFilter).toHaveValue("current");
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

    // Find the Download CSV control.
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

    // Fail clearly if the CSV download was not captured.
    if (!downloadPath) {
      throw new Error(
        "Expected attendee CSV download to have a local file path.",
      );
    }

    // Assert the downloaded filename.
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
    const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");

    // Assert the expected content is visible.
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

    // Find the Attendees list CSV (including answers) control.
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

    // Fail clearly if the CSV download was not captured.
    if (!downloadPath) {
      throw new Error(
        "Expected attendee answers CSV download to have a local file path.",
      );
    }

    // Assert the downloaded filename.
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
    // Give the invite and cancel flow enough time on slower deep runs.
    test.setTimeout(60_000);

    // Create a temporary event for the invitation lifecycle.
    const eventName = `E2E Attendee Invitation ${Date.now()}`;
    const { eventId } = await createApprovalRequiredEvent(
      organizerGroupPage,
      eventName,
    );

    try {
      // Load the attendees tab for the temporary event.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        eventName,
        eventId,
      );

      // Open the manual invitation modal for an event without RSVPs.
      const actionsButton = attendeesContent.getByRole("button", {
        name: "Open attendee actions menu",
      });
      await expect(actionsButton).toBeVisible();
      await actionsButton.click();

      const inviteAttendeeButton = attendeesContent.getByRole("menuitem", {
        name: "Invite attendee",
      });
      await expect(inviteAttendeeButton).toBeVisible();
      await inviteAttendeeButton.click();

      // Find the modal.
      const modal = organizerGroupPage.locator("#attendee-invitation-modal");
      const searchField = modal.locator(
        "user-search-field[data-attendee-invitation-search]",
      );
      const searchInput = searchField.locator(
        "#attendee-invitation-search-input",
      );
      const ticketTypeSelect = modal.getByLabel("Ticket type");

      // Assert the expected content is visible.
      await expect(modal).toBeVisible();
      await expect(
        modal.getByRole("heading", { name: "Invite attendee" }),
      ).toBeVisible();
      await expect(ticketTypeSelect).toBeVisible();
      await expect(ticketTypeSelect).toHaveValue(/.+/);
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

      // Submit and wait for the server response.
      await waitForActionResponse(
        organizerGroupPage,
        () => modal.locator("#submit-attendee-invitation").click(),
        {
          method: "POST",
          urlIncludes: `/dashboard/group/events/${eventId}/attendees/invite`,
        },
      );

      // Assert that the content is hidden.
      await expect(modal).toBeHidden();
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Invitation sent.",
      );

      // Verify the invitation appears in the attendees table.
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Pending Two",
      });
      await expect(attendeeRow).toBeVisible();
      await expect(
        getVisibleStatusBadge(attendeeRow, "Offer pending"),
      ).toBeVisible();

      // Cancel the temporary invitation and wait for the table to refresh.
      const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");
      await rowActionsMenu.locator("summary").click();
      await rowActionsMenu
        .getByRole("menuitem", { name: "Cancel invitation" })
        .click();
      await expect(
        organizerGroupPage.getByRole("button", { name: "Yes" }),
      ).toBeVisible();

      // Click Yes.
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
        {
          method: "PUT",
          urlIncludes: "/dashboard/group/admission-offers/",
          urlEndsWith: "/cancel",
        },
      );

      // Dismiss the success alert before opening enrollment history.
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Invitation canceled.",
      );
      await organizerGroupPage.getByRole("button", { name: "OK" }).click();

      // Switch from current enrollments to history and find the canceled offer.
      const statusFilter = attendeesContent.getByLabel("Status", {
        exact: true,
      });
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response
              .url()
              .includes(`/dashboard/group/events/${eventId}/attendees`) &&
            response.url().includes("status=history") &&
            response.ok(),
        ),
        statusFilter.selectOption("history"),
      ]);

      // Canceled offers remain visible as enrollment history.
      await expect(
        getVisibleStatusBadge(attendeeRow, "Offer canceled"),
      ).toBeVisible();
    } finally {
      await deleteEventFromList(organizerGroupPage, eventId);
    }
  });

  test("organizer can accept and reject attendee invitation requests", async ({
    organizerGroupPage,
    pending1Page,
    pending2Page,
  }) => {
    // Give the invitation request flow enough time on slower deep runs.
    test.setTimeout(120_000);

    // Create a temporary approval-required event.
    const eventName = `E2E Invitation Requests ${Date.now()}`;
    const { eventId } = await createApprovalRequiredEvent(
      organizerGroupPage,
      eventName,
    );

    try {
      // Request invitations from two users. The attend endpoint expects a
      // form-encoded body, so send an empty form payload with each request.
      for (const requesterPage of [pending1Page, pending2Page]) {
        const requestResponse = await requesterPage.request.post(
          buildE2eUrl(`/${TEST_COMMUNITY_NAME}/event/${eventId}/attend`),
          { form: {} },
        );
        expect(requestResponse.ok()).toBeTruthy();
      }

      // Open the organizer Requests tab for the temporary event.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
      const eventRow = organizerGroupPage.locator("tr", { hasText: eventName });
      await expect(eventRow).toBeVisible();
      await waitForActionResponse(
        organizerGroupPage,
        () => eventRow.locator('td button[aria-label^="Edit event:"]').click(),
        {
          method: "GET",
          urlIncludes: `/dashboard/group/events/${eventId}/update`,
        },
      );
      const invitationRequestsTab = organizerGroupPage.locator(
        'button[data-section="invitation-requests"]',
      );
      await routeNextRequestWithQuery(
        organizerGroupPage,
        `/dashboard/group/events/${eventId}/invitation-requests`,
        "?limit=1&offset=0",
      );
      await waitForActionResponse(
        organizerGroupPage,
        () => invitationRequestsTab.click(),
        {
          method: "GET",
          urlIncludes: `/dashboard/group/events/${eventId}/invitation-requests`,
        },
      );

      const requestsContent = organizerGroupPage.locator(
        "#invitation-requests-content",
      );
      const invitationRequestsTable = requestsContent.getByRole("table", {
        name: "Invitation requests",
      });
      await expect(invitationRequestsTable).toBeVisible();
      await expectUserColumnHasRoom(invitationRequestsTable, "Requester");

      // Verify every request column appears at its responsive breakpoint.
      const invitationRequestHeaders = [
        "Requester",
        "Position",
        "Status",
        "Ticket type",
        "Requested",
        "Reviewed",
        "Actions",
      ];
      await expectTableColumnsAtViewport(
        organizerGroupPage,
        invitationRequestsTable,
        1024,
        ["Requester", "Status", "Actions"],
        ["Position", "Ticket type", "Requested", "Reviewed"],
      );
      await expectTableColumnsAtViewport(
        organizerGroupPage,
        invitationRequestsTable,
        1536,
        ["Requester", "Status", "Ticket type", "Reviewed", "Actions"],
        ["Position", "Requested"],
      );
      await expectTableColumnsAtViewport(
        organizerGroupPage,
        invitationRequestsTable,
        1920,
        invitationRequestHeaders,
        [],
      );
      await expectTableHeaders(
        invitationRequestsTable,
        invitationRequestHeaders,
      );

      // Verify both request pages and restore the full list for filter coverage.
      await expectCurrentPaginationNavigation(
        organizerGroupPage,
        "#invitation-requests-content tbody tr",
      );
      const searchForm = requestsContent.locator(
        "#invitation-requests-search-form",
      );
      const paginationLimit = searchForm.locator('input[name="limit"]');
      await paginationLimit.evaluate((input) => {
        input.value = "50";
      });
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response
              .url()
              .includes(
                `/dashboard/group/events/${eventId}/invitation-requests`,
              ) &&
            new URL(response.url()).searchParams.get("limit") === "50" &&
            response.ok(),
        ),
        searchForm.evaluate((form) => {
          if (form instanceof HTMLFormElement) {
            form.requestSubmit();
          }
        }),
      ]);

      // Target the search controls used to submit request filters.
      const searchInput = requestsContent.getByRole("textbox", {
        name: "Search invitation requests",
      });

      // Enter a query expected to match one seeded requester.
      await searchInput.fill("Two");

      // Submit the matching search and wait for filtered results.
      await searchForm.evaluate((form) => {
        if (form instanceof HTMLFormElement) {
          form.requestSubmit();
        }
      });

      // Verify the matching result is shown and non-matching requests are hidden.
      await expect(
        requestsContent.locator("tr", { hasText: "E2E Pending Two" }),
      ).toBeVisible();
      await expect(
        requestsContent.locator("tr", { hasText: "E2E Pending One" }),
      ).toHaveCount(0);
      await expect(searchInput).toHaveValue("Two");

      // Enter a query expected to return no requests.
      await searchInput.fill("");
      await searchInput.fill("zzzzzzzzzzzz");

      // Submit the empty-result search and wait for the empty state.
      await searchForm.evaluate((form) => {
        if (form instanceof HTMLFormElement) {
          form.requestSubmit();
        }
      });

      const noResultsMessage = requestsContent
        .locator("div.text-xl.lg\\:text-2xl.mb-4:visible")
        .filter({
          hasText: "No invitation requests found matching your search.",
        });

      // Verify the filtered empty result message is shown.
      await expect(noResultsMessage.first()).toBeVisible();

      // Clear the invitation request search filter.
      await requestsContent
        .getByRole("button", { name: "Clear invitation request search" })
        .click();

      // Verify clearing removes the empty state and restores request rows.
      await expect(noResultsMessage).toHaveCount(0);
      await expect(
        requestsContent.locator("tr", { hasText: "E2E Pending One" }),
      ).toBeVisible();
      await expect(
        requestsContent.locator("tr", { hasText: "E2E Pending Two" }),
      ).toBeVisible();
      await expect(searchInput).toHaveValue("");

      // Sort requesters by name before applying a status filter.
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response
              .url()
              .includes(
                `/dashboard/group/events/${eventId}/invitation-requests`,
              ) &&
            response.url().includes("sort=name-desc") &&
            response.ok(),
        ),
        requestsContent.getByLabel("Sort by").selectOption("name-desc"),
      ]);

      // Verify the sorted request table keeps both pending requesters visible.
      await expect(
        requestsContent.locator("tr", { hasText: "E2E Pending One" }),
      ).toBeVisible();
      await expect(
        requestsContent.locator("tr", { hasText: "E2E Pending Two" }),
      ).toBeVisible();

      // Switch the table to all statuses while preserving the active sort.
      await requestsContent.getByLabel("Status filters").click();
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response
              .url()
              .includes(
                `/dashboard/group/events/${eventId}/invitation-requests`,
              ) &&
            response.url().includes("sort=name-desc") &&
            response.url().includes("status=all") &&
            response.ok(),
        ),
        requestsContent
          .locator("#invitation-requests-status-filter")
          .getByRole("button", { name: "All", exact: true })
          .click(),
      ]);

      // Verify resetting status removes the previous badge while keeping sort.
      await expect(requestsContent.getByText("Active filters")).toHaveCount(0);

      const pendingOneRow = requestsContent.locator("tr", {
        hasText: "E2E Pending One",
      });

      // Verify profile modals still open from rows after the filtered refresh.
      await expectUserProfileModalFromRow(
        organizerGroupPage,
        pendingOneRow,
        "View profile for E2E Pending One",
        "E2E Pending One",
        [
          "Community Applicant at Approval Queue",
          "Pending One profile for invitation request modal coverage.",
          "openprofile.dev",
        ],
      );

      // Reject one invitation request.
      await expect(pendingOneRow).toContainText("Pending");
      await pendingOneRow
        .getByRole("button", {
          name: "Open actions for E2E Pending One",
          exact: true,
        })
        .click();
      await pendingOneRow
        .getByRole("button", { name: "Reject", exact: true })
        .click();
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Are you sure you want to reject this invitation request?",
      );
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
        {
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${eventId}/attendees/${TEST_USER_IDS.pending1}/invitation-request/reject`,
        },
      );
      await expect(pendingOneRow).toContainText("Rejected");

      // Accept the other invitation request.
      const pendingTwoRow = requestsContent.locator("tr", {
        hasText: "E2E Pending Two",
      });
      await expect(pendingTwoRow).toContainText("Pending");
      await pendingTwoRow
        .getByRole("button", {
          name: "Open actions for E2E Pending Two",
          exact: true,
        })
        .click();
      await waitForActionResponse(
        organizerGroupPage,
        () =>
          pendingTwoRow
            .getByRole("button", { name: "Accept", exact: true })
            .click(),
        {
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${eventId}/attendees/${TEST_USER_IDS.pending2}/invitation-request/accept`,
        },
      );
      await expectTicketOfferStatus(pendingTwoRow, "Accepted", "Pending");
    } finally {
      await deleteEventFromList(organizerGroupPage, eventId);
    }
  });

  test("organizer manages tiered invitation request offers across lifecycle states", async ({
    organizerGroupPage,
  }) => {
    test.setTimeout(90_000);
    await organizerGroupPage.setViewportSize({ width: 1600, height: 900 });

    const lifecycleEvent = TEST_TICKETING_EVENTS.invitationRequests;
    const requestsContent = await openInvitationRequestsTab(
      organizerGroupPage,
      lifecycleEvent.name,
      lifecycleEvent.id,
    );

    // Include accepted requests so expired and checkout-started offers are visible.
    await requestsContent.getByLabel("Status filters").click();
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${lifecycleEvent.id}/invitation-requests`,
            ) &&
          response.url().includes("status=all") &&
          response.ok(),
      ),
      requestsContent
        .locator("#invitation-requests-status-filter")
        .getByRole("button", { name: "All", exact: true })
        .click(),
    ]);

    // Verify the requested tier remains a first-class table column.
    await expect(
      requestsContent.getByRole("columnheader", {
        name: "Ticket type",
        exact: true,
      }),
    ).toBeVisible();
    const scopedRequestRow = requestsContent.locator("tr", {
      hasText: "E2E Pending Two",
    });
    await expect(scopedRequestRow).toContainText("General Admission");

    // Approve an unscoped request by choosing one assignable private tier.
    const unscopedRequestRow = requestsContent.locator("tr", {
      hasText: "E2E Pending One",
    });
    await unscopedRequestRow
      .getByRole("button", { name: "Open actions for E2E Pending One" })
      .click();
    const ticketTypeSelect = unscopedRequestRow.getByLabel(
      "Invitation-only ticket",
    );
    await expect(ticketTypeSelect).toContainText("Sponsor allocation");
    await expect(ticketTypeSelect).toContainText("VIP allocation");
    await ticketTypeSelect.selectOption("56555555-5555-5555-5555-655555555914");
    const approvalRequest = organizerGroupPage.waitForRequest(
      (request) =>
        request.method() === "PUT" &&
        request
          .url()
          .includes(
            `/events/${lifecycleEvent.id}/attendees/${TEST_USER_IDS.pending1}/invitation-request/accept`,
          ),
    );
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        unscopedRequestRow
          .getByRole("button", { name: "Accept", exact: true })
          .click(),
      {
        method: "PUT",
        urlIncludes: `/events/${lifecycleEvent.id}/attendees/${TEST_USER_IDS.pending1}/invitation-request/accept`,
      },
    );
    expect(
      new URLSearchParams((await approvalRequest).postData() ?? "").get(
        "event_ticket_type_id",
      ),
    ).toBe("56555555-5555-5555-5555-655555555914");
    await expectTicketOfferStatus(unscopedRequestRow, "Accepted", "Pending");

    // Reissue an expired offer while preserving its assigned private tier.
    const expiredOfferRow = requestsContent.locator("tr", {
      hasText: "E2E Admin Two",
    });
    await expect(expiredOfferRow).toContainText("Accepted");
    await expiredOfferRow
      .getByRole("button", { name: "Open actions for E2E Admin Two" })
      .click();
    await expect(
      expiredOfferRow.getByLabel("Invitation-only ticket"),
    ).toHaveValue("56555555-5555-5555-5555-655555555914");
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        expiredOfferRow
          .getByRole("button", { name: "Reissue offer", exact: true })
          .click(),
      {
        method: "PUT",
        urlIncludes: "/invitation-request/reissue",
      },
    );
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Ticket offer reissued.",
    );
    await organizerGroupPage.getByRole("button", { name: "OK" }).click();

    // Cancel an offer whose attendee has already started provider checkout.
    const checkoutOfferRow = requestsContent.locator("tr", {
      hasText: "E2E Organizer Two",
    });
    await checkoutOfferRow
      .getByRole("button", { name: "Open actions for E2E Organizer Two" })
      .click();
    await checkoutOfferRow
      .getByRole("button", { name: "Cancel offer", exact: true })
      .click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Are you sure you want to cancel this ticket offer?",
    );
    await waitForActionResponse(
      organizerGroupPage,
      () => organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
      {
        method: "PUT",
        urlIncludes: "/dashboard/group/admission-offers/",
        urlEndsWith: "/cancel",
      },
    );
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Ticket offer canceled.",
    );

    // Open a request on an event whose only private tier is inactive.
    const unavailableEvent = TEST_TICKETING_EVENTS.noAssignableTier;
    const unavailableRequests = await openInvitationRequestsTab(
      organizerGroupPage,
      unavailableEvent.name,
      unavailableEvent.id,
    );
    const unavailableRow = unavailableRequests.locator("tr", {
      hasText: "E2E Community Viewer One",
    });
    await unavailableRow
      .getByRole("button", {
        name: "Open actions for E2E Community Viewer One",
      })
      .click();
    await expect(
      unavailableRow.locator("[data-invitation-request-ticket-empty]"),
    ).toBeVisible();
    await expect(
      unavailableRow.getByText(
        "No invitation-only ticket types can be assigned.",
        { exact: false },
      ),
    ).toBeVisible();
    await expect(
      unavailableRow.getByRole("button", { name: "Accept", exact: true }),
    ).toBeDisabled();
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
      const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");

      // Assert that Refund requested is visible.
      await expect(
        getVisibleStatusBadge(attendeeRow, "Refund requested"),
      ).toBeVisible();
      await expect(rowActionsMenu).toBeVisible();

      // Verify pending refunds expose approve and reject actions.
      await rowActionsMenu.locator("summary").click();
      const approveRefundAction = rowActionsMenu.getByRole("menuitem", {
        name: "Approve refund",
      });
      await expect(approveRefundAction).toHaveAttribute(
        "data-refund-approve-url",
        /\/refunds\/[^/]+\/approve$/,
      );
      await expect(approveRefundAction).toHaveAttribute(
        "data-attendee-refund-approve-open",
        "",
      );
      const rejectRefundAction = rowActionsMenu.getByRole("menuitem", {
        name: "Reject refund",
      });
      await expect(rejectRefundAction).toHaveAttribute(
        "data-refund-reject-url",
        /\/refunds\/[^/]+\/reject$/,
      );
      await expect(rejectRefundAction).toHaveAttribute(
        "data-attendee-refund-reject-open",
        "",
      );
      const cancelAttendance = rowActionsMenu.getByRole("menuitem", {
        name: "Cancel attendance and refund",
      });
      await expect(cancelAttendance).toBeEnabled();
      await expect(cancelAttendance).toHaveAttribute(
        "hx-delete",
        /\/attendance$/u,
      );

      // Verify approval opens the optional review-note modal.
      await approveRefundAction.click();
      const approveDialog = organizerGroupPage.getByRole("dialog", {
        name: "Approve refund request",
      });
      await expect(approveDialog).toBeVisible();
      const approvalNote = approveDialog.getByLabel("Review note (optional)");
      await expect(approvalNote).toBeFocused();
      await expect(approvalNote).not.toHaveAttribute("required", "");
      await approveDialog.getByRole("button", { name: "Cancel" }).click();
      await expect(approveDialog).toBeHidden();
      await expect(rowActionsMenu.locator("summary")).toBeFocused();

      // Verify rejection opens the attendee-visible reason modal.
      await rowActionsMenu.locator("summary").click();
      await rejectRefundAction.click();
      const rejectDialog = organizerGroupPage.getByRole("dialog", {
        name: "Reject refund request",
      });
      await expect(rejectDialog).toBeVisible();
      await expect(
        rejectDialog.getByLabel("Reason shown to attendee"),
      ).toBeFocused();
      await rejectDialog.getByRole("button", { name: "Cancel" }).click();
      await expect(rejectDialog).toBeHidden();
      await expect(rowActionsMenu.locator("summary")).toBeFocused();
    });

    test("organizer submits an attendee-visible reason when rejecting a refund", async ({
      organizerGroupPage,
    }) => {
      // Return a successful rejection without changing seeded payment state.
      await organizerGroupPage.route("**/refunds/*/reject", (route) =>
        route.fulfill({ status: 204 }),
      );

      // Open the attendee refund rejection modal.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Member One",
      });
      const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");
      await rowActionsMenu.locator("summary").click();
      await rowActionsMenu
        .getByRole("menuitem", { name: "Reject refund" })
        .click();
      const rejectDialog = organizerGroupPage.getByRole("dialog", {
        name: "Reject refund request",
      });
      const rejectionReason = rejectDialog.getByLabel(
        "Reason shown to attendee",
      );
      await expect(rejectionReason).toHaveAttribute("required", "");
      await expect(rejectDialog).toContainText(
        "This reason appears in the attendee's email, My Events, and the event page.",
      );
      await rejectionReason.fill("Outside the refund policy window");

      // Submit the reason and verify the request contract.
      const [rejectResponse] = await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            /\/dashboard\/group\/refunds\/[^/]+\/reject$/u.test(
              new URL(response.url()).pathname,
            ),
        ),
        rejectDialog.getByRole("button", { name: "Reject refund" }).click(),
      ]);
      const rejectionData = new URLSearchParams(
        rejectResponse.request().postData(),
      );
      expect(rejectionData.get("review_note")).toBe(
        "Outside the refund policy window",
      );
      await expect(rejectDialog).toBeHidden();
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Refund request rejected.",
      );
      await organizerGroupPage.locator(".swal2-confirm").click();
    });

    test("organizer sees success alerts after approving and rejecting refunds", async ({
      organizerGroupPage,
    }) => {
      // Return successful refund responses without changing seeded payment state.
      await organizerGroupPage.route("**/refunds/*/approve", (route) =>
        route.fulfill({ status: 204 }),
      );
      await organizerGroupPage.route("**/refunds/*/reject", (route) =>
        route.fulfill({ status: 204 }),
      );

      // Load the pending refund actions.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Member One",
      });
      const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");

      // Approve the refund with a review note and verify success feedback.
      await rowActionsMenu.locator("summary").click();
      await rowActionsMenu
        .getByRole("menuitem", { name: "Approve refund" })
        .click();
      const approveDialog = organizerGroupPage.getByRole("dialog", {
        name: "Approve refund request",
      });
      await approveDialog
        .getByLabel("Review note (optional)")
        .fill("Approved by organizer");
      const [approveResponse] = await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            /\/dashboard\/group\/refunds\/[^/]+\/approve$/u.test(
              new URL(response.url()).pathname,
            ),
        ),
        approveDialog.getByRole("button", { name: "Approve refund" }).click(),
      ]);
      const approvalData = new URLSearchParams(
        approveResponse.request().postData(),
      );
      expect(approvalData.get("review_note")).toBe("Approved by organizer");
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Refund queued.",
      );
      await organizerGroupPage.locator(".swal2-confirm").click();

      // Reject the refund and verify success feedback.
      await rowActionsMenu.locator("summary").click();
      await rowActionsMenu
        .getByRole("menuitem", { name: "Reject refund" })
        .click();
      const rejectDialog = organizerGroupPage.getByRole("dialog", {
        name: "Reject refund request",
      });
      await rejectDialog
        .getByLabel("Reason shown to attendee")
        .fill("Outside the refund policy window");
      await rejectDialog.getByRole("button", { name: "Reject refund" }).click();
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Refund request rejected.",
      );
    });

    test("organizer sees error alerts when refund actions fail", async ({
      organizerGroupPage,
    }) => {
      // Return failed refund responses without changing seeded payment state.
      await organizerGroupPage.route("**/refunds/*/approve", (route) =>
        route.fulfill({ status: 500 }),
      );
      await organizerGroupPage.route("**/refunds/*/reject", (route) =>
        route.fulfill({ status: 500 }),
      );

      // Load the pending refund actions.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Member One",
      });
      const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");

      // Fail refund approval and verify error feedback.
      await rowActionsMenu.locator("summary").click();
      await rowActionsMenu
        .getByRole("menuitem", { name: "Approve refund" })
        .click();
      const approveDialog = organizerGroupPage.getByRole("dialog", {
        name: "Approve refund request",
      });
      const approvalNote = approveDialog.getByLabel("Review note (optional)");
      await approvalNote.fill("Approved by organizer");
      await approveDialog
        .getByRole("button", { name: "Approve refund" })
        .click();
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Something went wrong approving this refund request. Please try again later.",
      );
      await expect(approveDialog).toBeVisible();
      await expect(approvalNote).toHaveValue("Approved by organizer");
      await organizerGroupPage.locator(".swal2-confirm").click();
      await approveDialog.getByRole("button", { name: "Cancel" }).click();

      // Fail refund rejection and verify error feedback.
      await rowActionsMenu.locator("summary").click();
      await rowActionsMenu
        .getByRole("menuitem", { name: "Reject refund" })
        .click();
      const rejectDialog = organizerGroupPage.getByRole("dialog", {
        name: "Reject refund request",
      });
      const reviewNote = rejectDialog.getByLabel("Reason shown to attendee");
      await reviewNote.fill("Outside the refund policy window");
      await rejectDialog.getByRole("button", { name: "Reject refund" }).click();
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Something went wrong rejecting this refund request. Please try again later.",
      );
      await expect(rejectDialog).toBeVisible();
      await expect(reviewNote).toHaveValue("Outside the refund policy window");
    });

    test("organizer cannot retry a refund while provider processing is active", async ({
      organizerGroupPage,
    }) => {
      // Load the attendees tab for the seeded refund review event.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Organizer Two",
      });
      const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");

      // Assert that Refund processing is visible.
      await expect(
        getVisibleStatusBadge(attendeeRow, "Refund processing"),
      ).toBeVisible();
      await expect(rowActionsMenu).toBeVisible();

      // Verify processing refunds cannot be canceled, retried, or rejected.
      await rowActionsMenu.locator("summary").click();
      const cancelAttendance = rowActionsMenu.getByRole("menuitem", {
        name: "Cancel attendance and refund",
      });
      await expect(cancelAttendance).toBeDisabled();
      await expect(cancelAttendance).toHaveAttribute(
        "title",
        "A refund is already in progress for this attendee.",
      );
      await expect(
        rowActionsMenu.getByRole("menuitem", { name: "Retry refund" }),
      ).toHaveCount(0);
      await expect(
        rowActionsMenu.getByRole("menuitem", { name: "Reject refund" }),
      ).toHaveCount(0);
    });

    test("organizer can queue cancellation after a refund request was rejected", async ({
      organizerGroupPage,
    }) => {
      // Return a successful cancellation without changing shared seeded payment state.
      await organizerGroupPage.route("**/attendees/*/attendance", (route) =>
        route.fulfill({
          status: 204,
          headers: {
            "HX-Trigger": "refresh-event-attendees, refresh-group-refunds",
          },
        }),
      );

      // Load the attendees tab for the seeded refund review event.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Pending One",
      });
      const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");

      // Assert that Refund rejected is visible.
      await expect(
        getVisibleStatusBadge(attendeeRow, "Refund rejected"),
      ).toBeVisible();
      await expect(rowActionsMenu).toBeVisible();

      // Verify the organizer can queue a full refund from the attendee action.
      await rowActionsMenu.locator("summary").click();
      const cancelAttendance = rowActionsMenu.getByRole("menuitem", {
        name: "Cancel attendance and refund",
      });
      await expect(cancelAttendance).toBeEnabled();
      await expect(cancelAttendance).toHaveAttribute(
        "hx-delete",
        /attendance$/u,
      );
      await cancelAttendance.click();
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Their attendance will remain active until the refund is confirmed.",
      );
      const attendeesRefreshResponse = organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_PAYMENT_EVENT_IDS.refunds}/attendees`,
            ) &&
          response.ok(),
      );
      await waitForActionResponse(
        organizerGroupPage,
        () =>
          organizerGroupPage
            .getByRole("button", { name: "Queue refund" })
            .click(),
        {
          method: "DELETE",
          urlIncludes: "/dashboard/group/events/",
          urlEndsWith: "/attendance",
        },
      );
      await attendeesRefreshResponse;
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Refund queued. Attendance will be canceled after confirmation.",
      );
      await expect(
        attendeesContent.getByRole("table", { name: "Attendees list" }),
      ).toBeVisible();
    });

    test("organizer sees an error when paid attendance cancellation fails", async ({
      organizerGroupPage,
    }) => {
      // Return a failed cancellation without changing shared seeded payment state.
      await organizerGroupPage.route("**/attendees/*/attendance", (route) =>
        route.fulfill({ status: 500 }),
      );

      // Open the paid cancellation action for a rejected refund request.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Pending One",
      });
      const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");
      await rowActionsMenu.locator("summary").click();
      const cancelAttendance = rowActionsMenu.locator(
        "button[role='menuitem']",
        {
          hasText: "Cancel attendance and refund",
        },
      );
      await cancelAttendance.click();

      // Submit the cancellation and verify its paid-specific recovery feedback.
      await waitForActionResponse(
        organizerGroupPage,
        () =>
          organizerGroupPage
            .getByRole("button", { name: "Queue refund" })
            .click(),
        {
          method: "DELETE",
          status: 500,
          urlIncludes: "/dashboard/group/events/",
          urlEndsWith: "/attendance",
        },
      );
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Something went wrong queueing this refund. Please try again later.",
      );
      await organizerGroupPage.locator(".swal2-confirm").click();
      await expect(cancelAttendance).toBeEnabled();
    });

    test("paid attendance cancellation stays disabled while its request is pending", async ({
      organizerGroupPage,
    }) => {
      // Hold the cancellation response so its pending state remains observable.
      let releaseCancellationResponse;
      const cancellationResponseGate = new Promise((resolve) => {
        releaseCancellationResponse = resolve;
      });
      let cancellationRequestCount = 0;
      await organizerGroupPage.route(
        "**/attendees/*/attendance",
        async (route) => {
          cancellationRequestCount += 1;
          await cancellationResponseGate;
          await route.fulfill({ status: 204 });
        },
      );

      // Start paid attendance cancellation from the attendee row.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Pending One",
      });
      const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");
      await rowActionsMenu.locator("summary").click();
      const cancelAttendance = rowActionsMenu.locator(
        "button[role='menuitem']",
        {
          hasText: "Cancel attendance and refund",
        },
      );
      await cancelAttendance.click();
      const cancellationResponse = organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().endsWith("/attendance"),
      );
      await organizerGroupPage
        .getByRole("button", { name: "Queue refund" })
        .click();

      // Verify HTMX prevents another cancellation until the request completes.
      await expect.poll(() => cancellationRequestCount).toBe(1);
      await expect(cancelAttendance).toBeDisabled();
      releaseCancellationResponse();
      await cancellationResponse;
      expect(cancellationRequestCount).toBe(1);
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
      const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");

      // Assert that Refund approved is visible.
      await expect(
        getVisibleStatusBadge(attendeeRow, "Refund approved"),
      ).toBeVisible();
      await expect(rowActionsMenu).toBeVisible();

      // Verify approved paid attendees cannot be canceled manually.
      await rowActionsMenu.locator("summary").click();
      const cancelAttendance = rowActionsMenu.getByRole("menuitem", {
        name: "Cancel attendance and refund",
      });
      await expect(cancelAttendance).toBeDisabled();
      await expect(cancelAttendance).toHaveAttribute(
        "title",
        "This attendee's refund has already been approved.",
      );
    });

    test("viewer cannot manage attendee refunds", async ({
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
        attendeesContent.locator("[data-attendee-refund-approve-open]"),
      ).toHaveCount(0);
      await expect(
        attendeesContent.locator("[data-attendee-refund-reject-open]"),
      ).toHaveCount(0);
      await expect(
        groupViewerPage.locator("#attendee-refund-approve-modal"),
      ).toHaveCount(0);
      await expect(
        groupViewerPage.locator("#attendee-refund-reject-modal"),
      ).toHaveCount(0);
      await expect(
        attendeesContent.getByRole("menuitem", {
          name: "Cancel attendance and refund",
        }),
      ).toHaveCount(0);
    });
  });

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
      () =>
        eventRow
          .locator(
            'td button[aria-label="Edit event: Full Event With Waitlist"]',
          )
          .click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/update`,
      },
    );

    // Load the attendees tab for the event.
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        organizerGroupPage.locator('button[data-section="attendees"]').click(),
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
    await attendeesContent
      .getByRole("menuitem", { name: "All eligible attendees" })
      .click();

    // Verify the modal opens with the default message fields.
    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();
    await expect(
      modal.getByRole("heading", { name: "Send email" }),
    ).toBeVisible();
    await expect(
      modal.getByText("This email will be sent to 1 eligible attendee."),
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

    // Find the event row.
    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Full Event With Waitlist",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        eventRow
          .locator(
            'td button[aria-label="Edit event: Full Event With Waitlist"]',
          )
          .click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/update`,
      },
    );

    // Load the attendees tab for the event.
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        organizerGroupPage.locator('button[data-section="attendees"]').click(),
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
    await attendeesContent
      .getByRole("menuitem", { name: "All eligible attendees" })
      .click();

    // Find the modal.
    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();

    // Fill and submit the attendee email.
    await modal
      .locator("#attendee-subject")
      .fill(ATTENDEE_NOTIFICATION_SUBJECT);
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

  test("organizer can choose attendees for attendee email", async ({
    organizerGroupPage,
  }) => {
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
    await attendeesContent
      .getByRole("menuitem", { name: "Choose attendees" })
      .click();

    // Find the attendee email selection controls.
    const selectionBar = attendeesContent.locator(
      "[data-attendee-email-selection-bar]",
    );
    const selectionCheckboxes = attendeesContent.locator(
      "[data-attendee-email-selection-checkbox]",
    );
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

    await selectionSendButton.click();

    // Verify the email modal is configured for selected recipients.
    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();
    await expect(
      modal.getByText("This email will be sent to 1 selected attendee."),
    ).toBeVisible();
    await expect(
      modal.locator("#attendee-notification-recipient-scope"),
    ).toHaveValue("selected");
    await expect(
      modal.locator("#attendee-notification-selected-fields input"),
    ).toHaveCount(1);

    // Close the modal and exit selection mode.
    await modal.getByRole("button", { name: "Cancel" }).click();
    await expect(modal).toBeHidden();
    await selectionBar.getByRole("button", { name: "Cancel" }).click();
    await expect(selectionBar).toBeHidden();
    await expect(openEmailActionsButton).toBeEnabled();
  });

  test("organizer can send an attendee email to selected attendees", async ({
    organizerGroupPage,
  }) => {
    // Load the attendees tab for the seeded waitlist event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Full Event With Waitlist",
      TEST_EVENT_IDS.alpha.waitlistLab,
    );

    // Open attendee email actions and enter selection mode.
    await attendeesContent.getByRole("button", { name: "Send email" }).click();
    await attendeesContent
      .getByRole("menuitem", { name: "Choose attendees" })
      .click();

    // Find the attendee email selection controls.
    const selectionBar = attendeesContent.locator(
      "[data-attendee-email-selection-bar]",
    );
    const selectionCheckboxes = attendeesContent.locator(
      "[data-attendee-email-selection-checkbox]",
    );

    // Select the eligible attendee and open the email modal.
    await expect(selectionCheckboxes).toHaveCount(1);
    await selectionCheckboxes.check();
    await selectionBar.getByRole("button", { name: "Continue" }).click();

    // Verify the email modal is configured for selected recipients.
    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();
    await expect(
      modal.getByText("This email will be sent to 1 selected attendee."),
    ).toBeVisible();
    await expect(
      modal.locator("#attendee-notification-recipient-scope"),
    ).toHaveValue("selected");

    // Fill and submit the selected attendee email.
    await modal
      .locator("#attendee-subject")
      .fill(ATTENDEE_NOTIFICATION_SUBJECT);
    await modal.locator("#attendee-body").fill(ATTENDEE_NOTIFICATION_BODY);

    const notificationResponse = await waitForActionResponse(
      organizerGroupPage,
      () => modal.getByRole("button", { name: "Send email" }).click(),
      {
        method: "POST",
        urlIncludes: `/dashboard/group/notifications/${TEST_EVENT_IDS.alpha.waitlistLab}`,
      },
    );

    // Verify the selected-recipient parameters were submitted.
    expect(notificationResponse.request().postData()).toContain(
      "recipient_scope=selected",
    );
    expect(notificationResponse.request().postData()).toContain(
      "recipient_user_ids%5B0%5D=",
    );

    // Verify the selected email send closes the modal and clears selection mode.
    await expect(modal).toBeHidden();
    await expect(selectionBar).toBeHidden();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Email sent successfully to selected attendees!",
    );
    await organizerGroupPage.getByRole("button", { name: "OK" }).click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toBeHidden();
  });

  test("organizer can open attendee email from an attendee row", async ({
    organizerGroupPage,
  }) => {
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
    await expect(
      modal.getByText("This email will be sent to 1 selected attendee."),
    ).toBeVisible();
    await expect(
      modal.locator("#attendee-notification-recipient-scope"),
    ).toHaveValue("selected");
    await expect(
      modal.locator("#attendee-notification-selected-fields input"),
    ).toHaveCount(1);

    // Close the attendee email modal without sending.
    await modal.getByRole("button", { name: "Cancel" }).click();
    await expect(modal).toBeHidden();
  });
});
