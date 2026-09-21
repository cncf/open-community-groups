import { expect } from "../../fixtures.js";

import { queryE2eDatabase } from "../../database.js";
import { TEST_COMMUNITY_NAME, TEST_EXTERNAL_PAYMENT_EVENTS, TEST_GROUP_SLUGS } from "../../seed.js";
import { getAttendButton, waitForAttendanceState } from "../../site/event/helpers.js";
import { navigateToEvent, navigateToPath, waitForActionResponse } from "../../utils.js";

/** Seeded external-payment group id. */
export const EXTERNAL_GROUP_ID = "44444444-4444-4444-4444-444444444448";
/** Seeded external-payment group slug. */
export const EXTERNAL_GROUP_SLUG = TEST_GROUP_SLUGS.community1.externalPayments;
// Seeded external-payment event ids used by fixture reset.
const EXTERNAL_EVENT_IDS = Object.values(TEST_EXTERNAL_PAYMENT_EVENTS).map(({ id }) => id);

/** Locates the shared checkout button used by public external-payment flows. */
export const getCheckoutButton = (page) => page.locator('[data-attendance-role="checkout-btn"]');
/** Locates the shared refund button used by public external-payment flows. */
export const getRefundButton = (page) => page.locator('[data-attendance-role="refund-btn"]');
/** Locates the shared ticket modal used by public external-payment flows. */
export const getTicketModal = (page) => page.locator('[data-attendance-role="ticket-modal"]');

/** Dismiss a visible SweetAlert and wait until it no longer blocks the page. */
export const dismissAlert = async (page) => {
  const confirmButton = page.locator(".swal2-confirm");
  if (await confirmButton.isVisible()) {
    await confirmButton.click();
    await expect(page.locator(".swal2-popup")).toBeHidden();
  }
};

/** Completes an external purchase from the organizer attendee table. */
export const markExternalPurchasePaid = async (page, event, attendeeName, note) => {
  const attendeesContent = await openAttendeesTab(page, event);
  const { dialog } = await openMarkPaidDialog(page, attendeesContent, attendeeName);
  await dialog.getByLabel("Payment details").fill(note);
  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        response.url().includes("/external-payment") &&
        response.ok(),
    ),
    page.waitForResponse(
      (response) =>
        response.request().method() === "GET" &&
        response.url().includes(`/events/${event.id}/attendees`) &&
        response.ok(),
    ),
    dialog.getByRole("button", { name: "Mark paid" }).click(),
  ]);
  await expect(dialog).toBeHidden();
};

/** Opens the mark-paid dialog for one attendee row. */
export const openMarkPaidDialog = async (page, attendeesContent, attendeeName) => {
  const attendeeRow = attendeesContent.locator("tbody tr", {
    hasText: attendeeName,
  });
  const actionsMenu = attendeeRow.locator("[data-actions-menu]");
  await actionsMenu.locator("summary").click();
  await actionsMenu.getByRole("menuitem", { name: "Mark payment received" }).click();

  const dialog = page.getByRole("dialog", { name: "Mark payment received" });
  await expect(dialog).toBeVisible();
  return { attendeeRow, dialog };
};

/** Reserves a ticket through external checkout and returns the server response. */
export const startExternalCheckout = async (page, event, discountCode = "") => {
  await openExternalEvent(page, event);
  await expect(getAttendButton(page)).toContainText("Get ticket");
  await getAttendButton(page).click();

  const ticketModal = getTicketModal(page);
  await expect(ticketModal).toBeVisible();
  const ticketOptionSelector = `[data-attendance-role="ticket-type-option"][value="${event.ticketTypeId}"]`;
  await ticketModal.locator(ticketOptionSelector).locator("..").click();
  await expect(ticketModal.locator(ticketOptionSelector)).toBeChecked();

  if (discountCode) {
    await ticketModal.locator('[data-attendance-role="discount-code-input"]').fill(discountCode);
  }

  const response = await waitForActionResponse(page, () => getCheckoutButton(page).click(), {
    method: "POST",
    urlIncludes: `/event/${event.id}/checkout`,
  });
  await expect(ticketModal).toBeHidden();

  return response;
};

/** Opens an event's attendees section from the desktop group dashboard. */
export const openAttendeesTab = async (page, event) => {
  await navigateToPath(page, "/dashboard/group?tab=events");
  const eventRow = page.locator("#dashboard-content tbody tr", {
    hasText: event.name,
  });
  await expect(eventRow).toBeVisible();
  await waitForActionResponse(page, () => eventRow.locator('button[aria-label^="Edit event:"]').click(), {
    method: "GET",
    urlIncludes: `/dashboard/group/events/${event.id}/update`,
  });
  const attendeesTab = page.locator('button[data-section="attendees"]');
  const openAttendeesSection = async () => {
    if (await attendeesTab.isVisible()) {
      await attendeesTab.click();
      return;
    }

    await page.locator("[data-section-select]").selectOption("attendees");
  };
  await waitForActionResponse(page, openAttendeesSection, {
    method: "GET",
    urlIncludes: `/dashboard/group/events/${event.id}/attendees`,
  });

  const attendeesContent = page.locator("#attendees-content");
  await expect(attendeesContent.getByRole("table", { name: "Attendees list" })).toBeVisible();
  return attendeesContent;
};

/** Opens a seeded external-payment event and waits for its attendance controls. */
export const openExternalEvent = async (page, event) => {
  await navigateToEvent(page, TEST_COMMUNITY_NAME, EXTERNAL_GROUP_SLUG, event.slug);
  await waitForAttendanceState(page);
};

/** Restores the external-payment configuration and clears mutable journey state. */
export const resetExternalPaymentFixtures = () => {
  const eventIds = EXTERNAL_EVENT_IDS.map((eventId) => `'${eventId}'`).join(", ");

  queryE2eDatabase(`
    select sync_external_payments_config(array['US']::text[], 72, 336);

    delete from event_purchase_refund
    where event_purchase_id in (
      select event_purchase_id from event_purchase where event_id in (${eventIds})
    );

    delete from event_refund_request
    where event_purchase_id in (
      select event_purchase_id from event_purchase where event_id in (${eventIds})
    );

    delete from event_attendee where event_id in (${eventIds});
    delete from event_purchase where event_id in (${eventIds});
    delete from admission_offer where event_id in (${eventIds});
    delete from event_invitation_request where event_id in (${eventIds});

    update "group"
    set
      active = true,
      city = 'New York',
      country_code = 'US',
      country_name = 'United States',
      external_payments_enabled = true,
      external_payments_seller_display_name = 'E2E External Payee Co',
      payment_recipient = null
    where group_id = '${EXTERNAL_GROUP_ID}';

    update event
    set
      canceled = false,
      deleted = false,
      published = true
    where event_id in (${eventIds});

    update event
    set
      external_payment_url = case event_id
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle.id}'
          then 'https://payments.example.com/external-lifecycle'
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.capacity.id}'
          then 'https://payments.example.com/external-capacity'
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.invitation.id}'
          then 'https://payments.example.com/external-invitation'
        else null
      end,
      external_payment_instructions = case event_id
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle.id}'
          then 'Include the reservation reference with the bank transfer.'
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.capacity.id}'
          then 'Complete payment before the reservation expires.'
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.invitation.id}'
          then 'Use the invitation reference when sending payment.'
        else null
      end,
      external_payment_window_hours = case event_id
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle.id}' then 72
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.capacity.id}' then 24
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.invitation.id}' then 48
        else null
      end
    where event_id in (${eventIds});

    update event_discount_code
    set available = null, available_override_active = false
    where event_id = '${TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle.id}';
  `);
};
