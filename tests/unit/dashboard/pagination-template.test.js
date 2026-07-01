import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/macros/pagination.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("pagination macros template", () => {
  it("supports explicit plural labels for range displays", async () => {
    // Load the pagination macros template before checking range copy.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify irregular and multi-word labels can provide their exact plural.
    expect(template).to.include(
      'macro range_display(offset, count, total, label = "result", plural_label = "")',
    );
    expect(template).to.include("plural_label != \"\"");
    expect(template).to.include("{{ plural_label }}");
  });
});
