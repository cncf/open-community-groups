import { expect, test } from "../../../fixtures.js";
import { TEST_PAYMENT_EVENT_IDS, TEST_PAYMENT_EVENT_NAMES, TEST_TICKETING_EVENTS } from "../../../seed.js";
import { queryE2eDatabase } from "../../../database.js";
import { navigateToPath, selectTimezone, uniqueName } from "../../../utils.js";
import { fillEventVenue, fillMarkdownEditor } from "../../form-helpers.js";
import {
  addDiscountCode,
  openEventUpdateFormByName,
  openPaymentsSection,
  waitForEventEditorAfterSave,
} from "./helpers.js";
import {
  addTicketType,
  editTicketType,
  enableAutomaticMeetingCreation,
  openDetailsSection,
  setAutomaticMeetingCapacity,
} from "./event-form-helpers.js";

test.describe("group dashboard event Tickets tab", () => {
  test("organizer sees free-only tickets when group payments are unavailable", async ({
    organizerGroupWithoutPaymentsPage,
  }) => {
    // Open the create form for a group without payment settings.
    await navigateToPath(organizerGroupWithoutPaymentsPage, "/dashboard/group?tab=events");

    // Open the create form from the dashboard content.
    const dashboardContent = organizerGroupWithoutPaymentsPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();

    // Verify the create form exposes free-only ticket controls.
    await expect(organizerGroupWithoutPaymentsPage.locator('button[data-section="payments"]')).toBeVisible();
    await openPaymentsSection(organizerGroupWithoutPaymentsPage);
    const createPaymentsSection = organizerGroupWithoutPaymentsPage.locator('[data-content="payments"]');
    await expect(createPaymentsSection.getByText("Tickets", { exact: true })).toHaveCount(0);
    await expect(createPaymentsSection.getByText("Ticket Types", { exact: true })).toBeVisible();
    await expect(createPaymentsSection.getByText(/Payments are not configured for this group/u)).toHaveCount(
      0,
    );
    await expect(organizerGroupWithoutPaymentsPage.locator("#payment_currency_code")).toHaveCount(0);
    await expect(organizerGroupWithoutPaymentsPage.locator("#add-ticket-type-button")).toBeEnabled();
    await expect(organizerGroupWithoutPaymentsPage.locator("#ticket-types-ui")).toHaveAttribute(
      "free-only",
      "",
    );
    await expect(organizerGroupWithoutPaymentsPage.locator("#add-discount-code-button")).toHaveCount(0);

    // Return to the events list before checking an existing event.
    await navigateToPath(organizerGroupWithoutPaymentsPage, "/dashboard/group?tab=events");

    // Open an existing event for a group without payment settings.
    const eventRow = dashboardContent.locator("tr", {
      hasText: "Delta Event Two",
    });
    await expect(eventRow).toBeVisible();

    // Open the existing event and wait for update content.
    await Promise.all([
      organizerGroupWithoutPaymentsPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/dashboard/group/events/") &&
          response.url().includes("/update") &&
          response.ok(),
      ),
      eventRow.locator('td button[aria-label^="Edit event:"]').click(),
    ]);

    // Verify the update form exposes free-only ticket controls.
    await expect(organizerGroupWithoutPaymentsPage.locator('button[data-section="payments"]')).toBeVisible();
    await openPaymentsSection(organizerGroupWithoutPaymentsPage);
    const updatePaymentsSection = organizerGroupWithoutPaymentsPage.locator('[data-content="payments"]');
    await expect(updatePaymentsSection.getByText("Tickets", { exact: true })).toHaveCount(0);
    await expect(updatePaymentsSection.getByText("Ticket Types", { exact: true })).toBeVisible();
    await expect(updatePaymentsSection.getByText(/Payments are not configured for this group/u)).toHaveCount(
      0,
    );
    await expect(organizerGroupWithoutPaymentsPage.locator("#payment_currency_code")).toHaveCount(0);
    await expect(organizerGroupWithoutPaymentsPage.locator("#ticket-types-ui")).toHaveAttribute(
      "free-only",
      "",
    );
    await expect(organizerGroupWithoutPaymentsPage.locator("#add-ticket-type-button")).toBeEnabled();
    await expect(organizerGroupWithoutPaymentsPage.locator("#add-discount-code-button")).toHaveCount(0);
  });

  test("organizer sees the payments tab when group payments are ready", async ({ organizerGroupPage }) => {
    // Open the create form for a payment-ready group.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Open the create form from the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();

    // Verify the create form exposes ticketing controls.
    await expect(organizerGroupPage.locator('button[data-section="payments"]')).toBeVisible();
    await openPaymentsSection(organizerGroupPage);
    await expect(organizerGroupPage.locator("#payment_currency_code")).toBeVisible();
    await expect(organizerGroupPage.locator("#add-ticket-type-button")).toBeVisible();
    await expect(organizerGroupPage.locator("#add-discount-code-button")).toBeVisible();

    // Open an existing payment-ready event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_PAYMENT_EVENT_NAMES.draft,
      TEST_PAYMENT_EVENT_IDS.draft,
    );

    // Verify the update form keeps seeded payment values.
    await expect(organizerGroupPage.locator('button[data-section="payments"]')).toBeVisible();
    await openPaymentsSection(organizerGroupPage);
    await expect(organizerGroupPage.locator("#payment_currency_code")).toHaveValue("USD");
  });

  test("organizer sees seeded admission tiers on a payment-ready event", async ({ organizerGroupPage }) => {
    // Open the seeded payment-ready event before checking its tiers.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_PAYMENT_EVENT_NAMES.draft,
      TEST_PAYMENT_EVENT_IDS.draft,
    );
    await openPaymentsSection(organizerGroupPage);

    // Verify seeded tier and enrollment values.
    await expect(organizerGroupPage.locator("#payment_currency_code")).toHaveValue("USD");
    await expect(organizerGroupPage.locator("#toggle_waitlist_enabled")).toBeEnabled();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("false");
    await expect(
      organizerGroupPage.locator('#ticket-types-ui [data-ticketing-role="table-body"]'),
    ).toContainText("General admission");
    await expect(
      organizerGroupPage.locator('#ticket-types-ui [data-ticketing-role="table-body"]'),
    ).toContainText("Community ticket");
    await expect(
      organizerGroupPage.locator('#ticket-types-ui [data-ticketing-role="table-body"]'),
    ).toContainText("Backstage pass");
    const generalAdmissionRow = organizerGroupPage
      .locator("#ticket-types-ui table")
      .locator("tbody tr", { hasText: "General admission" });
    await expect(generalAdmissionRow.locator("td").nth(1)).toBeVisible();
    await expect(generalAdmissionRow.locator("td").nth(1)).toContainText("$");
    await expect(generalAdmissionRow.locator("td").nth(2)).toBeVisible();
    await expect(generalAdmissionRow.locator("td").nth(3)).toBeVisible();
    await expect(
      organizerGroupPage.locator('#discount-codes-ui [data-ticketing-role="table-body"]'),
    ).toContainText("SAVE10");
    await expect(
      organizerGroupPage.locator('#discount-codes-ui [data-ticketing-role="table-body"]'),
    ).toContainText("EARLY20");
    const limitedDiscountRow = organizerGroupPage
      .locator('#discount-codes-ui [data-ticketing-role="table-body"] tr')
      .filter({ hasText: "Limited campaign" });
    await expect(limitedDiscountRow.getByText("0 / 1", { exact: true }).first()).toBeVisible();
  });

  test("unrelated edit on an event with dated ticketing saves without provider validation", async ({
    organizerGroupPage,
  }) => {
    // The seeded draft event carries dated price windows and a dated discount code, which only
    // register as a ticketing change when their timestamps are compared without normalization.
    const eventId = TEST_PAYMENT_EVENT_IDS.draft;
    const originalDescriptionShort = queryE2eDatabase(
      `select coalesce(description_short, '') from event where event_id = '${eventId}'`,
    );
    const ticketingConfigurationBefore = readTicketingConfiguration(eventId);
    const updatedDescriptionShort = uniqueName("dated ticketing round trip");

    try {
      // Open the seeded event and change a field outside the payments section.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
      await openEventUpdateFormByName(organizerGroupPage, TEST_PAYMENT_EVENT_NAMES.draft, eventId);
      await openDetailsSection(organizerGroupPage);
      await organizerGroupPage.locator("#description_short").fill(updatedDescriptionShort);

      // The save succeeds: a false ticketing change would contact the fake Stripe account and fail.
      await waitForEventEditorAfterSave(
        organizerGroupPage,
        () => organizerGroupPage.locator("#update-event-button").click(),
        { eventId, method: "PUT", urlIncludes: `/dashboard/group/events/${eventId}/update` },
      );

      // Verify the edit persisted while the ticketing configuration stayed byte-identical.
      expect(queryE2eDatabase(`select description_short from event where event_id = '${eventId}'`)).toBe(
        updatedDescriptionShort,
      );
      expect(readTicketingConfiguration(eventId)).toBe(ticketingConfigurationBefore);
    } finally {
      // Restore the original event summary without changing ticketing.
      queryE2eDatabase(
        `update event set description_short = nullif('${originalDescriptionShort}', '') where event_id = '${eventId}'`,
      );
    }
  });

  test("manual tax rate selector replaces a saved rate that is no longer available", async ({
    organizerGroupPage,
  }) => {
    // Return one active rate while omitting the event's saved provider rate.
    await organizerGroupPage.route("**/dashboard/group/events/tax-rates**", (route) =>
      route.fulfill({
        body: JSON.stringify([
          {
            display_name: "E2E replacement rate",
            id: "txr_e2e_replacement",
            inclusive: true,
            jurisdiction: "United States",
            percentage: "7.25",
          },
        ]),
        contentType: "application/json",
        status: 200,
      }),
    );

    // Open the event whose saved manual rate is absent from the provider response.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    const taxRatesResponsePromise = organizerGroupPage.waitForResponse(
      (response) => response.url().includes("/dashboard/group/events/tax-rates") && response.ok(),
    );
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_TICKETING_EVENTS.manualTaxUnavailable.name,
      TEST_TICKETING_EVENTS.manualTaxUnavailable.id,
    );
    const taxRatesResponse = await taxRatesResponsePromise;
    await openPaymentsSection(organizerGroupPage);

    // Verify the unavailable saved selection is explicit and can be replaced.
    const manualTaxFieldset = organizerGroupPage.locator("#manual-tax-rates-fieldset");
    const manualTaxRateSelect = organizerGroupPage.getByLabel("Manual Stripe Tax Rates", { exact: true });
    const unavailableRateMessage = manualTaxFieldset.getByRole("status");
    const taxCalculationMode = organizerGroupPage.locator("#tax_calculation_mode");
    await expect(taxCalculationMode).toHaveValue("manual");
    expect(new URL(taxRatesResponse.url()).searchParams.get("tax_behavior")).toBe("inclusive");
    await expect(manualTaxFieldset).toHaveAttribute("data-selected-rate-ids", '["txr_e2e_unavailable"]');
    await expect(manualTaxRateSelect).toHaveValue("");
    await expect(manualTaxRateSelect).toBeEnabled();
    await expect(unavailableRateMessage).toBeVisible();
    await expect(unavailableRateMessage).toContainText(
      "A previously selected Tax Rate is inactive, missing, or belongs to another account.",
    );

    // Complete the paid-event location requirements before testing the stale rate.
    await openDetailsSection(organizerGroupPage);
    const eventKind = organizerGroupPage.locator("#kind_id");
    await expect(eventKind).toHaveJSProperty(
      "validationMessage",
      "Paid tickets require an in-person or hybrid event.",
    );
    await eventKind.selectOption("hybrid");
    await expect(eventKind).toHaveValue("hybrid");
    await expect(eventKind).toHaveJSProperty("validationMessage", "");
    await organizerGroupPage.locator('button[data-section="date-venue"]').click({ force: true });
    await fillEventVenue(organizerGroupPage, {
      address: "123 Tax Rate Way",
      city: "New York",
      countryCode: "US",
      countryName: "United States",
      latitude: "40.7128",
      longitude: "-74.006",
      name: "Tax Rate Hall",
      state: "New York",
      stateCode: "NY",
      zipCode: "10001",
    });

    // Expose the save action and verify paid tickets reject the stale selection.
    await openDetailsSection(organizerGroupPage);
    const eventName = organizerGroupPage.locator("#name");
    await eventName.fill(`${await eventName.inputValue()} updated`);
    await openPaymentsSection(organizerGroupPage);
    const updateEventButton = organizerGroupPage.locator("#update-event-button");
    await expect(updateEventButton).toBeVisible();
    await expect(taxCalculationMode).toHaveJSProperty(
      "validationMessage",
      "Select an available Stripe Tax Rate for paid tickets.",
    );

    // Intercept the update so the test can inspect the submitted form.
    let interceptedUpdateRequest = null;
    await organizerGroupPage.route(
      `**/dashboard/group/events/${TEST_TICKETING_EVENTS.manualTaxUnavailable.id}/update`,
      async (route) => {
        if (route.request().method() !== "PUT") {
          await route.continue();
          return;
        }
        interceptedUpdateRequest = route.request();
        await route.fulfill({ status: 204 });
      },
    );
    await updateEventButton.click();
    expect(interceptedUpdateRequest).toBeNull();

    // Select the provider replacement and verify the submitted form contract.
    await openPaymentsSection(organizerGroupPage);
    await manualTaxRateSelect.selectOption("txr_e2e_replacement");
    await expect(manualTaxRateSelect).toHaveValue("txr_e2e_replacement");
    await expect(manualTaxRateSelect).toHaveAttribute("name", "manual_tax_rate_ids[]");
    await expect(unavailableRateMessage).toBeHidden();
    await expect(taxCalculationMode).toHaveJSProperty("validationMessage", "");

    // Submit the update and inspect the replacement tax rate payload.
    const [updateRequest] = await Promise.all([
      organizerGroupPage.waitForRequest(
        (request) =>
          request.method() === "PUT" &&
          request
            .url()
            .includes(`/dashboard/group/events/${TEST_TICKETING_EVENTS.manualTaxUnavailable.id}/update`),
      ),
      updateEventButton.click(),
    ]);
    const submittedForm = new URLSearchParams(updateRequest.postData() ?? "");
    expect(submittedForm.get("manual_tax_rate_ids_present")).toBe("true");
    expect(submittedForm.getAll("manual_tax_rate_ids[]")).toEqual(["txr_e2e_replacement"]);
    expect(submittedForm.get("tax_behavior")).toBe("inclusive");
    expect(submittedForm.get("tax_calculation_mode")).toBe("manual");
  });

  test("ticket removal blocks the last tier and marks editable tiers for deletion", async ({
    organizerGroupPage,
  }) => {
    // A one-tier event keeps its final ticket type in place.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_TICKETING_EVENTS.migratedCapacity.name,
      TEST_TICKETING_EVENTS.migratedCapacity.id,
    );
    await openPaymentsSection(organizerGroupPage);
    const lastTierDeleteButton = organizerGroupPage
      .locator('#ticket-types-ui [data-ticketing-role="table-body"] tr')
      .filter({ hasText: "General Admission" })
      .locator('[data-ticketing-action="delete-ticket"]');
    await expect(lastTierDeleteButton).toBeDisabled();
    await expect(lastTierDeleteButton).toHaveAttribute("title", "Every event needs at least one ticket type");

    // An editable tier can be marked for deletion without contacting the provider.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_PAYMENT_EVENT_NAMES.draft,
      TEST_PAYMENT_EVENT_IDS.draft,
    );
    await openPaymentsSection(organizerGroupPage);
    const purchasedTierRow = organizerGroupPage
      .locator('#ticket-types-ui [data-ticketing-role="table-body"] tr')
      .filter({ hasText: "General admission" });
    await purchasedTierRow.getByTitle("Delete").click();
    await expect(purchasedTierRow).toHaveCount(0);
    await expect(organizerGroupPage.locator("#update-event-button")).toBeEnabled();
  });

  test("organizer can configure paid tiers without contacting the payment provider", async ({
    organizerGroupPage,
  }) => {
    test.setTimeout(90_000);

    // Create a unique event name for the tiered payment flow.
    const eventName = uniqueName("Paid Tier Event");

    // Open the event form for a payment-ready group.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Open the create form from the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();

    // Fill the core event details.
    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage.locator("#description_short").fill("Paid dashboard event for payment coverage.");
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "Paid dashboard event used to cover admission tiers and discount codes.",
    );
    await organizerGroupPage.locator("#toggle_test_event").check({ force: true });
    await organizerGroupPage.locator("#toggle_waitlist_enabled").check({ force: true });

    // Configure a meeting-safe capacity before automatic meeting selection.
    await setAutomaticMeetingCapacity(organizerGroupPage);

    // Fill schedule and online meeting details.
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await selectTimezone(organizerGroupPage, "UTC");
    await organizerGroupPage.locator("#starts_at").fill("2030-11-12T18:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-11-12T20:00");
    await enableAutomaticMeetingCreation(organizerGroupPage);

    // Open payments before editing the default admission tier.
    await openPaymentsSection(organizerGroupPage);

    // Reuse the default tier for the free admission option.
    await editTicketType(organizerGroupPage, "General Admission", {
      title: "Free community pass",
      description: "Free tier used for zero-price coverage.",
      seatsTotal: "12",
    });

    // Verify free-only tiers need no currency and retain the waitlist setting.
    const paymentCurrencyInput = organizerGroupPage.locator("#payment_currency_code");
    await expect(paymentCurrencyInput).toHaveJSProperty("required", false);
    await expect(organizerGroupPage.locator("#toggle_waitlist_enabled")).toBeEnabled();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("true");

    // Add a paid ticket type with scheduled price windows.
    await addTicketType(organizerGroupPage, {
      title: "General admission",
      description: "Paid tier with early-bird pricing.",
      seatsTotal: "30",
      priceWindows: [
        { amount: "2500", endsAt: "2030-10-01T23:59" },
        { amount: "3000", startsAt: "2030-10-02T00:00" },
      ],
    });

    // Verify positive prices require a currency before submission.
    await expect(paymentCurrencyInput).toHaveJSProperty("required", true);
    const validationMessage = await paymentCurrencyInput.evaluate((element) => element.validationMessage);
    expect(validationMessage).toBe("Paid ticket prices require an event currency.");
    await paymentCurrencyInput.selectOption("USD");

    // Add discount codes for fixed amount and percentage coverage.
    await addDiscountCode(organizerGroupPage, {
      title: "Launch savings",
      code: "SAVE10",
      kind: "fixed_amount",
      amount: "1000",
    });
    await addDiscountCode(organizerGroupPage, {
      title: "Early supporter",
      code: "EARLY20",
      kind: "percentage",
      percentage: "20",
      totalAvailable: "50",
    });

    // Verify compact redemption summaries at the default desktop width.
    const discountCodesTable = organizerGroupPage.locator("#discount-codes-ui table");
    const redemptionsHeader = discountCodesTable.locator("thead th").nth(1);
    const unlimitedDiscountRow = discountCodesTable.locator("tbody tr", {
      hasText: "Launch savings",
    });
    const limitedDiscountRow = discountCodesTable.locator("tbody tr", {
      hasText: "Early supporter",
    });
    await expect(redemptionsHeader).toBeHidden();
    await expect(redemptionsHeader).toContainText("Redemptions");
    await expect(unlimitedDiscountRow.getByText("Unlimited", { exact: true }).first()).toBeVisible();
    await expect(limitedDiscountRow.getByText("50 max", { exact: true }).first()).toBeVisible();

    // Verify the dedicated redemption column at the widest layout.
    await organizerGroupPage.setViewportSize({ width: 1600, height: 900 });
    await expect(redemptionsHeader).toBeVisible();
    await expect(unlimitedDiscountRow.locator("td").nth(1)).toHaveText("Unlimited");
    await expect(limitedDiscountRow.locator("td").nth(1)).toHaveText("50 max");

    // Target submission while tracking whether browser validation blocks it.
    const visibleAddEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(visibleAddEventButton).toBeVisible();
    let eventAddRequests = 0;
    const countEventAddRequests = (request) => {
      if (request.method() === "POST" && request.url().includes("/dashboard/group/events/add")) {
        eventAddRequests += 1;
      }
    };
    organizerGroupPage.on("request", countEventAddRequests);

    // Verify paid tickets require an eligible event type before submission.
    await visibleAddEventButton.click();
    const eventKindInput = organizerGroupPage.locator("#kind_id");
    await expect(eventKindInput).toBeFocused();
    await expect(eventKindInput).toHaveJSProperty(
      "validationMessage",
      "Paid tickets require an in-person or hybrid event.",
    );
    await expect(organizerGroupPage.locator('button[data-section="details"]')).toHaveAttribute(
      "data-active",
      "true",
    );

    // Make the paid event hybrid and verify its physical venue is required.
    await organizerGroupPage.locator("#kind_id").selectOption("hybrid");
    await visibleAddEventButton.click();
    const venueNameInput = organizerGroupPage.locator("#location-search-venue_name");
    await expect(venueNameInput).toBeFocused();
    await expect(venueNameInput).toHaveJSProperty("validationMessage", "Paid tickets require a venue name.");
    await expect(organizerGroupPage.locator('button[data-section="date-venue"]')).toHaveAttribute(
      "data-active",
      "true",
    );

    // Keep subdivisions optional and validate every required venue field in browser order.
    await venueNameInput.fill("Hybrid Admission Hall");
    const venueStateNameInput = organizerGroupPage.locator("#location-search-venue_state_name");
    const venueStateCodeInput = organizerGroupPage.locator("#location-search-venue_state_code");
    await expect(venueStateNameInput).toHaveJSProperty("required", false);
    await expect(venueStateNameInput).toHaveJSProperty("validationMessage", "");
    await expect(venueStateCodeInput).toHaveJSProperty("required", false);
    await expect(venueStateCodeInput).toHaveJSProperty("validationMessage", "");
    const requiredVenueFields = [
      {
        input: organizerGroupPage.locator("#location-search-venue_address"),
        message: "Paid tickets require a venue address.",
        value: "123 Hybrid Way",
      },
      {
        input: organizerGroupPage.locator("#location-search-venue_city"),
        message: "Paid tickets require a venue city.",
        value: "New York",
      },
      {
        input: organizerGroupPage.locator("#location-search-venue_zip_code"),
        message: "Paid tickets require a venue postal code.",
        value: "10001",
      },
      {
        input: organizerGroupPage.locator("#location-search-venue_country_name"),
        message: "Paid tickets require a country.",
        value: "United States",
      },
      {
        input: organizerGroupPage.locator("#location-search-venue_country_code"),
        message: "Paid tickets require a country code to calculate taxes.",
        value: "US",
      },
    ];
    for (const requirement of requiredVenueFields) {
      await visibleAddEventButton.click();
      await expect(requirement.input).toBeFocused();
      await expect(requirement.input).toHaveJSProperty("validationMessage", requirement.message);
      await requirement.input.fill(requirement.value);
    }

    // Complete the venue and verify the tax controls included in the form payload.
    await fillEventVenue(organizerGroupPage, {
      address: "123 Hybrid Way",
      city: "New York",
      countryCode: "US",
      countryName: "United States",
      latitude: "40.7128",
      longitude: "-74.006",
      name: "Hybrid Admission Hall",
      state: "NY",
      stateCode: "NY",
      zipCode: "10001",
    });
    for (const requirement of [venueNameInput, ...requiredVenueFields.map(({ input }) => input)]) {
      await expect(requirement).toHaveJSProperty("validationMessage", "");
    }
    await openPaymentsSection(organizerGroupPage);
    await expect(organizerGroupPage.locator("#tax_behavior")).toHaveValue("inclusive");
    await organizerGroupPage.locator("#tax_behavior").selectOption("exclusive");
    await expect(organizerGroupPage.locator("#tax_behavior")).toHaveValue("exclusive");
    await expect(organizerGroupPage.locator("#tax_calculation_mode")).toHaveValue("automatic");

    // Client-side validation never sent an event request or contacted the provider.
    organizerGroupPage.off("request", countEventAddRequests);
    expect(eventAddRequests).toBe(0);
  });
});

/** Serializes the ticketing rows of an event (minus the always-touched `updated_at`) for equality checks. */
function readTicketingConfiguration(eventId) {
  return queryE2eDatabase(`
    select jsonb_build_object(
      'ticket_types', (
        select coalesce(jsonb_agg(to_jsonb(tt) - 'updated_at' order by tt.event_ticket_type_id), '[]'::jsonb)
        from event_ticket_type tt
        where tt.event_id = '${eventId}'
      ),
      'price_windows', (
        select coalesce(jsonb_agg(to_jsonb(pw) - 'updated_at' order by pw.event_ticket_price_window_id), '[]'::jsonb)
        from event_ticket_price_window pw
        join event_ticket_type tt on tt.event_ticket_type_id = pw.event_ticket_type_id
        where tt.event_id = '${eventId}'
      ),
      'discount_codes', (
        select coalesce(jsonb_agg(to_jsonb(dc) - 'updated_at' order by dc.event_discount_code_id), '[]'::jsonb)
        from event_discount_code dc
        where dc.event_id = '${eventId}'
      )
    )::text
  `);
}
