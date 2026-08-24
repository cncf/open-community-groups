import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch(
    "/ocg-server/templates/dashboard/group/check_in_list.html",
  );

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group check-in template", () => {
  it("uses the dashboard content width", async () => {
    // Load the Check-In template before checking its page alignment.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the partial does not add a centered page-width constraint.
    expect(template).to.include(
      '<section class="relative min-w-0" data-group-check-in-root',
    );
    expect(template).not.to.include("container mx-auto");
    expect(template).not.to.include("max-w-7xl");
    expect(template).to.include("cards::check_in_event_card(event)");
    expect(template).not.to.include("status_before_title = true");
  });

  it("renders three event-card columns on extra-wide screens", async () => {
    // Load the Check-In template before checking its responsive grid.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the organizer grid grows from two to three columns at 2xl.
    expect(template).to.include("lg:grid-cols-2 2xl:grid-cols-3");
  });

  it("links desktop manual check-in guidance to Events", async () => {
    // Load the Check-In template before checking its desktop guidance.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the title legend replaces the desktop action with an explanatory link.
    expect(template).to.include('<span class="hidden md:inline">');
    expect(template).to.include("For manual check-in, open an event's attendee list from");
    expect(template).to.include('href="/dashboard/group?tab=events"');
    expect(template).to.include(">Events</a>.");
    expect(template).not.to.include(">Manual attendees list</a>");
  });

  it("uses a labeled mini button to open each event scanner", async () => {
    // Load the Check-In template before checking its scanner action.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify cards contain a real compact action instead of an unlabeled QR icon.
    expect(template).to.include("data-group-check-in-card");
    expect(template).to.include(
      'class="btn-primary-outline btn-mini inline-flex items-center whitespace-nowrap focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-500"',
    );
    expect(template).to.include("<span>Scan attendees</span>");
    expect(template).to.include('<span class="sr-only">for {{ event.name }}</span>');
    expect(template).not.to.include("icon-qr-code bg-primary-500");
  });

  it("uses shared dashboard styles for the scanner modal and controls", async () => {
    // Load the Check-In template before checking the modal primitives.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the scanner follows the app modal, form, switch, and action styles.
    expect(template).to.include('{% import "macros/dashboard.html" as dashboard -%}');
    expect(template).to.include(
      'class="fixed inset-0 z-[1000] hidden h-full max-h-full w-full items-center justify-center overflow-x-hidden overflow-y-auto flex"',
    );
    expect(template).to.include(
      '<div class="modal-panel h-full max-h-full max-w-2xl p-4 sm:h-auto sm:max-h-[90vh]">',
    );
    expect(template).to.include(
      '<div class="modal-card h-full max-h-full rounded-lg sm:h-auto sm:max-h-[calc(90vh-2rem)]">',
    );
    expect(template).to.include('<div class="modal-body flex-1 p-4 md:p-6">');
    expect(template).to.include(
      '{{ dashboard::modal_header(title_id = "group-check-in-scanner-title", title = "Scan attendees", close_attrs = "data-group-check-in-close") -}}',
    );
    expect(template).to.include('id="group-check-in-event-name"');
    expect(template).to.include('id="group-check-in-event-date"');
    expect(template).to.include('id="group-check-in-event-location" class="min-w-0 truncate"');
    expect(template).to.include(
      '<div class="w-full overflow-hidden rounded-xl border border-stone-200 bg-white">',
    );
    expect(template).to.include(
      '<div class="relative aspect-[4/3] overflow-hidden border-t border-stone-200 bg-stone-950">',
    );
    expect(template).to.include(
      '<div class="pointer-events-none absolute inset-[10%] rounded-2xl border-2 border-white/70"> <div data-group-check-in-camera-unavailable',
    );
    expect(template).to.include('class="select select-primary mt-1" disabled');
    expect(template).not.to.include("icon-caret-down");
    expect(template).to.include('class="sr-only peer" data-group-check-in-mute');
    expect(template).to.include("data-group-check-in-torch-control");
    expect(template).to.include('class="sr-only peer" data-group-check-in-torch disabled');
    expect(template).to.include('class="ms-3 text-sm font-medium text-stone-900">Torch</span>');
    expect(template).to.include("peer-checked:bg-primary-500");
    expect(template).not.to.include("Turn torch on");
    expect(template).to.include('class="btn-primary-outline w-full sm:w-auto"');
    expect(template).to.include(
      'class="btn-primary-anchor inline-flex w-full justify-center sm:w-auto">Manual check-in</a>',
    );
  });
});
