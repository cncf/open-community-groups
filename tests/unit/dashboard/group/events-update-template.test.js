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
      'class="grid min-w-0 grow gap-y-12 lg:grid-cols-[12rem_minmax(0,1fr)] lg:gap-x-8"',
    );
    expect(template).to.include('data-event-page="update"');
  });

  it("keeps the existing read-only copy when registration answers lock question editing", async () => {
    // Load the event update template before checking locked question copy.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the rendered registration question fields.
    expect(template).to.include("{% if event.registration_questions_locked -%}");
    expect(template).to.include(
      "Registration questions are read-only because attendees have submitted answers.",
    );
  });

  it("passes past-event state to online event and session details", async () => {
    // Load the event update template before checking the component contract.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the online and session details components receive past-event state.
    expect(template).to.include("{% if event.is_past() %}event-past{% endif %}");
  });

  it("lazy-loads event review tabs from the desktop tab buttons", async () => {
    // Load the event update template before checking lazy tab contracts.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert review tabs fetch their table content only when selected.
    expect(template).to.include('aria-label="Event form section"');
    expect(template).to.include('event_form::tab_option(section = "attendees", label = "Attendees")');
    expect(template).to.include(
      'event_form::tab_option(section = "invitation-requests", label = "Requests")',
    );
    expect(template).to.include('event_form::tab_option(section = "waitlist", label = "Waitlist")');
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
      'data-content="attendees" class="hidden min-w-0 px-4 lg:col-start-2 lg:px-0"',
    );
    expect(template).to.include(
      'data-content="invitation-requests" class="hidden min-w-0 px-4 lg:col-start-2 lg:px-0"',
    );
    expect(template).to.include('data-content="waitlist" class="hidden min-w-0 px-4 lg:col-start-2 lg:px-0"');
    expect(template).to.include(
      'class="flex flex-wrap items-center justify-end gap-3 mt-6 px-4 lg:col-start-2 lg:px-0"',
    );
  });

  it("keeps the event form navigation in the shared page scroll", async () => {
    // Load the event update template before checking sidebar scroll behavior.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the form navigation scrolls with the active event content.
    expect(template).to.not.include('class="sticky top-6"');
  });
});
