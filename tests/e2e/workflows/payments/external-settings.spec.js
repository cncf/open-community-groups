import { expect, test } from "../../fixtures.js";

import { queryE2eDatabase } from "../../database.js";
import { TEST_EXTERNAL_PAYMENT_EVENTS, TEST_USER_IDS } from "../../seed.js";
import { getAttendButton } from "../../site/event/helpers.js";
import { navigateToPath, waitForActionResponse } from "../../utils.js";
import {
  EXTERNAL_GROUP_ID,
  dismissAlert,
  getCheckoutButton,
  getTicketModal,
  markExternalPurchasePaid,
  openExternalEvent,
  resetExternalPaymentFixtures,
  startExternalCheckout,
} from "./external-helpers.js";

test.describe("external payment settings", () => {
  test.describe.configure({ mode: "serial" });

  test.beforeEach(() => {
    resetExternalPaymentFixtures();
  });

  test("stops new sales after eligibility loss and preserves existing holds", async ({
    member1Page,
    member2Page,
    organizerExternalGroupPage,
  }) => {
    const event = TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle;

    // Create a valid hold before removing the group's country from the allowlist.
    await startExternalCheckout(member1Page, event);
    queryE2eDatabase("select sync_external_payments_config(array['CA']::text[], 72, 336);");

    try {
      // Verify eligibility loss rejects new paid registrations with actionable feedback.
      await openExternalEvent(member2Page, event);
      await getAttendButton(member2Page).click();
      const ticketModal = getTicketModal(member2Page);
      const ticketOptionSelector = `[data-attendance-role="ticket-type-option"][value="${event.ticketTypeId}"]`;
      await ticketModal.locator(ticketOptionSelector).locator("..").click();
      const checkoutResponse = await waitForActionResponse(
        member2Page,
        () => getCheckoutButton(member2Page).click(),
        {
          method: "POST",
          status: 409,
          urlIncludes: `/event/${event.id}/checkout`,
        },
      );
      expect(await checkoutResponse.json()).toEqual({ conflict: "payment-setup-unavailable" });
      await expect(ticketModal).toBeHidden();
      await expect(member2Page.locator(".swal2-popup")).toContainText(
        "Payment is temporarily unavailable for this ticket. Try again later or contact the organizer.",
      );
      await dismissAlert(member2Page);

      // Verify group settings explain the ineligible payment state.
      await navigateToPath(organizerExternalGroupPage, "/dashboard/group?tab=settings");
      await expect(organizerExternalGroupPage.getByRole("note")).toContainText(
        "External payments are not available for groups located in United States.",
      );

      // Confirm an existing external hold remains recoverable by the organizer.
      await markExternalPurchasePaid(
        organizerExternalGroupPage,
        event,
        "E2E Member One",
        "Existing hold confirmed after eligibility loss",
      );
      expect(
        queryE2eDatabase(`
          select status from event_purchase
          where event_id = '${event.id}' and user_id = '${TEST_USER_IDS.member1}';
        `),
      ).toBe("completed");
    } finally {
      // Restore operator eligibility for the remaining serial journeys.
      queryE2eDatabase("select sync_external_payments_config(array['US']::text[], 72, 336);");
    }
  });

  test("shows external payment eligibility through the settings toggle", async ({
    organizerExternalGroupPage,
  }) => {
    const settingsPath = "/dashboard/group?tab=settings";
    const toggleName = "Collect ticket payments outside this platform";

    try {
      // Eligible groups receive the active toggle and its visual switch track.
      await navigateToPath(organizerExternalGroupPage, settingsPath);
      const enabledToggle = organizerExternalGroupPage.getByRole("checkbox", {
        name: toggleName,
      });
      await expect(enabledToggle).toBeChecked();
      await expect(enabledToggle).toBeEnabled();
      await expect(enabledToggle).toHaveClass(/\bsr-only\b.*\bpeer\b/u);
      await expect(enabledToggle.locator("xpath=following-sibling::div[1]")).toBeVisible();
      const legalName = organizerExternalGroupPage.getByRole("textbox", { name: /^Legal Name/u });
      await expect(legalName).toHaveValue("E2E External Payee Co");
      await expect(legalName).toBeEnabled();
      await expect(legalName).toHaveAttribute("required", "");

      // Removing the country from the allowlist leaves the toggle visible but inert.
      queryE2eDatabase("select sync_external_payments_config(array['CA']::text[], 72, 336);");
      await navigateToPath(organizerExternalGroupPage, settingsPath);
      const ineligibleToggle = organizerExternalGroupPage.getByRole("checkbox", { name: toggleName });
      await expect(ineligibleToggle).toHaveCount(1);
      await expect(ineligibleToggle).toBeChecked();
      await expect(ineligibleToggle).toBeDisabled();
      await expect(ineligibleToggle.locator("xpath=following-sibling::div[1]")).toBeVisible();
      // The legal name stays editable so an enabled legacy group can still save it.
      await expect(organizerExternalGroupPage.getByRole("textbox", { name: /^Legal Name/u })).toBeEnabled();
      const eligibilityWarning = organizerExternalGroupPage.getByRole("note");
      await expect(eligibilityWarning).toContainText(
        "External payments are not available for groups located in United States.",
      );
      await expect(eligibilityWarning).toHaveClass(/border-amber-200/u);
      await expect(eligibilityWarning).toHaveClass(/bg-amber-50/u);

      // A missing country explains that the location must be saved first.
      queryE2eDatabase(`
        update "group"
        set country_code = null, country_name = null
        where group_id = '${EXTERNAL_GROUP_ID}';
      `);
      await navigateToPath(organizerExternalGroupPage, settingsPath);
      await expect(
        organizerExternalGroupPage.getByRole("checkbox", {
          name: toggleName,
        }),
      ).toBeDisabled();
      await expect(organizerExternalGroupPage.getByRole("note")).toContainText(
        "Set the group's location above and save the settings to determine eligibility.",
      );
    } finally {
      // Restore payment eligibility and the external group location.
      queryE2eDatabase(`
        select sync_external_payments_config(array['US']::text[], 72, 336);
        update "group"
        set country_code = 'US', country_name = 'United States'
        where group_id = '${EXTERNAL_GROUP_ID}';
      `);
    }
  });

  test("warns before settings invalidate published external events", async ({
    organizerExternalGroupPage,
  }) => {
    const settingsPath = "/dashboard/group?tab=settings";
    const updateSettingsButton = organizerExternalGroupPage.getByRole("button", { name: "Update Group" });

    try {
      // Published external events prevent organizers from disabling the rail.
      await navigateToPath(organizerExternalGroupPage, settingsPath);
      await organizerExternalGroupPage
        .getByRole("checkbox", {
          name: "Collect ticket payments outside this platform",
        })
        .uncheck({ force: true });
      await waitForActionResponse(organizerExternalGroupPage, () => updateSettingsButton.click(), {
        method: "PUT",
        status: 422,
        urlIncludes: "/dashboard/group/settings/update",
      });
      await expect(organizerExternalGroupPage.locator(".swal2-popup")).toContainText(
        "external payments cannot be disabled while published external paid events are upcoming",
      );
      await dismissAlert(organizerExternalGroupPage);

      // An eligible country change still cannot strand events in another country.
      queryE2eDatabase("select sync_external_payments_config(array['US', 'CA']::text[], 72, 336);");
      await navigateToPath(organizerExternalGroupPage, settingsPath);
      // The component clears the code whenever the country name changes, so set it last.
      for (const [fieldId, value] of [
        ["group-location-search-country_name", "Canada"],
        ["group-location-search-country_code", "CA"],
      ]) {
        await organizerExternalGroupPage.locator(`#${fieldId}`).evaluate((field, nextValue) => {
          field.value = nextValue;
          field.dispatchEvent(new Event("input", { bubbles: true }));
        }, value);
      }
      await waitForActionResponse(organizerExternalGroupPage, () => updateSettingsButton.click(), {
        method: "PUT",
        status: 422,
        urlIncludes: "/dashboard/group/settings/update",
      });
      await expect(organizerExternalGroupPage.locator(".swal2-popup")).toContainText(
        "published external paid events require a venue in the group country",
      );
      await dismissAlert(organizerExternalGroupPage);
    } finally {
      // Restore the external payment allowlist.
      queryE2eDatabase("select sync_external_payments_config(array['US']::text[], 72, 336);");
    }
  });

  test("explains external cancellation and unpublish consequences", async ({
    organizerExternalGroupPage,
  }) => {
    const event = TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle;

    // Open the external event actions without changing its durable state.
    await navigateToPath(organizerExternalGroupPage, "/dashboard/group?tab=events");
    const eventRow = organizerExternalGroupPage.locator("#dashboard-content tbody tr", {
      hasText: event.name,
    });
    const actionsButton = eventRow.locator(".btn-actions");

    // Cancellation directs the organizer to return external money outside OCG.
    await actionsButton.click();
    await eventRow.locator('button[id^="cancel-event-"]').click();
    const cancellationAlert = organizerExternalGroupPage.locator(".swal2-popup");
    await expect(cancellationAlert).toContainText(
      "Any external payments already received must be returned by an organizer outside OCG.",
    );
    await cancellationAlert.getByRole("button", { name: "Keep event" }).click();
    await expect(cancellationAlert).toBeHidden();

    // Unpublishing distinguishes expiring reservations from confirmed attendees.
    await actionsButton.click();
    await eventRow.locator('button[id^="unpublish-event-"]').click();
    const unpublishAlert = organizerExternalGroupPage.locator(".swal2-popup");
    await expect(unpublishAlert).toContainText(/pending reservations?.*expire/iu);
    await expect(unpublishAlert).toContainText(/confirmed attendees?.*remain/iu);
    await unpublishAlert.getByRole("button", { name: "No" }).click();
    await expect(unpublishAlert).toBeHidden();
  });

  // Exercise copying external payment values into a blank event form.
  const copyExternalPaymentFormValues = async (organizerExternalGroupPage) => {
    // Open a blank event form in the external-payment test group.
    await organizerExternalGroupPage.setViewportSize({
      height: 900,
      width: 1600,
    });
    await navigateToPath(organizerExternalGroupPage, "/dashboard/group?tab=events");
    await organizerExternalGroupPage.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerExternalGroupPage.locator('[data-event-page="add"]')).toBeVisible();
    await organizerExternalGroupPage.locator('button[data-section="payments"]').click();
    await expect(organizerExternalGroupPage.locator('[data-content="payments"]')).toBeVisible();

    // Copy a source event from the details section and return to the payments section.
    const copyEvent = async (eventName) => {
      await organizerExternalGroupPage.locator('button[data-section="details"]').click();
      const selector = organizerExternalGroupPage.locator("event-selector");
      await selector.getByRole("button", { name: "Select event" }).click();
      await selector.getByPlaceholder("Search events").fill(eventName);
      const eventOption = selector.getByRole("button", {
        name: new RegExp(eventName, "u"),
      });
      await expect(eventOption).toBeVisible();
      await eventOption.click();
      await expect(selector.getByRole("button", { name: "Select event" })).toContainText(eventName);
      await organizerExternalGroupPage.locator('button[data-section="payments"]').click();
      await expect(organizerExternalGroupPage.locator('[data-content="payments"]')).toBeVisible();
    };

    const externalUrl = organizerExternalGroupPage.locator("#external_payment_url");
    const externalInstructions = organizerExternalGroupPage.locator("#external_payment_instructions");
    const externalWindow = organizerExternalGroupPage.locator("#external_payment_window_hours");
    const paymentCurrency = organizerExternalGroupPage.locator("#payment_currency_code");

    // Verify the destination form starts without external-payment values.
    await expect(externalUrl).toHaveValue("");
    await expect(externalInstructions).toHaveValue("");
    await expect(externalWindow).toHaveValue("");
    await expect(externalInstructions).toHaveCSS("resize", "vertical");

    await externalUrl.fill("https://payments.example.com/stale");
    await externalInstructions.fill("Stale instructions");
    await externalWindow.fill("96");

    // Copy an external event and replace every stale destination value.
    await copyEvent(TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle.name);
    await expect(externalUrl).toHaveValue("https://payments.example.com/external-lifecycle");
    await expect(externalInstructions).toHaveValue(
      "Include the reservation reference with the bank transfer.",
    );
    await expect(externalWindow).toHaveValue("72");
    await expect(externalWindow).toHaveAttribute("min", "1");
    await expect(externalWindow).toHaveAttribute("max", "336");
    await expect(externalUrl).toHaveJSProperty("required", true);

    // Keep the currency first, URL and window together, and instructions below.
    const [currencyBox, urlBox, windowBox, instructionsBox] = await Promise.all([
      paymentCurrency.boundingBox(),
      externalUrl.boundingBox(),
      externalWindow.boundingBox(),
      externalInstructions.boundingBox(),
    ]);
    expect(currencyBox).not.toBeNull();
    expect(urlBox).not.toBeNull();
    expect(windowBox).not.toBeNull();
    expect(instructionsBox).not.toBeNull();
    expect(currencyBox.y).toBeLessThan(urlBox.y);
    expect(Math.abs(urlBox.y - windowBox.y)).toBeLessThanOrEqual(2);
    expect(instructionsBox.y).toBeGreaterThan(urlBox.y);
    expect(instructionsBox.width).toBeGreaterThan(urlBox.width);

    // A positive copied price makes the external URL actionable validation.
    await externalUrl.fill("");
    await expect(externalUrl).toHaveJSProperty(
      "validationMessage",
      "Paid tickets require an external payment URL.",
    );
    await externalUrl.fill("https://payments.example.com/external-lifecycle");

    // Verify the values that the payments form would submit.
    const submittedExternalValues = await organizerExternalGroupPage
      .locator("#payments-form")
      .evaluate((form) => Object.fromEntries(new FormData(form)));
    expect(submittedExternalValues).toMatchObject({
      external_payment_instructions: "Include the reservation reference with the bank transfer.",
      external_payment_url: "https://payments.example.com/external-lifecycle",
      external_payment_window_hours: "72",
    });

    // Copy another external event and update all three values together.
    await copyEvent(TEST_EXTERNAL_PAYMENT_EVENTS.capacity.name);
    await expect(externalUrl).toHaveValue("https://payments.example.com/external-capacity");
    await expect(externalInstructions).toHaveValue("Complete payment before the reservation expires.");
    await expect(externalWindow).toHaveValue("24");

    // Copy a free event and clear the complete external-payment field set.
    await copyEvent(TEST_EXTERNAL_PAYMENT_EVENTS.copyFree.name);
    await expect(externalUrl).toHaveValue("");
    await expect(externalInstructions).toHaveValue("");
    await expect(externalWindow).toHaveValue("");
    await expect(externalUrl).toHaveJSProperty("required", false);
    await expect(externalUrl).toHaveJSProperty("validationMessage", "");
  };

  test("copies and clears external payment form values as one unit", async ({
    organizerExternalGroupPage,
  }) => {
    // The copy selector searches public events, which exclude seeded test events.
    const copySourceIds = [
      TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle.id,
      TEST_EXTERNAL_PAYMENT_EVENTS.capacity.id,
      TEST_EXTERNAL_PAYMENT_EVENTS.copyFree.id,
    ]
      .map((eventId) => `'${eventId}'`)
      .join(", ");
    queryE2eDatabase(`update event set test_event = false where event_id in (${copySourceIds});`);

    try {
      // Copy external payment values between source events in the blank form.
      await copyExternalPaymentFormValues(organizerExternalGroupPage);
    } finally {
      // Restore the copied source events to seeded test visibility.
      queryE2eDatabase(`update event set test_event = true where event_id in (${copySourceIds});`);
    }
  });
});
