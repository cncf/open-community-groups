import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/events_add.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group event add template", () => {
  it("keeps bottom actions in the main grid column", async () => {
    // Load the event add template before checking grid placement classes.
    const template = normalizeWhitespace(await loadTemplate());

    // Assert root-level actions after the form wrapper stay in the form column.
    expect(template).to.include(
      'class="flex flex-wrap items-center justify-end gap-3 mt-6 px-4 lg:col-start-2 lg:px-0"',
    );
  });
});
