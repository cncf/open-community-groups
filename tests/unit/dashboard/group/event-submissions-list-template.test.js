import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/event_submissions_list.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group event submissions list template", () => {
  it("renders selected filter labels as standard chips below the search input", async () => {
    // Load the submissions list template before checking the labels filter.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the labels filter keeps chips out of the input at the standard size.
    expect(template).to.include(
      '<label-selector id="submissions-label-filter" name="label_ids" labels="{{ event_labels|json }}" selected="{{ selected_label_ids|json }}" placeholder="Search labels"> </label-selector>',
    );
    expect(template).to.not.include("selected-in-input");

    // Verify the sort control stays aligned with the input when chips wrap.
    expect(template).to.include('<div class="flex flex-col gap-3 md:flex-row md:items-start">');
  });
});
