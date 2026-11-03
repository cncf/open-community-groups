import { expect, test } from "../../fixtures.js";

import { queryE2eDatabase, queryE2eDatabaseRows } from "../../database.js";
import { cleanupEventsByIds } from "../../data-graphs/events.js";
import { fillEventVenue, fillMarkdownEditor } from "../../dashboard/form-helpers.js";
import {
  addDiscountCode,
  openPaymentsSection,
  waitForEventEditorAfterSave,
} from "../../dashboard/group/events/helpers.js";
import {
  addTicketType,
  editTicketType,
  openAddEventForm,
} from "../../dashboard/group/events/event-form-helpers.js";
import { TEST_COMMUNITY_IDS, TEST_EVENT_CATEGORY_IDS, TEST_GROUP_NAMES } from "../../seed.js";
import { futureDate, selectTimezone, uniqueName, waitForActionResponse } from "../../utils.js";
import { EXTERNAL_GROUP_ID, resetExternalPaymentFixtures } from "./external-helpers.js";

// Event timezone whose wall-clock times the price windows must keep.
const EVENT_TIMEZONE = "America/New_York";

test.describe("external payment event editor", () => {
  test.beforeEach(() => {
    resetExternalPaymentFixtures();
  });

  test("organizer saves a paid external event and updates its ticketing", async ({
    notifications,
    organizerExternalGroupPage,
    owned,
  }) => {
    const eventName = uniqueName("External Paid Event");
    const earlyWindowEndsAt = futureDate({ days: 200, hour: 23, minute: 59 });
    const regularWindowStartsAt = futureDate({ days: 201, hour: 0 });
    const externalPaymentUrl = "https://payments.example.com/external-editor";
    const externalPaymentInstructions = "Send the reservation reference with the bank transfer.";

    // Fill the core details of a non-test hybrid event.
    await openAddEventForm(organizerExternalGroupPage);
    await organizerExternalGroupPage.locator("#name").fill(eventName);
    await organizerExternalGroupPage.locator("#kind_id").selectOption("hybrid");
    await organizerExternalGroupPage.locator("#category_id").selectOption(TEST_EVENT_CATEGORY_IDS.general);
    await organizerExternalGroupPage
      .locator("#description_short")
      .fill("Paid external event saved through the editor.");
    await fillMarkdownEditor(
      organizerExternalGroupPage,
      "description",
      "Paid external event created by the e2e suite.",
    );
    await expect(organizerExternalGroupPage.locator("#toggle_test_event")).not.toBeChecked();

    // Schedule the event in New York and place it at a complete US venue.
    await organizerExternalGroupPage.locator('button[data-section="date-venue"]').click();
    await selectTimezone(organizerExternalGroupPage, EVENT_TIMEZONE);
    await organizerExternalGroupPage.locator("#starts_at").fill(futureDate({ days: 260, hour: 18 }));
    await organizerExternalGroupPage.locator("#ends_at").fill(futureDate({ days: 260, hour: 21 }));
    await fillEventVenue(organizerExternalGroupPage, {
      address: "200 External Way",
      city: "New York",
      countryCode: "US",
      countryName: "United States",
      latitude: "40.7128",
      longitude: "-74.006",
      name: "External Payments Hall",
      state: "New York",
      stateCode: "NY",
      zipCode: "10001",
    });

    // Configure the currency and the external payment details.
    await openPaymentsSection(organizerExternalGroupPage);
    await organizerExternalGroupPage.locator("#payment_currency_code").selectOption("USD");
    await organizerExternalGroupPage.locator("#external_payment_url").fill(externalPaymentUrl);
    await organizerExternalGroupPage.locator("#external_payment_window_hours").fill("48");
    await organizerExternalGroupPage
      .locator("#external_payment_instructions")
      .fill(externalPaymentInstructions);

    // Replace the default free tier with two paid tiers, the first with two price windows.
    await addTicketType(organizerExternalGroupPage, {
      description: "Early bird, then regular pricing.",
      priceWindows: [
        { amount: "25.00", endsAt: earlyWindowEndsAt },
        { amount: "35.50", startsAt: regularWindowStartsAt },
      ],
      seatsTotal: "40",
      title: "Standard pass",
    });
    await addTicketType(organizerExternalGroupPage, {
      description: "Reserved front-row seating.",
      priceWindows: [{ amount: "120.00" }],
      seatsTotal: "10",
      title: "VIP pass",
    });
    const defaultTierRow = organizerExternalGroupPage
      .locator('#ticket-types-ui [data-ticketing-role="table-body"] tr')
      .filter({ hasText: "General Admission" });
    await defaultTierRow.getByTitle("Delete").click();
    await expect(defaultTierRow).toHaveCount(0);

    // Add a fixed and a percentage discount code.
    await addDiscountCode(organizerExternalGroupPage, {
      amount: "5.00",
      code: "SAVE5",
      kind: "fixed_amount",
      title: "Five off",
    });
    await addDiscountCode(organizerExternalGroupPage, {
      code: "EARLY15",
      kind: "percentage",
      percentage: "15",
      title: "Early supporter",
      totalAvailable: "20",
    });

    // Create the event once client validation for paid tickets passes.
    await waitForActionResponse(
      organizerExternalGroupPage,
      () =>
        organizerExternalGroupPage.locator("#pending-changes-alert:not(.hidden) #add-event-button").click(),
      { method: "POST", status: 201, urlIncludes: "/dashboard/group/events/add" },
    );
    const eventId = await waitForEventEditorAfterSave(organizerExternalGroupPage);
    owned.defer(() => cleanupEventsByIds([eventId]));

    // Verify the event, its ordered tiers in minor units and local wall-clock times, and codes.
    expect(readExternalEventConfiguration(eventId)).toEqual({
      discount_codes: [
        {
          amount_minor: null,
          code: "EARLY15",
          kind: "percentage",
          percentage: 15,
          title: "Early supporter",
          total_available: 20,
        },
        {
          amount_minor: 500,
          code: "SAVE5",
          kind: "fixed_amount",
          percentage: null,
          title: "Five off",
          total_available: null,
        },
      ],
      event: {
        external_payment_instructions: externalPaymentInstructions,
        external_payment_url: externalPaymentUrl,
        external_payment_window_hours: 48,
        group_id: EXTERNAL_GROUP_ID,
        kind: "hybrid",
        payment_currency_code: "USD",
        test_event: false,
        timezone: EVENT_TIMEZONE,
        venue_country_code: "US",
      },
      ticket_types: [
        {
          order: 1,
          price_windows: [
            { amount_minor: 2500, ends_at: earlyWindowEndsAt, starts_at: null },
            {
              amount_minor: 3550,
              ends_at: null,
              starts_at: regularWindowStartsAt,
            },
          ],
          seats_total: 40,
          title: "Standard pass",
        },
        {
          order: 2,
          price_windows: [{ amount_minor: 12000, ends_at: null, starts_at: null }],
          seats_total: 10,
          title: "VIP pass",
        },
      ],
    });

    // Verify every community admin was told about the new paid external event.
    const communityAdminIds = listCommunityAdminIds();
    expect(communityAdminIds.length).toBeGreaterThan(0);
    notifications.expectNew([
      {
        kind: "event-paid-configured",
        templateDataContains: {
          event_count: 1,
          events: [
            {
              event_id: eventId,
              has_external_payment: true,
              name: eventName,
              timezone: EVENT_TIMEZONE,
            },
          ],
          group_name: TEST_GROUP_NAMES.externalPayments,
        },
        userIds: communityAdminIds,
      },
    ]);

    // Change the payment window and a tier's seats on the saved event.
    const updateCheckpoint = notifications.checkpoint();
    await openPaymentsSection(organizerExternalGroupPage);
    await organizerExternalGroupPage.locator("#external_payment_window_hours").fill("96");
    await editTicketType(organizerExternalGroupPage, "VIP pass", {
      description: "Reserved front-row seating.",
      seatsTotal: "15",
      title: "VIP pass",
    });
    await waitForEventEditorAfterSave(
      organizerExternalGroupPage,
      () => organizerExternalGroupPage.locator("#update-event-button").click(),
      {
        eventId,
        method: "PUT",
        urlIncludes: `/dashboard/group/events/${eventId}/update`,
      },
    );

    // Verify the update persisted without notifying admins again.
    const updatedConfiguration = readExternalEventConfiguration(eventId);
    expect(updatedConfiguration.event.external_payment_window_hours).toBe(96);
    expect(
      updatedConfiguration.ticket_types.map(({ seats_total, title }) => ({
        seats_total,
        title,
      })),
    ).toEqual([
      { seats_total: 40, title: "Standard pass" },
      { seats_total: 15, title: "VIP pass" },
    ]);
    notifications.expectNew([], { since: updateCheckpoint });
  });
});

/** Returns the community admins that paid-event notifications fan out to. */
function listCommunityAdminIds() {
  return queryE2eDatabaseRows(
    `select unnest(list_community_admin_ids('${TEST_COMMUNITY_IDS.community1}'))`,
  ).map(([userId]) => userId);
}

/**
 * Reads the persisted external ticketing configuration of an event. Price window times are
 * rendered as `datetime-local` values in the event timezone.
 */
function readExternalEventConfiguration(eventId) {
  return JSON.parse(
    queryE2eDatabase(`
      select jsonb_build_object(
        'discount_codes', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'amount_minor', dc.amount_minor,
            'code', dc.code,
            'kind', dc.kind,
            'percentage', dc.percentage,
            'title', dc.title,
            'total_available', dc.total_available
          ) order by dc.code collate "C"), '[]'::jsonb)
          from event_discount_code dc
          where dc.event_id = e.event_id
        ),
        'event', jsonb_build_object(
          'external_payment_instructions', e.external_payment_instructions,
          'external_payment_url', e.external_payment_url,
          'external_payment_window_hours', e.external_payment_window_hours,
          'group_id', e.group_id,
          'kind', e.event_kind_id,
          'payment_currency_code', e.payment_currency_code,
          'test_event', e.test_event,
          'timezone', e.timezone,
          'venue_country_code', e.venue_country_code
        ),
        'ticket_types', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'order', tt."order",
            'price_windows', (
              select coalesce(jsonb_agg(jsonb_build_object(
                'amount_minor', pw.amount_minor,
                'ends_at', to_char(pw.ends_at at time zone e.timezone, 'YYYY-MM-DD"T"HH24:MI'),
                'starts_at', to_char(pw.starts_at at time zone e.timezone, 'YYYY-MM-DD"T"HH24:MI')
              ) order by pw.starts_at nulls first, pw.ends_at), '[]'::jsonb)
              from event_ticket_price_window pw
              where pw.event_ticket_type_id = tt.event_ticket_type_id
            ),
            'seats_total', tt.seats_total,
            'title', tt.title
          ) order by tt."order"), '[]'::jsonb)
          from event_ticket_type tt
          where tt.event_id = e.event_id
        )
      )::text
      from event e
      where e.event_id = '${eventId}'
    `),
  );
}
