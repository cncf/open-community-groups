import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabase } from "../../../database.js";
import {
  cleanupEventsByIds,
  setupTicketAllocationEvent,
  setupTicketWaitlistEntry,
} from "../../../data-graphs/events.js";
import {
  TEST_EVENT_IDS,
  TEST_GROUP_IDS,
  TEST_INVITATION_CANCELLATION,
  TEST_USER_IDS,
  TEST_WAITLIST_INVITE_EVENT,
} from "../../../seed.js";
import {
  confirmAlert,
  dismissAlert,
  expectCurrentPaginationNavigation,
  waitForActionResponse,
  waitForHtmxSettle,
  waitForResponseMatching,
} from "../../../utils.js";
import { expectStaleCapacityConflict, holdSeat } from "./attendees-helpers.js";
import {
  openCurrentEventEditorSection,
  openDashboardWaitlist,
  openEventSection,
  openEventUpdateFormByName,
} from "./helpers.js";
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

  test("organizer keeps the waitlist tab while a disabled waitlist has entries", async ({
    organizerGroupPage,
    owned,
  }) => {
    const event = setupDisabledWaitlistEvent(owned);

    // Queue a member on the full event while its waitlist stays disabled.
    queueDisabledWaitlistMember(event);

    // Open the event editor.
    await openEventUpdateFormByName(organizerGroupPage, event.name, event.eventId);
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("false");

    // Verify both section pickers still offer the waitlist.
    await expect(organizerGroupPage.locator('button[data-section="waitlist"]')).toHaveCount(1);
    await expect(
      organizerGroupPage.locator('#update-event-section-select option[value="waitlist"]'),
    ).toHaveCount(1);

    // Open the waitlist tab and verify the remaining entry is listed.
    const waitlistContent = await openCurrentEventEditorSection(
      organizerGroupPage,
      event.eventId,
      "waitlist",
      "#waitlist-content",
      { tableName: "Waitlist entries" },
    );
    await expect(waitlistContent.locator("tr", { hasText: "E2E Member Two" })).toBeVisible();
  });

  test("organizer loses the waitlist tab once a disabled waitlist is empty", async ({
    organizerGroupPage,
    owned,
  }) => {
    const event = setupDisabledWaitlistEvent(owned);

    // Queue a member so the disabled waitlist tab is rendered.
    queueDisabledWaitlistMember(event);

    // Open the event editor while the entry still exists.
    await openEventUpdateFormByName(organizerGroupPage, event.name, event.eventId);
    await expect(organizerGroupPage.locator('button[data-section="waitlist"]')).toHaveCount(1);

    // Remove the last entry before the waitlist tab lazy-loads.
    removeDisabledWaitlistMember(event);

    // Open the waitlist tab and verify the disabled empty state.
    const waitlistContent = await openCurrentEventEditorSection(
      organizerGroupPage,
      event.eventId,
      "waitlist",
      "#waitlist-content",
    );
    await expect(
      waitlistContent.locator("p.text-sm.lg\\:text-md.text-stone-700:visible").filter({
        hasText: "Enable waitlist to allow full events to add people to the queue.",
      }),
    ).toBeVisible();

    // Reopen the event editor and verify the empty disabled waitlist has no tab.
    await openEventUpdateFormByName(organizerGroupPage, event.name, event.eventId);
    await expect(organizerGroupPage.locator('button[data-section="waitlist"]')).toHaveCount(0);
    await expect(
      organizerGroupPage.locator('#update-event-section-select option[value="waitlist"]'),
    ).toHaveCount(0);
    await expect(organizerGroupPage.locator('[data-content="waitlist"]')).toHaveCount(0);
  });

  test("organizer can enable and disable the waitlist for an event", async ({
    organizerGroupPage,
    owned,
  }) => {
    const event = setupDisabledWaitlistEvent(owned);

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
          urlIncludes: `/dashboard/group/events/${event.eventId}/update`,
        },
      );
    };

    // Expand the viewport so the editor navigation is visible.
    await organizerGroupPage.setViewportSize({ width: 1920, height: 1080 });

    // Open the owned event editor.
    await openEventUpdateFormByName(organizerGroupPage, event.name, event.eventId);
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("false");

    // Enable the waitlist setting.
    await submitWaitlistValue("true");

    // Reopen the event editor.
    await openEventUpdateFormByName(organizerGroupPage, event.name, event.eventId);
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("true");

    // Open the waitlist tab and verify the empty enabled state.
    const waitlistContent = await openCurrentEventEditorSection(
      organizerGroupPage,
      event.eventId,
      "waitlist",
      "#waitlist-content",
    );
    const emptyWaitlistMessage = waitlistContent
      .locator("p.text-sm.lg\\:text-md.text-stone-700:visible")
      .filter({ hasText: "Waitlist entries for this event will appear here." });
    await expect(emptyWaitlistMessage).toHaveCount(1);
    await expect(emptyWaitlistMessage).toBeVisible();

    // Disable the waitlist setting.
    await submitWaitlistValue("false");

    // Reopen the event editor.
    await openEventUpdateFormByName(organizerGroupPage, event.name, event.eventId);
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("false");

    // Assert the empty disabled waitlist no longer has a tab.
    await expect(organizerGroupPage.locator('button[data-section="waitlist"]')).toHaveCount(0);
    await expect(
      organizerGroupPage.locator('#update-event-section-select option[value="waitlist"]'),
    ).toHaveCount(0);
  });

  test("organizer can see a waitlist entry on the waitlist tab", async ({ organizerGroupPage }) => {
    // Use the wide table layout because the Position filter is 2xl-only.
    await organizerGroupPage.setViewportSize({ width: 1600, height: 900 });

    // Open the seeded event waitlist section.
    const waitlistContent = await openDashboardWaitlist(organizerGroupPage);
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

    // Enter a query expected to match the visible waitlist entry.
    await searchInput.fill("Two");

    // Submit the matching search and wait for filtered results.
    await waitForActionResponse(organizerGroupPage, () => searchInput.press("Enter"), {
      method: "GET",
      params: { ts_query: "Two" },
      pathname: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`,
      status: 200,
    });

    // Verify the matching result is shown with a queue position.
    await expect(waitlistRow).toBeVisible();
    await expect(waitlistRow).toContainText("e2e-member-2");
    await expect(waitlistRow.locator("td").nth(2)).toHaveText("1");
    await expect(searchInput).toHaveValue("Two");

    // Enter a query expected to return no waitlist entries.
    await searchInput.fill("");
    await searchInput.fill("zzzzzzzzzzzz");

    // Submit the empty-result search and wait for the empty state.
    await waitForActionResponse(organizerGroupPage, () => searchInput.press("Enter"), {
      method: "GET",
      params: { ts_query: "zzzzzzzzzzzz" },
      pathname: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`,
      status: 200,
    });

    const noResultsMessage = waitlistContent.locator("div.text-xl.lg\\:text-2xl.mb-4:visible").filter({
      hasText: "No waitlist entries found matching your search.",
    });

    // Verify the filtered empty result message is shown.
    await expect(noResultsMessage.first()).toBeVisible();

    // Clear the waitlist search filter.
    await waitForActionResponse(
      organizerGroupPage,
      () => waitlistContent.getByRole("button", { name: "Clear waitlist search" }).click(),
      {
        method: "GET",
        params: { ts_query: null },
        pathname: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`,
        status: 200,
      },
    );

    // Verify clearing removes the empty state and restores the waitlist entry.
    await expect(noResultsMessage).toHaveCount(0);
    await expect(waitlistRow).toBeVisible();
    await expect(waitlistRow).toContainText("e2e-member-2");
    await expect(searchInput).toHaveValue("");

    // Sort the waitlist by entry name and keep the row visible.
    await waitForActionResponse(
      organizerGroupPage,
      () => waitlistContent.getByLabel("Sort by").selectOption("name-desc"),
      {
        method: "GET",
        params: { sort: "name-desc" },
        pathname: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`,
        status: 200,
      },
    );

    // Verify the sorted waitlist row remains visible.
    await expect(waitlistRow).toBeVisible();

    // Apply the title-present table filter while preserving the sort.
    await waitlistContent.getByLabel("Position filters").click();
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        waitlistContent.locator('#waitlist-position-filter button[name="title"][value="present"]').click(),
      {
        method: "GET",
        params: { sort: "name-desc", title: "present" },
        pathname: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.dashboardWaitlist}/waitlist`,
        status: 200,
      },
    );

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

  test("organizer invites a queued entry and an expired offer holder from the waitlist", async ({
    organizerGroupPage,
  }) => {
    const inviteUrl = `/dashboard/group/events/${TEST_WAITLIST_INVITE_EVENT.id}/attendees/invite`;

    try {
      // Load the invite lab waitlist with queued, expired, and claimed entries.
      const waitlistContent = await openWaitlistTab(
        organizerGroupPage,
        TEST_WAITLIST_INVITE_EVENT.name,
        TEST_WAITLIST_INVITE_EVENT.id,
      );

      // Verify earlier lapsed offers stay behind one row per person.
      const claimedRow = waitlistContent.locator("tr", { hasText: "E2E Member One" });
      const queuedRow = waitlistContent.locator("tr", { hasText: "E2E Pending One" });
      await expect(waitlistContent).toContainText(/1 - 3 of\s+3\s+waitlist entries/);
      await expect(claimedRow).toHaveCount(1);
      await expect(queuedRow).toHaveCount(1);
      await expect(queuedRow).not.toContainText("Offer expired");

      // Verify claimed offers stay read-only and explain why.
      const claimedAction = claimedRow.getByRole("button", {
        name: "Waitlist actions unavailable for E2E Member One",
      });
      await expect(claimedRow).toContainText("Ticket claimed");
      await expect(claimedAction).toBeDisabled();
      await expect(claimedAction).toHaveAttribute("title", "This waiting list offer was already claimed.");

      // Open the queued entry menu and verify the only tier with seats is preselected.
      const queuedActions = queuedRow.getByRole("button", {
        name: "Open waitlist actions for E2E Pending One",
      });
      await expect(queuedRow.locator("td").nth(2)).toHaveText("1");
      await queuedActions.click();
      await expect(queuedActions).toHaveAttribute("aria-expanded", "true");
      const queuedTicketSelect = queuedRow.getByLabel("Ticket type");
      await expect(queuedTicketSelect).toBeEnabled();
      await expect(queuedTicketSelect).toHaveValue(TEST_WAITLIST_INVITE_EVENT.inviteTicketTypeId);
      await expect(queuedTicketSelect).toContainText("Late Admission (Public)");
      await expect(queuedTicketSelect).not.toContainText("General Admission");
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
      expect(invitePayload.get("event_ticket_type_id")).toBe(TEST_WAITLIST_INVITE_EVENT.inviteTicketTypeId);
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Invitation sent.");
      await organizerGroupPage.getByRole("button", { name: "OK" }).click();

      // Verify the refreshed table drops the queued entry without exposing its earlier offer.
      await refreshAfterInvite;
      await waitForHtmxSettle(organizerGroupPage);
      await expect(queuedRow).toHaveCount(0);
      expect(
        queryE2eDatabase(`
          select string_agg(source || ':' || status, ',' order by created_at)
          from admission_offer
          where event_id = '${TEST_WAITLIST_INVITE_EVENT.id}'
          and user_id = '${TEST_USER_IDS.pending1}'
        `),
      ).toBe("waitlist:expired,organizer_invitation:pending");
      expect(
        queryE2eDatabase(`
          select count(*)
          from event_waitlist
          where event_id = '${TEST_WAITLIST_INVITE_EVENT.id}'
          and user_id = '${TEST_USER_IDS.pending1}'
        `),
      ).toBe("0");

      // Open the expired offer menu and verify it offers the same invite action.
      const expiredRow = waitlistContent.locator("tr", { hasText: "E2E Pending Two" });
      const expiredActions = expiredRow.getByRole("button", {
        name: "Open waitlist actions for E2E Pending Two",
      });
      const expiredInviteButton = expiredRow.locator("[data-waitlist-invite-ticket-submit]");
      await expect(expiredRow).toContainText("Offer expired");
      await expiredActions.click();
      await expect(expiredRow.getByLabel("Ticket type")).toHaveValue(
        TEST_WAITLIST_INVITE_EVENT.inviteTicketTypeId,
      );
      await expect(expiredInviteButton).toHaveText("Invite");

      // Invite the expired offer holder and verify the request targets that user.
      const expiredInviteRequest = organizerGroupPage.waitForRequest(
        (request) => request.method() === "POST" && request.url().includes(inviteUrl),
      );
      const refreshAfterExpiredInvite = waitForWaitlistRefresh(
        organizerGroupPage,
        TEST_WAITLIST_INVITE_EVENT.id,
      );
      await waitForActionResponse(organizerGroupPage, () => expiredInviteButton.click(), {
        method: "POST",
        urlIncludes: inviteUrl,
        status: 201,
      });
      const expiredInvitePayload = new URLSearchParams((await expiredInviteRequest).postData() ?? "");
      expect(expiredInvitePayload.get("user_id")).toBe(TEST_USER_IDS.pending2);
      expect(expiredInvitePayload.get("event_ticket_type_id")).toBe(
        TEST_WAITLIST_INVITE_EVENT.inviteTicketTypeId,
      );
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Invitation sent.");
      await organizerGroupPage.getByRole("button", { name: "OK" }).click();

      // Verify the new organizer offer supersedes the expired row while claimed history stays.
      await refreshAfterExpiredInvite;
      await waitForHtmxSettle(organizerGroupPage);
      await expect(expiredRow).toHaveCount(0);
      await expect(claimedRow).toContainText("Ticket claimed");
      expect(
        queryE2eDatabase(`
          select string_agg(source || ':' || status, ',' order by created_at)
          from admission_offer
          where event_id = '${TEST_WAITLIST_INVITE_EVENT.id}'
          and user_id = '${TEST_USER_IDS.pending2}'
        `),
      ).toBe("waitlist:expired,organizer_invitation:pending");
    } finally {
      restoreWaitlistInviteFixtures();
    }
  });

  test("organizer gets sold-out guidance when a waitlist invite tier fills", async ({
    organizerGroupPage,
    owned,
  }) => {
    const event = owned.track(
      setupTicketAllocationEvent({
        groupId: TEST_GROUP_IDS.community1.alpha,
        ticketTypes: [
          { key: "full", seats: 1, title: "Full tier" },
          { key: "open", seats: 1, title: "Open tier" },
        ],
        waitlistEnabled: true,
      }),
      ({ eventId }) => cleanupEventsByIds([eventId]),
    );
    const inviteUrl = `/dashboard/group/events/${event.eventId}/attendees/invite`;

    // Queue a member for the full tier while the open tier still has one seat left.
    holdSeat(event, "full", TEST_USER_IDS.admin1);
    setupTicketWaitlistEntry({
      eventId: event.eventId,
      ticketTypeId: event.ticketTypeIds.full,
      userId: TEST_USER_IDS.pending1,
    });
    const waitlistContent = await openWaitlistTab(organizerGroupPage, event.name, event.eventId);

    // Choose the open tier for the queued member.
    const queuedRow = waitlistContent.locator("tr", { hasText: "E2E Pending One" });
    await queuedRow.getByRole("button", { name: "Open waitlist actions for E2E Pending One" }).click();
    const ticketTypeSelect = queuedRow.getByLabel("Ticket type");
    await expect(ticketTypeSelect.locator("option", { hasText: "Full tier" })).toHaveCount(0);
    await ticketTypeSelect.selectOption(event.ticketTypeIds.open);
    const inviteButton = queuedRow.locator("[data-waitlist-invite-ticket-submit]");
    await expect(inviteButton).toBeEnabled();

    // Take the last open seat after the table rendered, then send the stale invitation.
    holdSeat(event, "open", TEST_USER_IDS.admin2);
    const refresh = waitForWaitlistRefresh(organizerGroupPage, event.eventId);
    await expectStaleCapacityConflict(organizerGroupPage, () => inviteButton.click(), {
      matcher: { method: "POST", urlIncludes: inviteUrl },
    });
    await refresh;

    // The conflict leaves the member queued.
    expect(
      queryE2eDatabase(`
        select count(*)
        from admission_offer
        where event_id = '${event.eventId}'
        and user_id = '${TEST_USER_IDS.pending1}'
      `),
    ).toBe("0");
    expect(
      queryE2eDatabase(`
        select count(*)
        from event_waitlist
        where event_id = '${event.eventId}'
        and user_id = '${TEST_USER_IDS.pending1}'
      `),
    ).toBe("1");

    // The refreshed row no longer offers a tier, so another stale invite cannot be sent.
    const refreshedRow = waitlistContent.locator("tr", { hasText: "E2E Pending One" });
    await refreshedRow.getByRole("button", { name: "Open waitlist actions for E2E Pending One" }).click();
    await expect(refreshedRow.getByLabel("Ticket type")).toBeDisabled();
    await expect(refreshedRow.locator("[data-waitlist-invite-ticket-submit]")).toBeDisabled();
    await expect(refreshedRow.locator("[data-waitlist-invite-ticket-empty]")).toBeVisible();
  });

  test("organizer stays on the last waitlist page after inviting its only entry", async ({
    organizerGroupPage,
  }) => {
    const inviteUrl = `/dashboard/group/events/${TEST_WAITLIST_INVITE_EVENT.id}/attendees/invite`;

    try {
      // Load the last one-entry page of the invite lab sorted by name.
      const waitlistContent = await openWaitlistTab(
        organizerGroupPage,
        TEST_WAITLIST_INVITE_EVENT.name,
        TEST_WAITLIST_INVITE_EVENT.id,
        { query: "?limit=1&offset=2&sort=name-asc" },
      );
      const expiredRow = waitlistContent.locator("tr", { hasText: "E2E Pending Two" });
      await expect(expiredRow).toBeVisible();
      await expect(waitlistContent).toContainText(/3 - 3 of\s+3\s+waitlist entry/);

      // Invite the only entry on the last page.
      await expiredRow.getByRole("button", { name: "Open waitlist actions for E2E Pending Two" }).click();
      await expect(expiredRow.getByLabel("Ticket type")).toHaveValue(
        TEST_WAITLIST_INVITE_EVENT.inviteTicketTypeId,
      );
      const refreshAfterInvite = waitForWaitlistRefresh(organizerGroupPage, TEST_WAITLIST_INVITE_EVENT.id);
      await waitForActionResponse(
        organizerGroupPage,
        () => expiredRow.locator("[data-waitlist-invite-ticket-submit]").click(),
        {
          method: "POST",
          urlIncludes: inviteUrl,
          status: 201,
        },
      );
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Invitation sent.");
      await organizerGroupPage.getByRole("button", { name: "OK" }).click();

      // Verify the stale offset refresh lands on the new last page instead of an empty one.
      const refreshResponse = await refreshAfterInvite;
      await waitForHtmxSettle(organizerGroupPage);
      expect(new URL(refreshResponse.url()).searchParams.get("offset")).toBe("2");
      await expect(expiredRow).toHaveCount(0);
      await expect(waitlistContent.locator("tr", { hasText: "E2E Pending One" })).toBeVisible();
      await expect(waitlistContent).toContainText(/2 - 2 of\s+2\s+waitlist entry/);
      await expect(waitlistContent.locator("#waitlist-refresh")).toHaveAttribute(
        "hx-get",
        /[?&]offset=1(&|$)/,
      );
    } finally {
      restoreWaitlistInviteFixtures();
    }
  });

  test("organizer sees a lapsed waitlist offer again after canceling the attendance that hid it", async ({
    notifications,
    organizerGroupPage,
    owned,
  }) => {
    // Seed a declined waitlist offer hidden by the same user's later attendance. Owned cleanups
    // run in reverse: the attendee, then the invite lab offers.
    owned.defer(restoreWaitlistInviteFixtures);
    queryE2eDatabase(`
      insert into admission_offer (
        created_at,
        event_id,
        event_ticket_type_id,
        expires_at,
        source,
        status,
        user_id
      ) values (
        current_timestamp - interval '2 days',
        '${TEST_WAITLIST_INVITE_EVENT.id}',
        '${TEST_WAITLIST_INVITE_EVENT.queuedTicketTypeId}',
        current_timestamp - interval '1 day',
        'waitlist',
        'declined',
        '${TEST_USER_IDS.member2}'
      );
    `);
    owned.attendee({
      eventId: TEST_WAITLIST_INVITE_EVENT.id,
      userId: TEST_USER_IDS.member2,
    });

    // Verify the active attendance hides the lapsed waitlist offer.
    const waitlistContent = await openWaitlistTab(
      organizerGroupPage,
      TEST_WAITLIST_INVITE_EVENT.name,
      TEST_WAITLIST_INVITE_EVENT.id,
    );
    const waitlistRow = waitlistContent.locator("tr", { hasText: "E2E Member Two" });
    await expect(waitlistContent.locator("tr", { hasText: "E2E Pending Two" })).toBeVisible();
    await expect(waitlistRow).toHaveCount(0);

    // Open the attendance row from the same event editor.
    const attendeesContent = await openCurrentEventEditorSection(
      organizerGroupPage,
      TEST_WAITLIST_INVITE_EVENT.id,
      "attendees",
      "#attendees-content",
      { tableName: "Attendees list" },
    );
    const attendeeRow = attendeesContent.locator("tr", { hasText: "E2E Member Two" });
    const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");
    await expect(attendeeRow).toBeVisible();
    await rowActionsMenu.locator("summary").click();
    await rowActionsMenu.getByRole("menuitem", { name: "Cancel attendance" }).click();

    // Cancel the attendance and wait for the hidden waitlist tab to refresh.
    const refreshAfterCancel = waitForWaitlistRefresh(organizerGroupPage, TEST_WAITLIST_INVITE_EVENT.id);
    await waitForActionResponse(
      organizerGroupPage,
      () => confirmAlert(organizerGroupPage, { message: "Are you sure you want to cancel this attendance?" }),
      {
        method: "DELETE",
        status: 204,
        urlIncludes: `/dashboard/group/events/${TEST_WAITLIST_INVITE_EVENT.id}/attendees/${TEST_USER_IDS.member2}`,
        urlEndsWith: "/attendance",
      },
    );
    notifications.expectNew([{ kind: "event-attendance-canceled", userIds: [TEST_USER_IDS.member2] }]);
    await dismissAlert(organizerGroupPage, { message: "Attendance canceled." });
    await refreshAfterCancel;
    await waitForHtmxSettle(organizerGroupPage);

    // Return to the already loaded waitlist tab and verify the offer is back.
    await organizerGroupPage.locator('button[data-section="waitlist"]').click();
    await expect(waitlistRow).toBeVisible();
    await expect(waitlistRow).toContainText("Offer declined");
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
    // Load the seeded waitlist as a read-only viewer and target its entry.
    const waitlistContent = await openDashboardWaitlist(groupViewerPage);
    const waitlistRow = waitlistContent.locator("tr", {
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

/** Opens an event's waitlist tab from the requested dashboard event list. */
const openWaitlistTab = (page, eventName, eventId, { past = false, query = "" } = {}) =>
  openEventSection(page, {
    contentSelector: "#waitlist-content",
    eventId,
    eventName,
    eventsTab: past ? "past" : "upcoming",
    query,
    section: "waitlist",
    tableName: "Waitlist entries",
  });

/**
 * Fills the only seat and queues a member on a disabled waitlist event.
 * The full tier keeps the enrollment worker from promoting the queued member.
 * @param {{ eventId: string, ticketTypeIds: Record<string, string> }} event - Owned event.
 */
const queueDisabledWaitlistMember = (event) => {
  holdSeat(event, "general", TEST_USER_IDS.admin1);
  setupTicketWaitlistEntry({
    eventId: event.eventId,
    ticketTypeId: event.ticketTypeIds.general,
    userId: TEST_USER_IDS.member2,
  });
};

/**
 * Removes the queued member from a disabled waitlist event.
 * @param {{ eventId: string }} event - Owned event.
 */
const removeDisabledWaitlistMember = (event) => {
  queryE2eDatabase(`
    delete from event_waitlist
    where event_id = '${event.eventId}'
    and user_id = '${TEST_USER_IDS.member2}';
  `);
};

/** Restores the invite lab waitlist fixtures mutated by organizer invitations. */
const restoreWaitlistInviteFixtures = () => {
  queryE2eDatabase(`
    delete from admission_offer
    where event_id = '${TEST_WAITLIST_INVITE_EVENT.id}'
    and admission_offer_id not in (
      '${TEST_WAITLIST_INVITE_EVENT.expiredOfferId}',
      '${TEST_WAITLIST_INVITE_EVENT.claimedOfferId}',
      '${TEST_WAITLIST_INVITE_EVENT.queuedEarlierOfferId}',
      '${TEST_WAITLIST_INVITE_EVENT.claimedEarlierOfferId}'
    );

    insert into event_waitlist (event_id, event_ticket_type_id, user_id)
    values (
      '${TEST_WAITLIST_INVITE_EVENT.id}',
      '${TEST_WAITLIST_INVITE_EVENT.queuedTicketTypeId}',
      '${TEST_USER_IDS.pending1}'
    )
    on conflict do nothing;
  `);
};

/**
 * Creates a one-seat event whose waitlist is disabled, deleted at owned teardown.
 * @param {{ track: Function }} owned - Owned data registry of the test.
 * @returns {{ eventId: string, name: string, ticketTypeIds: Record<string, string> }}
 */
const setupDisabledWaitlistEvent = (owned) =>
  owned.track(
    setupTicketAllocationEvent({
      groupId: TEST_GROUP_IDS.community1.alpha,
      ticketTypes: [{ key: "general", seats: 1, title: "General admission" }],
    }),
    ({ eventId }) => cleanupEventsByIds([eventId]),
  );

/** Returns a promise for the waitlist table refresh triggered by a completed action. */
const waitForWaitlistRefresh = (page, eventId) =>
  waitForResponseMatching(page, {
    method: "GET",
    pathname: `/dashboard/group/events/${eventId}/waitlist`,
    status: 200,
  });
