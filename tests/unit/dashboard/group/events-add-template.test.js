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
      'class="min-w-0 pt-0 xl:row-span-full xl:self-stretch xl:border-r xl:border-stone-900/10 xl:py-0 xl:pr-8"',
    );
    expect(template).to.not.include("lg:border-b-0");
    expect(template).to.include(
      '<div class="min-w-0"> <div class="space-y-12">',
    );
  });
});
