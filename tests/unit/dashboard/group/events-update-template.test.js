import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/events_update.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group event update template", () => {
  it("keeps the update event page at full dashboard content height", async () => {
    // Load the event update template before checking page root classes.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the update event page can fill the group dashboard content area.
    expect(template).to.include('id="event-update-page"');
    expect(template).to.include(
      'class="group/event-page grid h-full min-h-full min-w-0 grow grid-rows-[auto_minmax(0,1fr)] gap-y-8 has-[#pending-changes-alert:not(.hidden)]:grid-rows-[auto_auto_minmax(0,1fr)] lg:grid-cols-[12rem_minmax(0,1fr)] lg:gap-x-8"',
    );
    expect(template).to.include('data-event-page="update"');
    expect(template).to.include('<div id="event-preview-modal-root" class="contents"></div>');
  });

  it("keeps the existing read-only copy when registration answers lock question editing", async () => {
    // Load the event update template before checking locked question copy.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the rendered registration question fields.
    expect(template).to.include("{% if event.registration_questions_locked -%}");
    expect(template).to.include(
      "Registration questions are read-only because attendees have submitted answers.",
    );
    expect(template).to.include(
      "Mark a question Required if you need the answer with a ticket request, RSVP, checkout, or offer claim.",
    );
    expect(template).to.include("Ticket-request answers are available from Requests.");
    expect(template).to.include(
      "accept pending invitation requests and reissue expired approval offers outside the window.",
    );
    expect(template).to.include(
      "Accept pending requests and reissue expired offers while the event is still",
    );
  });

  it("passes past-event state to online event and session details", async () => {
    // Load the event update template before checking the component contract.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the online and session details components receive past-event state.
    expect(template).to.include("{% if event.is_past() %}event-past{% endif %}");
  });

  it("shows an event title header above update tabs and content", async () => {
    // Load the event update template before checking the event reminder.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the reminder spans the form layout without sticking to the viewport.
    expect(template).to.include('class="col-span-full min-w-0 space-y-4"');
    expect(template).to.not.include('style="top: 6.25rem"');
    expect(template).to.not.include("Editing event");
    expect(template).to.include(
      '<div class="truncate text-xl font-semibold text-stone-900">{{ event.name }}</div>',
    );
    expect(template).to.include('class="min-w-0 flex-1"');
    expect(template).to.not.include("overflow-hidden");
    expect(template).to.include('class="col-span-full min-w-0 2xl:col-span-3"');
    expect(template).to.include("{% if let Some(starts_at) = &event.starts_at -%}");
    expect(template).to.include(
      '{{ starts_at.with_timezone(event.timezone).format("%B %-e, %Y %-I:%M %p") }}',
    );
    expect(template).to.include("{% if let Some(ends_at) = &event.ends_at -%}");
    expect(template).to.include('<span class="text-stone-400">-</span>');
    expect(template).to.include('{{ ends_at.with_timezone(event.timezone).format("%-I:%M %p %Z") }}');
    expect(template).to.include('class="mt-1 text-xs text-stone-500"');
    expect(template).to.include('class="flex shrink-0 flex-row items-center justify-end gap-2 sm:ms-4"');
    expect(template).to.include('id="event-preview-button"');
    expect(template).to.include('id="event-public-page-link"');
    expect(template).to.include('id="publish-event-button"');
    expect(template).to.include('hx-put="/dashboard/group/events/{{ event.event_id }}/publish"');
    expect(template).to.include('hx-swap="none"');
    expect(template).to.include('data-has-related-events="{{ event.has_related_events }}"');
    expect(template).to.include('disabled title="This event is already published."');
    expect(template.indexOf("{% if event.canceled -%}")).to.be.lessThan(
      template.indexOf("{% else if event.published -%}"),
    );
    expect(template.indexOf('id="publish-event-button"')).to.be.greaterThan(
      template.indexOf('id="event-public-page-link"'),
    );
    expect(template).to.include(
      'class="group btn-primary-outline inline-flex items-center justify-center gap-2 whitespace-nowrap max-2xl:h-7 max-2xl:px-3 max-2xl:py-1 max-2xl:text-xs disabled:cursor-not-allowed disabled:opacity-50"',
    );
    expect(template).to.include(
      'class="group btn-primary-outline-anchor inline-flex items-center justify-center gap-2 whitespace-nowrap max-2xl:h-7 max-2xl:px-3 max-2xl:py-1 max-2xl:text-xs"',
    );
    expect(template).to.include(
      'Ends {{ ends_at.with_timezone(event.timezone).format("%B %-e, %Y %-I:%M %p %Z") }}',
    );
    expect(template).to.include('<div class="mt-1 text-xs text-stone-500">Date not set yet</div>');
    const eventTitleIndex = template.indexOf(
      '<div class="truncate text-xl font-semibold text-stone-900">{{ event.name }}</div>',
    );
    const canceledWarningIndex = template.indexOf("This event is canceled.");
    const eventContentIndex = template.indexOf('class="col-span-full row-start-2 grid h-full content-start');

    expect(canceledWarningIndex).to.be.greaterThan(eventTitleIndex);
    expect(eventContentIndex).to.be.greaterThan(canceledWarningIndex);
  });

  it("places the pending changes alert under the event title header", async () => {
    // Load the event update template before checking pending alert placement.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the save alert follows the title reminder and uses compact actions.
    const eventTitleIndex = template.indexOf(
      '<div class="truncate text-xl font-semibold text-stone-900">{{ event.name }}</div>',
    );
    const alertIndex = template.indexOf('id="pending-changes-alert"');

    expect(alertIndex).to.be.greaterThan(eventTitleIndex);
    expect(template).to.not.include("icon-clock");
    expect(template).to.include('id="pending-changes-alert" class="col-span-full hidden min-w-0"');
    expect(template).to.include('class="min-w-0 flex-1 break-words text-sm/6"');
    expect(template).to.include("btn-primary btn-mini h-7! w-24 text-nowrap ms-auto");
    expect(template).to.include('hx-put="/dashboard/group/events/{{ event.event_id }}/update"');
    expect(template).to.include('hx-target="#dashboard-content"');
    expect(template).to.include('hx-swap="none"');
  });

  it("lazy-loads event review tabs from the desktop tab buttons", async () => {
    // Load the event update template before checking lazy tab contracts.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert review tabs fetch their table content only when selected.
    expect(template).to.include('aria-label="Event form section"');
    expect(template).to.not.include(
      '<label for="update-event-section-select" class="form-label mb-2 lg:hidden">Section</label>',
    );
    expect(template).to.include('id="update-event-section-select"');
    expect(template).to.include('class="select-primary w-full sm:w-sm xl:hidden"');
    expect(template).to.include('class="hidden flex-col gap-1 font-medium xl:flex"');
    expect(template).to.include('event_form::tab_option(section = "attendees", label = "Attendees")');
    expect(template).to.include(
      'event_form::tab_option(section = "invitation-requests", label = "Requests")',
    );
    expect(template).to.include('event_form::tab_option(section = "waitlist", label = "Waitlist")');
    expect(template).to.include(
      'hx-get="/dashboard/group/events/{{ event.event_id }}/attendees" hx-trigger="click once" hx-target="#attendees-content"',
    );
    expect(template).to.include('<div id="attendees-content" data-group-check-in-root>');
    expect(template).to.include(
      'hx-get="/dashboard/group/events/{{ event.event_id }}/invitation-requests" hx-trigger="click once" hx-target="#invitation-requests-content"',
    );
    expect(template).to.include(
      'hx-get="/dashboard/group/events/{{ event.event_id }}/waitlist" hx-trigger="click once" hx-target="#waitlist-content"',
    );
  });

  it("keeps review tabs and bottom actions in the main grid column", async () => {
    // Load the event update template before checking grid placement classes.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert root-level content after the form wrapper stays in the form column.
    expect(template).to.include(
      'data-content="attendees" class="hidden min-w-0 px-4 xl:col-start-2 xl:px-0"',
    );
    expect(template).to.include(
      'data-content="invitation-requests" class="hidden min-w-0 px-4 xl:col-start-2 xl:px-0"',
    );
    expect(template).to.include('data-content="waitlist" class="hidden min-w-0 px-4 xl:col-start-2 xl:px-0"');
    expect(template).to.include(
      'class="flex flex-wrap items-center justify-end gap-3 mt-6 px-4 xl:col-start-2 xl:px-0"',
    );
  });

  it("does not expose payment recipient details", async () => {
    // Load the event update template before checking payment recipient copy.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert payment recipient details are not shown in the ticket form.
    expect(template).not.to.include("Paid ticket revenue is sent to Stripe recipient");
    expect(template).not.to.include("{{ payment_recipient.recipient_id }}");
  });

  it("renders external payment fields when eligible or already configured", async () => {
    // Load the event update template before checking external payment controls.
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include(
      "{% if self.uses_external_ticketing() || event.external_payment_url.is_some() -%}",
    );
    expect(template).to.include('name="external_payment_url_present"');
    expect(template).to.include('id="external_payment_url"');
    expect(template).to.include('name="external_payment_url"');
    expect(template).to.include("{% if let Some(url) = event.external_payment_url %}value=\"{{ url }}\"{% endif %}");
    expect(template).to.include('name="external_payment_instructions_present"');
    expect(template).to.include('id="external_payment_instructions"');
    expect(template).to.include('name="external_payment_instructions"');
    expect(template).to.include(
      "{% if let Some(instructions) = event.external_payment_instructions %}{{ instructions }}{% endif %}",
    );
    expect(template).to.include('name="external_payment_window_hours_present"');
    expect(template).to.include('id="external_payment_window_hours"');
    expect(template).to.include('name="external_payment_window_hours"');
    expect(template).to.include(
      "{% if let Some(hours) = event.external_payment_window_hours %}value=\"{{ hours }}\"{% endif %}",
    );
    expect(template).to.include(
      "{% if event_read_only || (ticketing_read_only && self.uses_external_ticketing()) %}disabled{% endif %}",
    );
    expect(template).to.include("{% if !self.uses_external_ticketing() -%}");
    expect(template).to.include("External payments are no longer available for this group.");
    expect(template).to.include("Clear the external payment URL to save changes; paid tickets");
  });

  it("explains the event and venue requirements for paid tickets", async () => {
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include(
      "Paid ticket prices require an in-person or hybrid event with a venue name, address, city, postal code, and country.",
    );
  });

  it("links unsupported automatic-tax feedback to manual-tax guidance", async () => {
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include(
      'href="/docs#/guides/event-operations?id=tickets-discounts-and-refunds" target="_blank" rel="noopener noreferrer" hx-boost="false"',
    );
    expect(template).to.include(
      'data-automatic-tax-readiness-role="manual-tax-help" hidden>Learn how to configure manual tax</a>',
    );
  });

  it("renders automatic-tax readiness as an outline action beside the tax label", async () => {
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include(
      '<div class="flex flex-wrap items-center gap-2"> <label for="tax_calculation_mode" class="form-label">Ticket Tax Calculation</label> <button type="button" class="btn-primary-outline btn-mini"',
    );
    expect(template).to.include(
      'data-automatic-tax-readiness-action="check" title="Check the saved venue with the automatic-tax provider"',
    );
    expect(template).to.include('aria-describedby="automatic-tax-readiness-status"');
    expect(template).to.include("{% if event_read_only %}disabled{% endif %}>Check readiness</button>");
    expect(template).to.include("Check readiness</button>");
    expect(template).to.include(
      '<div class="col-span-full hidden rounded-md border px-4 py-3" data-automatic-tax-readiness',
    );
    expect(template).to.include(
      'id="automatic-tax-readiness-status" class="text-sm/6" data-automatic-tax-readiness-role="status" role="status" aria-live="polite"',
    );
  });

  it("restores state and country tax codes into the venue fields", async () => {
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include('state-field-name="venue_state_name"');
    expect(template).to.include('state-code-field-name="venue_state_code"');
    expect(template).to.include('initial-state-code="{{ venue_state_code }}"');
    expect(template).to.include('country-code-field-name="venue_country_code"');
    expect(template).to.include('initial-country-code="{{ venue_country_code }}"');
  });
  it("keeps payment guidance only for read-only paid events", async () => {
    const template = normalizeWhitespace(await loadTemplate());
    const ticketForm = template.slice(
      template.indexOf('<form id="payments-form">'),
      template.indexOf("{# End Tickets Tab -#}"),
    );

    expect(ticketForm).to.include(
      '{% if paid_ticketing_available || event.is_paid_capable() -%} <div> {{ dashboard::form_title(title = "Tickets"',
    );
    expect(ticketForm).to.include("{% if paid_ticketing_read_only -%}");
    expect(ticketForm).to.include(
      'class="mt-8 rounded-md border border-stone-200 bg-stone-50 px-4 py-3 text-stone-600"',
    );
    expect(ticketForm).to.include(
      "Paid ticket settings are read-only until server payments and a matching group recipient are configured.",
    );
    expect(ticketForm).not.to.include(
      "Payments are not configured for this group, but free ticket tiers remain editable.",
    );
    expect(
      ticketForm.match(/class="btn-secondary inline-flex items-center justify-center whitespace-nowrap"/gu),
    ).to.have.length(2);
    expect(ticketForm).not.to.include("icon-add-circle");
    expect(ticketForm).not.to.include('id="ticket-types-count"');
    expect(ticketForm).not.to.include('id="discount-codes-count"');
  });

  it("offers manual-tax and no-tax modes with event-level selections", async () => {
    // Load the event update form before checking tax mode state.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify all modes and the server-rendered selection contract.
    expect(template).to.include('<option value="manual"');
    expect(template).to.include(
      "{% if self.uses_manual_ticket_tax() %}selected{% endif %}>Manual Stripe Tax Rates</option>",
    );
    expect(template).to.include('<option value="none"');
    expect(template).to.include('<div class="col-span-full 2xl:col-span-2" data-tax-control="behavior">');
    expect(template).to.include(
      "{% if ticketing_read_only || self.uses_no_ticket_tax() %}disabled{% endif %}",
    );
    expect(template).to.include("data-selected-rate-ids='{{ event.manual_tax_rate_ids|json }}'");
    expect(template).to.include('class="col-span-full max-w-3xl"');
    expect(template).to.include('<div class="form-label"> <label for="manual-tax-rates">');
    expect(template).to.include('name="manual_tax_rate_ids[]" class="select-primary flex-1"');
    expect(template).to.include('data-tax-rates-role="select"');
    expect(template).to.include('aria-describedby="manual-tax-rates-help manual-tax-rates-state"></select>');
    expect(template).to.include('data-tax-rates-role="state" role="status" aria-live="polite"');
    expect(template).to.include(
      'id="manual-tax-rates-state" class="mt-2 rounded-md border px-4 py-3 text-sm/6"',
    );
    expect(template).to.include('data-tax-rates-role="retry-loading" hidden');
    expect(template).to.include('<svg-spinner size="size-4" label="Loading Stripe Tax Rates">');
    expect(template).not.to.include("<span>Loading...</span>");
    expect(template).to.include('aria-label="About Manual Stripe Tax Rates"');
    expect(template).to.include('class="svg-icon size-3 icon-question-mark bg-stone-500"');
    expect(template).to.include('class="group/manual-tax-info relative inline-flex align-super"');
    expect(template).to.include("Create Tax Rates in the fiscal sponsor's Stripe account.");
    expect(template).to.include("group-hover/manual-tax-info:visible");
    expect(template).to.include("group-focus-within/manual-tax-info:visible");
    expect(template).to.include("The same rate applies to every paid ticket tier.");
    expect(template.indexOf('id="manual-tax-rates-help"')).to.be.greaterThan(
      template.indexOf('id="manual-tax-rates"'),
    );
    expect(template).to.include(
      'class="col-span-full 2xl:col-span-2 2xl:col-start-1"> <div class="flex flex-wrap items-center gap-2"> <label for="tax_calculation_mode"',
    );
  });

  it("describes paid enrollment modes as mutually exclusive alternatives", async () => {
    // Load the event update template before checking enrollment guidance.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert paid approval and waitlist modes are described without stale restrictions.
    expect(template).to.include("Paid ticket events can use invitation approval.");
    expect(template).to.include("including paid ticket events");
    expect(template).to.include("Invitation approval and the waitlist cannot be enabled together.");
    expect(template).to.not.include("waitlist or paid tickets");
    expect(template).to.not.include("Paid events disable waitlist automatically.");
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
    // Load the event update template before checking sidebar scroll behavior.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the form navigation scrolls with the active event content.
    expect(template).to.not.include('class="sticky top-6"');
    expect(template).to.include(
      'class="col-span-full row-start-2 grid h-full content-start min-h-0 min-w-0 gap-y-8 group-has-[#pending-changes-alert:not(.hidden)]/event-page:row-start-3 xl:grid-cols-[11rem_minmax(0,1fr)] xl:content-stretch xl:gap-x-8 xl:gap-y-0"',
    );
    expect(template).to.include(
      'class="min-w-0 pt-0 xl:row-span-full xl:self-stretch xl:border-r xl:border-stone-900/10 xl:py-0 xl:pr-8"',
    );
    expect(template).to.not.include("lg:border-b-0");
    expect(template).to.include('<div class="min-w-0"> <div class="inert-form"');
  });

  it("wires event and session contributor tables to shared badge awards", async () => {
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include(
      '<user-search-selector id="event-hosts-selector" selected-users="{{ event.hosts|json }}" field-name="hosts" dashboard-type="group" display-mode="table" event-id="{{ event.event_id }}" {% if can_manage_events && !event.canceled %}can-award-badges award-button-id="event-hosts-award-button"{% endif %}',
    );
    expect(template).to.include(
      '<div class="flex flex-wrap items-center justify-between gap-3"> <div class="text-xl lg:text-2xl font-medium text-stone-900">Event Hosts</div>',
    );
    expect(template).to.include(
      '<button id="event-hosts-award-button" type="button" class="btn-primary-outline" data-badge-award-open disabled>Award badge</button>',
    );
    expect(template).to.include(
      '<speakers-selector id="event-speakers-selector" selected-speakers="{{ event.speakers|json }}" dashboard-type="group" display-mode="table" event-id="{{ event.event_id }}"',
    );
    expect(template).to.include("can-award-badges show-award-all");
    expect(template).to.include("Session-level speakers");
    expect(template).to.include(
      '<div class="mt-8"> <h3 class="form-label m-0">Session-level speakers</h3> <p class="mt-4 text-sm text-stone-500">',
    );
    expect(template).not.to.include(">Event Speakers<");
    expect(template).not.to.include('<div class="mt-8 border-t border-stone-200 pt-8">');
    expect(template).to.include(
      '<session-speakers-table id="session-speakers-table" sessions="{{ event.sessions|json }}" event-id="{{ event.event_id }}"',
    );
    expect(template).to.include("can-award-badges{% endif %}");
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
