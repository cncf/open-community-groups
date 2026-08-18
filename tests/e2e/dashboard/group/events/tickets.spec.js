import { expect, test } from "../../../fixtures.js";

import {
  E2E_MEETINGS_ENABLED,
  E2E_PAYMENTS_ENABLED,
  TEST_APPROVAL_REQUIRED_EVENT,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_REGISTRATION_WINDOW_EVENTS,
  TEST_TICKETING_EVENTS,
  TEST_USER_IDS,
  expectPaginationNavigation,
  expectTableColumnsAtViewport,
  expectTableHeaders,
  navigateToPath,
  selectTimezone,
} from "../../../utils.js";
import {
  TEST_UPLOAD_ASSET_PATHS,
  fillEventVenue,
  fillMarkdownEditor,
  fillMultipleInputs,
  uploadGalleryImages,
  uploadImageField,
} from "../../form-helpers.js";
import {
  addDiscountCode,
  openEventUpdateFormByName,
  openPaymentsSection,
} from "./helpers.js";

import {
  addTicketType,
  editTicketType,
  enableAutomaticMeetingCreation,
  expectAutomaticMeetingControls,
  expectManualMeetingFields,
  openDetailsSection,
  removeDiscountCode,
  setAutomaticMeetingCapacity,
  setCfsLabels,
  setEventPeople,
  setRegistrationQuestions,
} from "./event-form-helpers.js";

test.describe("group dashboard event Tickets tab", () => {
  test("organizer sees free-only tickets when group payments are unavailable", async ({
    organizerGroupWithoutPaymentsPage,
  }) => {
    // Open the create form for a group without payment settings.
    await navigateToPath(
      organizerGroupWithoutPaymentsPage,
      "/dashboard/group?tab=events",
    );

    // Open the create form from the dashboard content.
    const dashboardContent =
      organizerGroupWithoutPaymentsPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();

    // Verify the create form exposes free-only ticket controls.
    await expect(
      organizerGroupWithoutPaymentsPage.locator(
        'button[data-section="payments"]',
      ),
    ).toBeVisible();
    await openPaymentsSection(organizerGroupWithoutPaymentsPage);
    const createPaymentsSection = organizerGroupWithoutPaymentsPage.locator(
      '[data-content="payments"]',
    );
    await expect(
      createPaymentsSection.getByText("Tickets", { exact: true }),
    ).toHaveCount(0);
    await expect(
      createPaymentsSection.getByText("Ticket Types", { exact: true }),
    ).toBeVisible();
    await expect(
      createPaymentsSection.getByText(
        /Payments are not configured for this group/u,
      ),
    ).toHaveCount(0);
    await expect(
      organizerGroupWithoutPaymentsPage.locator("#payment_currency_code"),
    ).toHaveCount(0);
    await expect(
      organizerGroupWithoutPaymentsPage.locator("#add-ticket-type-button"),
    ).toBeEnabled();
    await expect(
      organizerGroupWithoutPaymentsPage.locator("#ticket-types-ui"),
    ).toHaveAttribute("free-only", "");
    await expect(
      organizerGroupWithoutPaymentsPage.locator("#add-discount-code-button"),
    ).toHaveCount(0);

    // Return to the events list before checking an existing event.
    await navigateToPath(
      organizerGroupWithoutPaymentsPage,
      "/dashboard/group?tab=events",
    );

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
    await expect(
      organizerGroupWithoutPaymentsPage.locator(
        'button[data-section="payments"]',
      ),
    ).toBeVisible();
    await openPaymentsSection(organizerGroupWithoutPaymentsPage);
    const updatePaymentsSection = organizerGroupWithoutPaymentsPage.locator(
      '[data-content="payments"]',
    );
    await expect(
      updatePaymentsSection.getByText("Tickets", { exact: true }),
    ).toHaveCount(0);
    await expect(
      updatePaymentsSection.getByText("Ticket Types", { exact: true }),
    ).toBeVisible();
    await expect(
      updatePaymentsSection.getByText(
        /Payments are not configured for this group/u,
      ),
    ).toHaveCount(0);
    await expect(
      organizerGroupWithoutPaymentsPage.locator("#payment_currency_code"),
    ).toHaveCount(0);
    await expect(
      organizerGroupWithoutPaymentsPage.locator("#ticket-types-ui"),
    ).toHaveAttribute("free-only", "");
    await expect(
      organizerGroupWithoutPaymentsPage.locator("#add-ticket-type-button"),
    ).toBeEnabled();
    await expect(
      organizerGroupWithoutPaymentsPage.locator("#add-discount-code-button"),
    ).toHaveCount(0);
  });

  test("organizer sees the payments tab when group payments are ready", async ({
    organizerGroupPage,
  }) => {
    // Skip payment tab coverage when the environment disables payments.
    test.skip(
      !E2E_PAYMENTS_ENABLED,
      "Payments are disabled in this environment.",
    );

    // Open the create form for a payment-ready group.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Open the create form from the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();

    // Verify the create form exposes ticketing controls.
    await expect(
      organizerGroupPage.locator('button[data-section="payments"]'),
    ).toBeVisible();
    await openPaymentsSection(organizerGroupPage);
    await expect(
      organizerGroupPage.locator("#payment_currency_code"),
    ).toBeVisible();
    await expect(
      organizerGroupPage.locator("#add-ticket-type-button"),
    ).toBeVisible();
    await expect(
      organizerGroupPage.locator("#add-discount-code-button"),
    ).toBeVisible();

    // Open an existing payment-ready event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_PAYMENT_EVENT_NAMES.draft,
      TEST_PAYMENT_EVENT_IDS.draft,
    );

    // Verify the update form keeps seeded payment values.
    await expect(
      organizerGroupPage.locator('button[data-section="payments"]'),
    ).toBeVisible();
    await openPaymentsSection(organizerGroupPage);
    await expect(
      organizerGroupPage.locator("#payment_currency_code"),
    ).toHaveValue("USD");
  });

  test("organizer sees seeded admission tiers on a payment-ready event", async ({
    organizerGroupPage,
  }) => {
    // Skip seeded paid-tier coverage when the environment disables payments.
    test.skip(
      !E2E_PAYMENTS_ENABLED,
      "Payments are disabled in this environment.",
    );

    // Open the seeded payment-ready event before checking its tiers.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_PAYMENT_EVENT_NAMES.draft,
      TEST_PAYMENT_EVENT_IDS.draft,
    );
    await openPaymentsSection(organizerGroupPage);

    // Verify seeded tier and enrollment values.
    await expect(
      organizerGroupPage.locator("#payment_currency_code"),
    ).toHaveValue("USD");
    await expect(
      organizerGroupPage.locator("#toggle_waitlist_enabled"),
    ).toBeEnabled();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue(
      "false",
    );
    await expect(
      organizerGroupPage.locator(
        '#ticket-types-ui [data-ticketing-role="table-body"]',
      ),
    ).toContainText("General admission");
    await expect(
      organizerGroupPage.locator(
        '#ticket-types-ui [data-ticketing-role="table-body"]',
      ),
    ).toContainText("Community ticket");
    await expect(
      organizerGroupPage.locator(
        '#ticket-types-ui [data-ticketing-role="table-body"]',
      ),
    ).toContainText("Backstage pass");
    await expect(
      organizerGroupPage.locator(
        '#discount-codes-ui [data-ticketing-role="table-body"]',
      ),
    ).toContainText("SAVE10");
    await expect(
      organizerGroupPage.locator(
        '#discount-codes-ui [data-ticketing-role="table-body"]',
      ),
    ).toContainText("EARLY20");
    const limitedDiscountRow = organizerGroupPage
      .locator('#discount-codes-ui [data-ticketing-role="table-body"] tr')
      .filter({ hasText: "Limited campaign" });
    await expect(
      limitedDiscountRow.getByText("0 / 1", { exact: true }).first(),
    ).toBeVisible();
  });

  test("organizer replaces a saved manual tax rate that is no longer available", async ({
    organizerGroupPage,
  }) => {
    // Skip provider-backed tax coverage when payments are disabled.
    test.skip(
      !E2E_PAYMENTS_ENABLED,
      "Payments are disabled in this environment.",
    );

    // Return one active rate while omitting the event's saved provider rate.
    await organizerGroupPage.route(
      "**/dashboard/group/events/tax-rates**",
      (route) =>
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
      (response) =>
        response.url().includes("/dashboard/group/events/tax-rates") &&
        response.ok(),
    );
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_TICKETING_EVENTS.manualTaxUnavailable.name,
      TEST_TICKETING_EVENTS.manualTaxUnavailable.id,
    );
    const taxRatesResponse = await taxRatesResponsePromise;
    await openPaymentsSection(organizerGroupPage);

    // Verify the unavailable saved selection is explicit and can be replaced.
    const manualTaxFieldset = organizerGroupPage.locator(
      "#manual-tax-rates-fieldset",
    );
    const manualTaxRateSelect = organizerGroupPage.getByLabel(
      "Manual Stripe Tax Rates",
      { exact: true },
    );
    const unavailableRateMessage = manualTaxFieldset.getByRole("status");
    const taxCalculationMode = organizerGroupPage.locator(
      "#tax_calculation_mode",
    );
    await expect(taxCalculationMode).toHaveValue("manual");
    expect(
      new URL(taxRatesResponse.url()).searchParams.get("tax_behavior"),
    ).toBe("inclusive");
    await expect(manualTaxFieldset).toHaveAttribute(
      "data-selected-rate-ids",
      '["txr_e2e_unavailable"]',
    );
    await expect(manualTaxRateSelect).toHaveValue("");
    await expect(manualTaxRateSelect).toBeEnabled();
    await expect(unavailableRateMessage).toBeVisible();
    await expect(unavailableRateMessage).toContainText(
      "A previously selected Tax Rate is inactive, missing, or belongs to another account.",
    );

    // Expose the save action and verify paid tickets reject the stale selection.
    const eventName = organizerGroupPage.locator("#name");
    await eventName.fill(`${await eventName.inputValue()} updated`);
    const updateEventButton = organizerGroupPage.locator(
      "#update-event-button",
    );
    await expect(updateEventButton).toBeVisible();
    await expect(taxCalculationMode).toHaveJSProperty(
      "validationMessage",
      "Select an available Stripe Tax Rate for paid tickets.",
    );

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
    await manualTaxRateSelect.selectOption("txr_e2e_replacement");
    await expect(manualTaxRateSelect).toHaveValue("txr_e2e_replacement");
    await expect(manualTaxRateSelect).toHaveAttribute(
      "name",
      "manual_tax_rate_ids[]",
    );
    await expect(unavailableRateMessage).toBeHidden();
    await expect(taxCalculationMode).toHaveJSProperty(
      "validationMessage",
      "",
    );

    const [updateRequest] = await Promise.all([
      organizerGroupPage.waitForRequest(
        (request) =>
          request.method() === "PUT" &&
          request.url().includes(
            `/dashboard/group/events/${TEST_TICKETING_EVENTS.manualTaxUnavailable.id}/update`,
          ),
      ),
      updateEventButton.click(),
    ]);
    const submittedForm = new URLSearchParams(updateRequest.postData() ?? "");
    expect(submittedForm.get("manual_tax_rate_ids_present")).toBe("true");
    expect(submittedForm.getAll("manual_tax_rate_ids[]")).toEqual([
      "txr_e2e_replacement",
    ]);
    expect(submittedForm.get("tax_behavior")).toBe("inclusive");
    expect(submittedForm.get("tax_calculation_mode")).toBe("manual");
  });

  test("ticketing tables expose every column at their responsive breakpoint", async ({
    organizerGroupPage,
  }) => {
    // Skip ticket table coverage when the environment disables payments.
    test.skip(
      !E2E_PAYMENTS_ENABLED,
      "Payments are disabled in this environment.",
    );

    // Open the seeded payment-ready event before checking table columns.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_PAYMENT_EVENT_NAMES.draft,
      TEST_PAYMENT_EVENT_IDS.draft,
    );
    await openPaymentsSection(organizerGroupPage);

    // Target both seeded ticketing tables.
    const ticketTypesTable = organizerGroupPage.locator(
      "#ticket-types-ui table",
    );
    const generalAdmissionRow = ticketTypesTable.locator("tbody tr", {
      hasText: "General admission",
    });
    const discountCodesTable = organizerGroupPage.locator(
      "#discount-codes-ui table",
    );
    const ticketTypeHeaders = ["Name", "Price", "Seats", "Status", "Actions"];
    const discountCodeHeaders = [
      "Name",
      "Redemptions",
      "Status",
      "Availability",
      "Value",
      "Code",
      "Actions",
    ];

    // Verify ticket types keep all operational columns visible at each width.
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      ticketTypesTable,
      1024,
      ["Name", "Seats", "Status", "Actions"],
      ["Price"],
    );
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      ticketTypesTable,
      1280,
      ticketTypeHeaders,
      [],
    );
    await expectTableHeaders(ticketTypesTable, ticketTypeHeaders);

    // Verify compact discount columns expand at the double-extra-large breakpoint.
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      discountCodesTable,
      1024,
      ["Name", "Availability", "Actions"],
      ["Redemptions", "Status", "Value", "Code"],
    );
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      discountCodesTable,
      1536,
      discountCodeHeaders,
      [],
    );
    await expectTableHeaders(discountCodesTable, discountCodeHeaders);

    // Verify the seeded paid tier renders its formatted price.
    await expect(generalAdmissionRow.locator("td").nth(1)).toBeVisible();
    await expect(generalAdmissionRow.locator("td").nth(1)).toContainText("$");
    await expect(generalAdmissionRow.locator("td").nth(2)).toBeVisible();
    await expect(generalAdmissionRow.locator("td").nth(3)).toBeVisible();
  });

  test("ticket removal blocks the last tier and marks editable tiers for deletion", async ({
    organizerGroupPage,
  }) => {
    test.skip(
      !E2E_PAYMENTS_ENABLED,
      "Payments are disabled in this environment.",
    );

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
    await expect(lastTierDeleteButton).toHaveAttribute(
      "title",
      "Every event needs at least one ticket type",
    );

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
});
