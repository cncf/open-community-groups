import { expect } from "@open-wc/testing";

const loadTemplate = async (
  templatePath = "/ocg-server/templates/dashboard/group/check_in_list.html",
) => {
  const response = await fetch(templatePath);

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
    expect(template).to.include(
      "For manual check-in, open an event's attendee list from",
    );
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
      'class="btn-primary-outline btn-mini inline-flex items-center whitespace-nowrap focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-500 phone:absolute phone:inset-x-3 phone:bottom-3 phone:h-11 phone:justify-center phone:text-sm"',
    );
    expect(template).to.include("<span>Scan Attendee Codes</span>");
    expect(template).to.include(
      '<span class="sr-only">for {{ event.name }}</span>',
    );
    expect(template).not.to.include("icon-qr-code bg-primary-500");
  });

  it("uses shared dashboard styles for the scanner modal and controls", async () => {
    // Load the Check-In template before checking the modal primitives.
    const checkInTemplate = normalizeWhitespace(await loadTemplate());
    const template = normalizeWhitespace(
      await loadTemplate(
        "/ocg-server/templates/dashboard/group/check_in_scanner_modal.html",
      ),
    );

    // Verify the scanner follows the app modal, form, switch, and action styles.
    expect(checkInTemplate).to.include(
      '{% include "dashboard/group/check_in_scanner_modal.html" -%}',
    );
    expect(template).to.include(
      '{% import "macros/dashboard.html" as dashboard -%}',
    );
    expect(template).to.include(
      'class="fixed inset-0 z-[1000] hidden items-center justify-center p-3 sm:p-6 flex"',
    );
    expect(template).to.include(
      '<div class="relative z-10 flex h-[calc(100dvh-1.5rem)] w-full max-w-full flex-col overflow-hidden rounded-xl bg-white shadow-xl sm:h-auto sm:max-h-[calc(100dvh-3rem)] sm:max-w-2xl sheet-panel phone:h-[calc(100dvh-4rem)]">',
    );
    expect(template).to.include(
      '<div class="flex shrink-0 items-center justify-between gap-4 border-b border-stone-200 px-5 py-4 sm:px-6 sm:py-5 sheet-head sheet-grab phone:py-0">',
    );
    expect(template).to.include(
      '<h3 id="group-check-in-scanner-title" class="text-xl font-semibold text-stone-900 phone:min-w-0 phone:truncate">Scan Attendee Codes</h3>',
    );
    expect(template).to.include(
      '{{ dashboard::modal_close_button(attrs = "data-group-check-in-close") -}}',
    );
    expect(template).to.include(
      '<div class="min-h-0 flex-1 overflow-y-auto p-4 md:p-6 phone:max-sm:flex phone:max-sm:flex-col phone:max-sm:p-0" data-group-check-in-body>',
    );
    expect(template).to.include('id="group-check-in-event-name"');
    expect(template).to.include('id="group-check-in-event-date"');
    expect(template).to.include(
      'id="group-check-in-event-location" class="min-w-0 truncate"',
    );
    expect(template).to.include(
      '<div class="w-full overflow-hidden rounded-xl border border-stone-200 bg-white phone:max-sm:flex phone:max-sm:shrink-0 phone:max-sm:basis-auto phone:max-sm:flex-1 phone:max-sm:flex-col phone:max-sm:rounded-none phone:max-sm:border-0">',
    );
    expect(template).to.include(
      '<div class="relative aspect-[4/3] overflow-hidden border-t border-stone-200 bg-stone-950 phone:max-sm:aspect-auto phone:max-sm:min-h-48 phone:max-sm:flex-1">',
    );
    expect(template).to.include(
      '<div class="pointer-events-none absolute inset-[10%] rounded-2xl border-2 border-white/70 phone:max-sm:inset-auto phone:max-sm:top-1/2 phone:max-sm:left-1/2 phone:max-sm:aspect-square phone:max-sm:w-[70%] phone:max-sm:max-h-[80%] phone:max-sm:-translate-x-1/2 phone:max-sm:-translate-y-1/2"> <div data-group-check-in-camera-unavailable',
    );
    expect(template).to.include(
      'class="select select-primary mt-1 phone:min-h-11" disabled',
    );
    expect(template).not.to.include("icon-caret-down");
    expect(template).to.include(
      'class="sr-only peer" data-group-check-in-mute>',
    );
    expect(template).not.to.include("data-group-check-in-mute checked");
    expect(template).to.include("data-group-check-in-torch-control");
    expect(template).to.include(
      'class="sr-only peer" data-group-check-in-torch disabled',
    );
    expect(template).to.include(
      'class="ms-3 text-sm font-medium text-stone-900">Torch</span>',
    );
    expect(template).to.include('class="toggle-track"');
    expect(template).not.to.include("Turn torch on");
    expect(template).to.include('class="btn-primary-outline w-full sm:w-auto"');
    expect(template).not.to.include("data-group-check-in-manual");
    expect(template).not.to.include("data-attendees-url");
  });

  it("keeps desktop's cards on phones with the scan button on its own line", async () => {
    // Load the Check-In template before checking the phone card layout.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the list inset, and the room the card leaves for the bottom button.
    expect(template).to.include("phone:mx-3 phone:mb-4 phone:mt-0 phone:gap-3");
    expect(template).to.include("hover:shadow-sm phone:pb-14");
    expect(template).to.include("phone:px-3 phone:pt-4 phone:pb-3");
  });

  it("scopes every scanner layout change below 640px", async () => {
    // Load the shared scanner modal, which the desktop Attendees tab also uses.
    const template = normalizeWhitespace(
      await loadTemplate(
        "/ocg-server/templates/dashboard/group/check_in_scanner_modal.html",
      ),
    );

    // Verify the frame centres itself only on phones below 640px.
    expect(template).to.include("phone:max-sm:-translate-x-1/2 phone:max-sm:-translate-y-1/2");
    expect(template).to.include('border-white/70 phone:max-sm:inset-auto');
    expect(template).not.to.match(/[\s"]max-sm:/);

    // Verify a single camera hides the select, without depending on its disabled state.
    expect(template).to.include("phone:has-[option:only-child]:max-sm:hidden");
    expect(template).not.to.include("select:disabled");
  });

  it("gives the scanner controls 44px targets on phones", async () => {
    // Load the shared scanner modal before checking its touch targets.
    const template = normalizeWhitespace(
      await loadTemplate(
        "/ocg-server/templates/dashboard/group/check_in_scanner_modal.html",
      ),
    );

    // Verify the close button rides the draggable sheet head (sized to 44px by the sheet
    // styles), and both switches reach 44px.
    expect(template).to.include("sheet-head sheet-grab");
    expect(template).to.include(
      '<label class="inline-flex cursor-pointer items-center has-[:disabled]:cursor-not-allowed phone:min-h-11">',
    );
    expect(template).to.include(
      '<label class="hidden cursor-pointer items-center has-[:disabled]:cursor-not-allowed phone:min-h-11"',
    );
  });
});
