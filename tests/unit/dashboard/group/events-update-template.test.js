import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch(
    "/ocg-server/templates/dashboard/group/events_update.html",
  );

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
    expect(template).to.include(
      '<div id="event-preview-modal-root" class="contents"></div>',
    );
  });

  it("keeps the existing read-only copy when registration answers lock question editing", async () => {
    // Load the event update template before checking locked question copy.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the rendered registration question fields.
    expect(template).to.include(
      "{% if event.registration_questions_locked -%}",
    );
    expect(template).to.include(
      "Registration questions are read-only because attendees have submitted answers.",
    );
  });

  it("passes past-event state to online event and session details", async () => {
    // Load the event update template before checking the component contract.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the online and session details components receive past-event state.
    expect(template).to.include(
      "{% if event.is_past() %}event-past{% endif %}",
    );
  });

  it("shows an event title header above update tabs and content", async () => {
    // Load the event update template before checking the event reminder.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the reminder spans the form layout without sticking to the viewport.
    expect(template).to.include('class="col-span-full min-w-0"');
    expect(template).to.not.include('style="top: 6.25rem"');
    expect(template).to.not.include("Editing event");
    expect(template).to.include(
      '<div class="truncate text-xl font-semibold text-stone-900">{{ event.name }}</div>',
    );
    expect(template).to.include('class="min-w-0 flex-1"');
    expect(template).to.not.include("overflow-hidden");
    expect(template).to.include('class="col-span-full min-w-0 2xl:col-span-3"');
    expect(template).to.include(
      "{% if let Some(starts_at) = &event.starts_at -%}",
    );
    expect(template).to.include(
      '{{ starts_at.with_timezone(event.timezone).format("%B %-e, %Y %-I:%M %p") }}',
    );
    expect(template).to.include("{% if let Some(ends_at) = &event.ends_at -%}");
    expect(template).to.include('<span class="text-stone-400">-</span>');
    expect(template).to.include(
      '{{ ends_at.with_timezone(event.timezone).format("%-I:%M %p %Z") }}',
    );
    expect(template).to.include('class="mt-1 text-xs text-stone-500"');
    expect(template).to.include(
      'class="flex shrink-0 flex-row items-center justify-end gap-2 sm:ms-4"',
    );
    expect(template).to.include('id="event-preview-button"');
    expect(template).to.include('id="event-public-page-link"');
    expect(template).to.include(
      'class="group btn-primary-outline inline-flex items-center justify-center gap-2 whitespace-nowrap max-2xl:h-7 max-2xl:px-3 max-2xl:py-1 max-2xl:text-xs disabled:cursor-not-allowed disabled:opacity-50"',
    );
    expect(template).to.include(
      'class="group btn-primary-outline-anchor inline-flex items-center justify-center gap-2 whitespace-nowrap max-2xl:h-7 max-2xl:px-3 max-2xl:py-1 max-2xl:text-xs"',
    );
    expect(template).to.include(
      'Ends {{ ends_at.with_timezone(event.timezone).format("%B %-e, %Y %-I:%M %p %Z") }}',
    );
    expect(template).to.include(
      '<div class="mt-1 text-xs text-stone-500">Date not set yet</div>',
    );
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
    expect(template).to.include(
      'id="pending-changes-alert" class="col-span-full hidden min-w-0"',
    );
    expect(template).to.include('class="min-w-0 flex-1 break-words text-sm/6"');
    expect(template).to.include(
      "btn-primary btn-mini h-7! w-24 text-nowrap ms-auto",
    );
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
    expect(template).to.include(
      'class="select-primary w-full sm:w-sm xl:hidden"',
    );
    expect(template).to.include(
      'class="hidden flex-col gap-1 font-medium xl:flex"',
    );
    expect(template).to.include(
      'event_form::tab_option(section = "attendees", label = "Attendees")',
    );
    expect(template).to.include(
      'event_form::tab_option(section = "invitation-requests", label = "Requests")',
    );
    expect(template).to.include(
      'event_form::tab_option(section = "waitlist", label = "Waitlist")',
    );
    expect(template).to.include(
      'hx-get="/dashboard/group/events/{{ event.event_id }}/attendees" hx-trigger="click once" hx-target="#attendees-content"',
    );
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
    expect(template).to.include(
      'data-content="waitlist" class="hidden min-w-0 px-4 xl:col-start-2 xl:px-0"',
    );
    expect(template).to.include(
      'class="flex flex-wrap items-center justify-end gap-3 mt-6 px-4 xl:col-start-2 xl:px-0"',
    );
  });

  it("keeps the event form navigation in the shared page scroll", async () => {
    // Load the event update template before checking sidebar scroll behavior.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the form navigation scrolls with the active event content.
    expect(template).to.not.include('class="sticky top-6"');
    expect(template).to.include(
      'class="col-span-full row-start-2 grid h-full content-start min-h-0 min-w-0 gap-y-8 group-has-[#pending-changes-alert:not(.hidden)]/event-page:row-start-3 xl:grid-cols-[12rem_minmax(0,1fr)] xl:content-stretch xl:gap-x-8 xl:gap-y-0"',
    );
    expect(template).to.include(
      'class="min-w-0 pt-0 xl:row-span-full xl:self-stretch xl:border-r xl:border-stone-900/10 xl:py-0 xl:pr-8"',
    );
    expect(template).to.not.include("lg:border-b-0");
    expect(template).to.include(
      '<div class="min-w-0"> <div class="inert-form"',
    );
  });
});
