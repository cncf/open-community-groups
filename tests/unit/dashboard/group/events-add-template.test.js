import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/events_add.html");

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
      'class="grid min-w-0 grow gap-y-12 lg:grid-cols-[12rem_minmax(0,1fr)] lg:gap-x-8"',
    );
    expect(template).to.include('data-event-page="add"');
  });

  it("keeps bottom actions in the main grid column", async () => {
    // Load the event add template before checking grid placement classes.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert root-level actions after the form wrapper stay in the form column.
    expect(template).to.include(
      'class="flex flex-wrap items-center justify-end gap-3 mt-6 px-4 lg:col-start-2 lg:px-0"',
    );
  });

  it("keeps the event form navigation in the shared page scroll", async () => {
    // Load the event add template before checking sidebar scroll behavior.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert the form navigation scrolls with the active event content.
    expect(template).to.not.include('class="sticky top-6"');
  });
});
