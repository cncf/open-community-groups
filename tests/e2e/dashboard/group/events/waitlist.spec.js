import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabase } from "../../../database.js";
import { snapshotNotifications } from "../../../notifications.js";
import {
  TEST_EVENT_IDS,
  TEST_INVITATION_CANCELLATION,
  TEST_USER_IDS,
  TEST_WAITLIST_INVITE_EVENT,
} from "../../../seed.js";
import {
  expectCurrentPaginationNavigation,
  navigateToPath,
  routeNextRequestWithQuery,
  waitForActionResponse,
  waitForHtmxSettle,
} from "../../../utils.js";
import { expectUserColumnHasRoom, expectUserProfileModalFromRow } from "./user-profile-modal-helpers.js";

const DASHBOARD_WAITLIST_EVENT_NAME = "Dashboard Waitlist Table Lab";

const PAST_WAITLIST_EVENT_NAME = "Past Event For Filtering";

test.describe("group dashboard waitlist tab", () => {
  test("organizer can move between waitlist result pages", async ({ organizerGroupPage }) => {
    // Open seeded waitlist entries with one result per page.
    await openDashboardWaitlist(organizerGroupPage, "?limit=1&offset=0");

    // Verify pagination swaps waitlist rows in both directions.
    await expectCurrentPaginationNavigation(organizerGroupPage, "#waitlist-content tbody tr");
  });

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
    await waitForActionResponse(
      organizerGroupPage,
      () => eventRow.locator('td button[aria-label="Edit event: Upcoming In-Person Event"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`,
      },
    );

    // Submit and wait for the server response.
    await waitForActionResponse(
      organizerGroupPage,
      () => organizerGroupPage.locator('button[data-section="waitlist"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/waitlist`,
      },
    );

    // Find the waitlist content.
    const waitlistContent = organizerGroupPage.locator("#waitlist-content");
    await expect(
      waitlistContent.locator("p.text-sm.lg\\:text-md.text-stone-700:visible").filter({
        hasText: "Enable waitlist to allow full events to add people to the queue.",
      }),
    ).toBeVisible();
  });

  test("organizer can enable waitlist for an event and then restore it", async ({ organizerGroupPage }) => {
    // Expand the viewport so the editor navigation is visible.
    await organizerGroupPage.setViewportSize({ width: 1920, height: 1080 });

    // Open the seeded alpha event editor from the events list.
    const openAlphaEventEditor = async () => {
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

      // Find the event row.
      const eventRow = organizerGroupPage.locator("tr", {
        hasText: "Upcoming In-Person Event",
      });
      await expect(eventRow).toBeVisible();

      // Submit and wait for the server response.
      await waitForActionResponse(
        organizerGroupPage,
        () => eventRow.locator('td button[aria-label="Edit event: Upcoming In-Person Event"]').click(),
        {
          method: "GET",
          urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`,
        },
      );
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
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.locator("#update-event-button").click(),
        {
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`,
        },
      );
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
    await waitForActionResponse(
      organizerGroupPage,
      () => organizerGroupPage.locator('button[data-section="waitlist"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/waitlist`,
      },
    );

    // Find the waitlist content.
    const waitlistContent = organizerGroupPage.locator("#waitlist-content");
    const emptyWaitlistMessage = waitlistContent
      .locator("p.text-sm.lg\\:text-md.text-stone-700:visible")
      .filter({ hasText: "Waitlist entries for this event will appear here." });
    await expect(emptyWaitlistMessage).toHaveCount(1);
    await expect(emptyWaitlistMessage).toBeVisible();

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
    await waitForActionResponse(
      organizerGroupPage,
      () => eventRow.locator(`td button[aria-label="Edit event: ${DASHBOARD_WAITLIST_EVENT_NAME}"]`).click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/update`,
      },
    );

    // Submit and wait for the server response.
    await waitForActionResponse(
      organizerGroupPage,
      () => organizerGroupPage.locator('button[data-section="waitlist"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`,
      },
    );

    // Find the waitlist content.
    const waitlistContent = organizerGroupPage.locator("#waitlist-content");
    const waitlistRow = waitlistContent.locator("tr", {
      hasText: "E2E Member Two",
    });

    // Assert that Waitlist entries is visible.
    const waitlistTable = waitlistContent.getByRole("table", {
      name: "Waitlist entries",
    });
    await expect(waitlistTable).toBeVisible();
    await expectUserColumnHasRoom(waitlistTable, "Entry");
    await expect(waitlistRow).toBeVisible();
    await expect(waitlistRow).toContainText("e2e-member-2");
    await expect(waitlistRow.locator("td").nth(2)).toHaveText("1");
    const queuedWaitlistAction = waitlistRow.getByRole("button", {
      name: "Open waitlist actions for E2E Member Two",
    });
    await expect(queuedWaitlistAction).toBeEnabled();
    await expect(queuedWaitlistAction).toHaveAttribute("aria-expanded", "false");
    const expiredOfferRow = waitlistContent.locator("tr", {
      hasText: "E2E Admin One",
    });
    const expiredOfferAction = expiredOfferRow.getByRole("button", {
      name: "Open waitlist actions for E2E Admin One",
    });
    await expect(expiredOfferRow).toBeVisible();
    await expect(expiredOfferRow).toContainText("Offer expired");
    await expect(expiredOfferAction).toBeEnabled();
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
    await expect(waitlistRow.locator("td").nth(2)).toHaveText("1");
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

  test("organizer sees the empty ticket state when the waitlist event is sold out", async ({
    organizerGroupPage,
  }) => {
    // Load the sold-out waitlist table lab whose only seat is already taken.
    const waitlistContent = await openWaitlistTab(
      organizerGroupPage,
      DASHBOARD_WAITLIST_EVENT_NAME,
      TEST_EVENT_IDS.alpha.dashboardWaitlist,
    );
    const queuedRow = waitlistContent.locator("tr", { hasText: "E2E Member Two" });
    const queuedActions = queuedRow.getByRole("button", {
      name: "Open waitlist actions for E2E Member Two",
    });

    // Open the queued entry menu and verify its invite form cannot pick a tier.
    await queuedActions.click();
    await expect(queuedActions).toHaveAttribute("aria-expanded", "true");
    await expect(queuedRow.getByLabel("Ticket type")).toBeDisabled();
    const inviteButton = queuedRow.locator("[data-waitlist-invite-ticket-submit]");
    await expect(inviteButton).toHaveText("Invite");
    await expect(inviteButton).toBeDisabled();
    await expect(queuedRow.locator("[data-waitlist-invite-ticket-empty]")).toBeVisible();
    await expect(queuedRow.getByText("No ticket types can be assigned.", { exact: false })).toBeVisible();

    // Verify Escape closes the menu and returns focus to its disclosure button.
    await organizerGroupPage.keyboard.press("Escape");
    await expect(queuedActions).toHaveAttribute("aria-expanded", "false");
    await expect(queuedRow.getByLabel("Ticket type")).toBeHidden();
    await expect(queuedActions).toBeFocused();
  });

  test("organizer invites a queued entry and reissues an expired offer from the waitlist", async ({
    organizerGroupPage,
  }) => {
    test.setTimeout(90_000);

    // Snapshot notifications so the offers created here can be cleaned up afterwards.
    const notificationSnapshot = snapshotNotifications();
    const inviteUrl = `/dashboard/group/events/${TEST_WAITLIST_INVITE_EVENT.id}/attendees/invite`;

    try {
      // Load the invite lab waitlist with queued, expired, and claimed entries.
      const waitlistContent = await openWaitlistTab(
        organizerGroupPage,
        TEST_WAITLIST_INVITE_EVENT.name,
        TEST_WAITLIST_INVITE_EVENT.id,
      );

      // Verify claimed offers stay read-only and explain why.
      const claimedRow = waitlistContent.locator("tr", { hasText: "E2E Member One" });
      const claimedAction = claimedRow.getByRole("button", {
        name: "Waitlist actions unavailable for E2E Member One",
      });
      await expect(claimedRow).toContainText("Ticket claimed");
      await expect(claimedAction).toBeDisabled();
      await expect(claimedAction).toHaveAttribute("title", "This waiting list offer was already claimed.");

      // Open the queued entry menu and verify the queued tier is preselected.
      const queuedRow = waitlistContent.locator("tr", { hasText: "E2E Pending One" });
      const queuedActions = queuedRow.getByRole("button", {
        name: "Open waitlist actions for E2E Pending One",
      });
      await expect(queuedRow.locator("td").nth(2)).toHaveText("1");
      await queuedActions.click();
      await expect(queuedActions).toHaveAttribute("aria-expanded", "true");
      const queuedTicketSelect = queuedRow.getByLabel("Ticket type");
      await expect(queuedTicketSelect).toBeEnabled();
      await expect(queuedTicketSelect).toHaveValue(TEST_WAITLIST_INVITE_EVENT.ticketTypeId);
      await expect(queuedTicketSelect).toContainText("General Admission (Public)");
      await expect(queuedRow.locator("[data-waitlist-invite-ticket-empty]")).toBeHidden();

      // Invite the queued entry and verify the request carries the user and tier.
      const inviteButton = queuedRow.locator("[data-waitlist-invite-ticket-submit]");
      await expect(inviteButton).toHaveText("Invite");
      await expect(inviteButton).toBeEnabled();
      const inviteRequest = organizerGroupPage.waitForRequest(
        (request) => request.method() === "POST" && request.url().includes(inviteUrl),
      );
      const refreshAfterInvite = waitForWaitlistRefresh(organizerGroupPage, TEST_WAITLIST_INVITE_EVENT.id);
      await waitForActionResponse(organizerGroupPage, () => inviteButton.click(), {
        method: "POST",
        urlIncludes: inviteUrl,
        status: 201,
      });
      const invitePayload = new URLSearchParams((await inviteRequest).postData() ?? "");
      expect(invitePayload.get("user_id")).toBe(TEST_USER_IDS.pending1);
      expect(invitePayload.get("event_ticket_type_id")).toBe(TEST_WAITLIST_INVITE_EVENT.ticketTypeId);
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Invitation sent.");
      await organizerGroupPage.getByRole("button", { name: "OK" }).click();

      // Verify the refreshed table drops the queued entry and the offer is durable.
      await refreshAfterInvite;
      await waitForHtmxSettle(organizerGroupPage);
      await expect(queuedRow).toHaveCount(0);
      expect(
        queryE2eDatabase(`
          select source || ':' || status
          from admission_offer
          where event_id = '${TEST_WAITLIST_INVITE_EVENT.id}'
          and user_id = '${TEST_USER_IDS.pending1}'
        `),
      ).toBe("organizer_invitation:pending");
      expect(
        queryE2eDatabase(`
          select count(*)
          from event_waitlist
          where event_id = '${TEST_WAITLIST_INVITE_EVENT.id}'
          and user_id = '${TEST_USER_IDS.pending1}'
        `),
      ).toBe("0");

      // Open the expired offer menu and verify its offered tier is preselected.
      const expiredRow = waitlistContent.locator("tr", { hasText: "E2E Pending Two" });
      const expiredActions = expiredRow.getByRole("button", {
        name: "Open waitlist actions for E2E Pending Two",
      });
      const reissueButton = expiredRow.locator("[data-waitlist-invite-ticket-submit]");
      await expect(expiredRow).toContainText("Offer expired");
      await expiredActions.click();
      await expect(expiredRow.getByLabel("Ticket type")).toHaveValue(TEST_WAITLIST_INVITE_EVENT.ticketTypeId);
      await expect(reissueButton).toHaveText("Reissue offer");

      // Reissue the expired offer and verify the request targets the expired user.
      const reissueRequest = organizerGroupPage.waitForRequest(
        (request) => request.method() === "POST" && request.url().includes(inviteUrl),
      );
      const refreshAfterReissue = waitForWaitlistRefresh(organizerGroupPage, TEST_WAITLIST_INVITE_EVENT.id);
      await waitForActionResponse(organizerGroupPage, () => reissueButton.click(), {
        method: "POST",
        urlIncludes: inviteUrl,
        status: 201,
      });
      const reissuePayload = new URLSearchParams((await reissueRequest).postData() ?? "");
      expect(reissuePayload.get("user_id")).toBe(TEST_USER_IDS.pending2);
      expect(reissuePayload.get("event_ticket_type_id")).toBe(TEST_WAITLIST_INVITE_EVENT.ticketTypeId);
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Ticket offer reissued.");
      await organizerGroupPage.getByRole("button", { name: "OK" }).click();

      // Verify the expired history stays next to the reissued organizer offer.
      await refreshAfterReissue;
      await waitForHtmxSettle(organizerGroupPage);
      await expect(expiredRow).toBeVisible();
      await expect(expiredRow).toContainText("Offer expired");
      expect(
        queryE2eDatabase(`
          select string_agg(source || ':' || status, ',' order by created_at)
          from admission_offer
          where event_id = '${TEST_WAITLIST_INVITE_EVENT.id}'
          and user_id = '${TEST_USER_IDS.pending2}'
        `),
      ).toBe("waitlist:expired,organizer_invitation:pending");

      // Verify a repeated reissue is rejected while the new offer is still pending.
      await expiredActions.click();
      await waitForActionResponse(organizerGroupPage, () => reissueButton.click(), {
        method: "POST",
        urlIncludes: inviteUrl,
        status: 422,
      });
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "user already has a pending event invitation",
      );
      await organizerGroupPage.getByRole("button", { name: "OK" }).click();
    } finally {
      restoreWaitlistInviteFixtures(notificationSnapshot);
    }
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
    await waitForActionResponse(
      groupViewerPage,
      () => eventRow.locator(`td button[aria-label="Edit event: ${DASHBOARD_WAITLIST_EVENT_NAME}"]`).click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/update`,
      },
    );

    // Load the waitlist tab and target its seeded entry.
    await waitForActionResponse(
      groupViewerPage,
      () => groupViewerPage.locator('button[data-section="waitlist"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`,
      },
    );
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
      "Your role cannot manage the waiting list.",
    );
  });
});

/** Opens the dashboard waitlist tab and returns its content region. */
const openDashboardWaitlist = async (page, query = "") => {
  await navigateToPath(page, "/dashboard/group?tab=events");

  const eventRow = page.locator("tr", {
    hasText: DASHBOARD_WAITLIST_EVENT_NAME,
  });
  await expect(eventRow).toBeVisible();

  await waitForActionResponse(
    page,
    () => eventRow.locator(`td button[aria-label="Edit event: ${DASHBOARD_WAITLIST_EVENT_NAME}"]`).click(),
    {
      method: "GET",
      urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/update`,
    },
  );

  // The tab buttons only exist once the event update form has loaded.
  const waitlistTab = page.locator('button[data-section="waitlist"]');
  if (query !== "") {
    await routeNextRequestWithQuery(
      page,
      `/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`,
      query,
    );
  }

  await waitForActionResponse(page, () => waitlistTab.click(), {
    method: "GET",
    urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`,
  });

  return page.locator("#waitlist-content");
};

/** Opens an event's waitlist tab from the requested dashboard event list. */
const openWaitlistTab = async (page, eventName, eventId, { past = false } = {}) => {
  await navigateToPath(page, "/dashboard/group?tab=events");

  if (past) {
    await page.locator("#past-tab").click();
    await expect(page.locator("#past-content")).toBeVisible();
  }

  const eventsContent = page.locator(past ? "#past-content" : "#upcoming-content");
  const eventRow = eventsContent.locator("tr", { hasText: eventName });
  await expect(eventRow).toBeVisible();

  await waitForActionResponse(
    page,
    () => eventRow.locator(`td button[aria-label="Edit event: ${eventName}"]`).click(),
    {
      method: "GET",
      urlIncludes: `/dashboard/group/events/${eventId}/update`,
    },
  );

  await waitForActionResponse(page, () => page.locator('button[data-section="waitlist"]').click(), {
    method: "GET",
    urlIncludes: `/dashboard/group/events/${eventId}/waitlist`,
  });

  const waitlistContent = page.locator("#waitlist-content");
  await expect(waitlistContent.getByRole("table", { name: "Waitlist entries" })).toBeVisible();

  return waitlistContent;
};

/** Restores the invite lab waitlist fixtures mutated by organizer invitations. */
const restoreWaitlistInviteFixtures = (notificationSnapshot) => {
  queryE2eDatabase(`
    delete from admission_offer
    where event_id = '${TEST_WAITLIST_INVITE_EVENT.id}'
    and source = 'organizer_invitation';

    insert into event_waitlist (event_id, event_ticket_type_id, user_id)
    values (
      '${TEST_WAITLIST_INVITE_EVENT.id}',
      '${TEST_WAITLIST_INVITE_EVENT.ticketTypeId}',
      '${TEST_USER_IDS.pending1}'
    )
    on conflict do nothing;

    delete from notification
    where created_at >= '${notificationSnapshot.createdAfter}'::timestamptz
    and kind = 'event-admission-offer-created'
    and user_id in ('${TEST_USER_IDS.pending1}'::uuid, '${TEST_USER_IDS.pending2}'::uuid);
  `);
};

/** Returns a promise for the waitlist table refresh triggered by a completed action. */
const waitForWaitlistRefresh = (page, eventId) =>
  page.waitForResponse(
    (response) =>
      response.request().method() === "GET" &&
      response.url().includes(`/dashboard/group/events/${eventId}/waitlist`) &&
      response.ok(),
  );
