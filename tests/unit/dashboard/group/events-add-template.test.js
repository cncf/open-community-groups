import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch(
    "/ocg-server/templates/dashboard/group/events_add.html",
  );

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group event add template", () => {
  it("keeps the add event page at full dashboard content height", async () => {
    // Load the event add template before checking page root classes.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the add event page can fill the group dashboard content area.
    expect(template).to.include(
      'class="group/event-page grid h-full min-h-full min-w-0 grow grid-rows-[auto_minmax(0,1fr)] gap-y-8 has-[#pending-changes-alert:not(.hidden)]:grid-rows-[auto_auto_minmax(0,1fr)] lg:grid-cols-[12rem_minmax(0,1fr)] lg:gap-x-8"',
    );
    expect(template).to.include('data-event-page="add"');
    expect(template).to.include(
      '<div id="event-preview-modal-root" class="contents"></div>',
    );
    expect(template).to.include('class="col-span-full min-w-0 space-y-3"');
    expect(template).to.include('class="block min-w-0 max-w-full"');
    expect(template).to.include('class="form-legend mt-3 break-words"');
  });

  it("places the copy event selector inside details before the event name", async () => {
    // Load the event add template before checking copy selector placement.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert copying is part of details and appears before the event name field.
    const detailsFormIndex = template.indexOf('<form id="details-form">');
    const copySelectorIndex = template.indexOf(
      'button-id="copy-event-selector"',
    );
    const eventNameIndex = template.indexOf('name="name"');

    expect(detailsFormIndex).to.be.greaterThan(-1);
    expect(copySelectorIndex).to.be.greaterThan(detailsFormIndex);
    expect(eventNameIndex).to.be.greaterThan(copySelectorIndex);
  });

  it("shows a draft event title header above add tabs and content", async () => {
    // Load the event add template before checking the draft event reminder.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the draft reminder starts with clear fallback copy.
    expect(template).to.include('id="draft-event-title"');
    expect(template).to.include("Untitled event");
    expect(template).to.include('id="draft-event-date"');
    expect(template).to.include("Date not set yet");
    expect(template).to.include('class="col-span-full min-w-0"');
    expect(template).to.include('class="min-w-0 flex-1"');
    expect(template).to.include('class="mt-1 text-xs text-stone-500"');
    expect(template).to.include(
      'class="truncate text-xl font-semibold text-stone-900"',
    );
    expect(template).to.not.include("overflow-hidden");
    expect(template).to.include('class="col-span-full min-w-0 xl:col-span-3"');
    expect(template).to.include(
      'class="flex shrink-0 flex-row items-center justify-end gap-2 sm:ms-4"',
    );
    expect(template).to.include('id="event-preview-button"');
    expect(template).to.include(
      'class="group btn-primary-outline inline-flex items-center justify-center gap-2 whitespace-nowrap max-2xl:h-7 max-2xl:px-3 max-2xl:py-1 max-2xl:text-xs disabled:cursor-not-allowed disabled:opacity-50"',
    );
    expect(template).to.not.include(
      'class="mt-8 flex flex-row items-stretch gap-2 lg:flex-col"',
    );
  });

  it("places the pending changes alert under the draft event header", async () => {
    // Load the event add template before checking pending alert placement.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the save alert follows the title reminder and uses compact actions.
    const draftHeaderIndex = template.indexOf('id="draft-event-title"');
    const alertIndex = template.indexOf('id="pending-changes-alert"');

    expect(alertIndex).to.be.greaterThan(draftHeaderIndex);
    expect(template).to.not.include("icon-clock");
    expect(template).to.include(
      'id="pending-changes-alert" class="col-span-full hidden min-w-0"',
    );
    expect(template).to.include('class="min-w-0 flex-1 break-words text-sm/6"');
    expect(template).to.include(
      'class="btn-primary btn-mini h-7! w-24 text-nowrap ms-auto"',
    );
  });

  it("keeps bottom actions in the main grid column", async () => {
    // Load the event add template before checking grid placement classes.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert root-level actions after the form wrapper stay in the form column.
    expect(template).to.include(
      'class="flex flex-wrap items-center justify-end gap-3 mt-6 px-4 xl:col-start-2 xl:px-0"',
    );
  });

  it("initializes the General Admission ticket with 500 seats", async () => {
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include(
      `ticket-types='[{"active":true,"availability":"public","order":1,"price_windows":[{"amount_minor":0}],"seats_total":500,"title":"General Admission"}]'`,
    );
  });

  it("explains the event and venue requirements for paid tickets", async () => {
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include(
      "Paid ticket prices require an in-person or hybrid event with a venue name, address, city, postal code, and country.",
    );
  });

  it("submits state and country tax codes from the venue fields", async () => {
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include('state-field-name="venue_state_name"');
    expect(template).to.include('state-code-field-name="venue_state_code"');
    expect(template).to.include('country-code-field-name="venue_country_code"');
  });

  it("supports all event-wide tax modes during creation", async () => {
    // Load the event creation form before checking the tax controls.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify manual rates and no-tax mode are available with accessible rate states.
    expect(template).to.include(
      '<option value="automatic" selected>Automatic Stripe Tax</option>',
    );
    expect(template).to.include(
      '<option value="manual">Manual Stripe Tax Rates</option>',
    );
    expect(template).to.include(
      '<option value="none">Do not collect tax</option>',
    );
    expect(template).to.include('id="manual-tax-rates-fieldset"');
    expect(template).to.include('class="col-span-full max-w-3xl"');
    expect(template).to.include(
      'data-tax-rates-url="/dashboard/group/events/tax-rates"',
    );
    expect(template).to.include(
      '<div class="form-label"> <label for="manual-tax-rates">',
    );
    expect(template).to.include(
      'name="manual_tax_rate_ids[]" class="select-primary flex-1"',
    );
    expect(template).to.include('data-tax-rates-role="select"');
    expect(template).to.include(
      'aria-describedby="manual-tax-rates-help manual-tax-rates-state"></select>',
    );
    expect(template).to.include(
      'data-tax-rates-role="state" role="status" aria-live="polite"',
    );
    expect(template).to.include('data-tax-rates-role="retry-loading" hidden');
    expect(template).to.include(
      '<svg-spinner size="size-4" label="Loading Stripe Tax Rates">',
    );
    expect(template).not.to.include("<span>Loading...</span>");
    expect(template).to.include('aria-label="About Manual Stripe Tax Rates"');
    expect(template).to.include(
      'class="svg-icon size-3 icon-question-mark bg-stone-500"',
    );
    expect(template).to.include(
      'class="group/manual-tax-info relative inline-flex align-super"',
    );
    expect(template).to.include(
      "Create Tax Rates in the fiscal sponsor's Stripe account.",
    );
    expect(template).to.include("group-hover/manual-tax-info:visible");
    expect(template).to.include("group-focus-within/manual-tax-info:visible");
    expect(template).to.include(
      "The same rate applies to every paid ticket tier.",
    );
    expect(template.indexOf('id="manual-tax-rates-help"')).to.be.greaterThan(
      template.indexOf('id="manual-tax-rates"'),
    );
    expect(template).to.include(
      'class="col-span-full 2xl:col-span-2 2xl:col-start-1"> <label for="tax_calculation_mode"',
    );
  });

  it("does not expose payment recipient details", async () => {
    // Load the event add template before checking payment recipient copy.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert payment recipient details are not shown in the ticket form.
    expect(template).not.to.include(
      "Paid ticket revenue is sent to Stripe recipient",
    );
    expect(template).not.to.include("{{ payment_recipient.recipient_id }}");
  });

  it("starts free-only ticketing at ticket types without setup guidance", async () => {
    const template = normalizeWhitespace(await loadTemplate());
    const ticketForm = template.slice(
      template.indexOf('<form id="payments-form">'),
      template.indexOf("{# End Tickets Tab -#}"),
    );

    expect(ticketForm).to.include(
      '{% if payments_ready -%} <div> {{ dashboard::form_title(title = "Tickets"',
    );
    expect(ticketForm).to.include(">Ticket Types</div>");
    expect(
      ticketForm.match(
        /class="btn-secondary inline-flex items-center justify-center gap-2 whitespace-nowrap"/gu,
      ),
    ).to.have.length(2);
    expect(ticketForm).to.include('id="ticket-types-count"');
    expect(ticketForm).to.include('id="discount-codes-count"');
    expect(ticketForm).not.to.include(
      "Payments are not configured for this group",
    );
    expect(ticketForm).not.to.include(
      'class="mt-8 rounded-md border border-stone-200 bg-stone-50 px-4 py-3 text-stone-600"',
    );
  });

  it("describes paid enrollment modes as mutually exclusive alternatives", async () => {
    // Load the event add template before checking enrollment guidance.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert paid approval and waitlist modes are described without stale restrictions.
    expect(template).to.include(
      "Paid ticket events can use invitation approval.",
    );
    expect(template).to.include("including paid ticket events");
    expect(template).to.include(
      "Invitation approval and the waitlist cannot be enabled together.",
    );
    expect(template).to.not.include("waitlist or paid tickets");
    expect(template).to.not.include(
      "Paid events disable waitlist automatically.",
    );
  });

  it("spaces ticket sections without separators", async () => {
    // Load and isolate the ticket form before checking section spacing.
    const template = normalizeWhitespace(await loadTemplate());
    const ticketForm = template.slice(
      template.indexOf('<form id="payments-form">'),
      template.indexOf("{# End Tickets Tab -#}"),
    );

    // Keep the large section rhythm without rendering divider borders.
    expect(ticketForm).to.include('<div class="space-y-12">');
    expect(ticketForm.match(/class="pb-12"/gu)).to.have.length(1);
    expect(ticketForm).not.to.include('class="pt-12"');
    expect(ticketForm).not.to.include("pt-12 pb-12");
    expect(ticketForm).not.to.include("border-t");
    expect(ticketForm).not.to.include("border-stone-900/10");
  });

  it("keeps the event form navigation in the shared page scroll", async () => {
    // Load the event add template before checking sidebar scroll behavior.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the form navigation scrolls with the active event content.
    expect(template).to.not.include('class="sticky top-6"');
    expect(template).to.not.include(
      '<label for="add-event-section-select" class="form-label mb-2 lg:hidden">Section</label>',
    );
    expect(template).to.include('id="add-event-section-select"');
    expect(template).to.include(
      'class="select-primary w-full sm:w-sm xl:hidden"',
    );
    expect(template).to.include(
      'class="hidden flex-col gap-1 font-medium xl:flex"',
    );
    expect(template).to.include(
      'class="col-span-full row-start-2 grid h-full content-start min-h-0 min-w-0 gap-y-8 group-has-[#pending-changes-alert:not(.hidden)]/event-page:row-start-3 xl:grid-cols-[12rem_minmax(0,1fr)] xl:content-stretch xl:gap-x-8 xl:gap-y-0"',
    );
    expect(template).to.include(
      'class="min-w-0 pt-0 xl:row-span-full xl:self-stretch xl:border-r xl:border-stone-900/10 xl:py-0 xl:pr-8"',
    );
    expect(template).to.not.include("lg:border-b-0");
    expect(template).to.include(
      '<div class="min-w-0"> <div class="space-y-12">',
    );
  });

  it("uses editable contributor tables without award controls before creation", async () => {
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include(
      '<user-search-selector id="event-hosts-selector" field-name="hosts" dashboard-type="group" display-mode="table"',
    );
    expect(template).to.include(
      '<speakers-selector id="event-speakers-selector" dashboard-type="group" display-mode="table"',
    );
    expect(template).to.include("Session-level speakers");
    expect(template).to.include(
      '<div class="mt-8 border-t border-stone-200 pt-8"> <h3 class="form-label m-0">Session-level speakers</h3> <p class="mt-4 text-sm text-stone-500">',
    );
    expect(template).not.to.include(">Event Speakers<");
    expect(template).to.include(
      '<session-speakers-table id="session-speakers-table"></session-speakers-table>',
    );
    expect(template).not.to.include("can-award-badges");
    expect(template).not.to.include("show-award-all");
  });

  it("spaces contributor sections without separators", async () => {
    // Load and isolate the contributor form before checking section spacing.
    const template = normalizeWhitespace(await loadTemplate());
    const contributorForm = template.slice(
      template.indexOf('<form id="hosts-sponsors-form">'),
      template.indexOf("{# End Hosts & Speakers Tab -#}"),
    );

    // Keep the large section rhythm without rendering divider borders.
    expect(contributorForm).to.include('<div class="space-y-12">');
    expect(contributorForm.match(/class="pb-12"/gu)).to.have.length(1);
    expect(contributorForm).not.to.include("border-b");
    expect(contributorForm).not.to.include("border-stone-900/10");
  });
});
