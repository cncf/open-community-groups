import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/event/page.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("event page agenda filter template", () => {
  it("renders chips below the input and closes after each pick", async () => {
    // Load the event page template before checking the agenda labels filter.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the filter closes after a pick and keeps touch browsing.
    expect(template).to.include(
      '<label-selector id="agenda-label-filter" data-agenda-filter name="" label="Filter agenda by labels" labels="{{ agenda_labels|json }}" placeholder="Filter by labels" close-on-select touch-browse> </label-selector>',
    );

    // Verify selected chips render below the input.
    const filter = template.match(/<label-selector id="agenda-label-filter"[^>]*>/)[0];
    expect(filter).to.not.include("selected-in-input");
  });
});
