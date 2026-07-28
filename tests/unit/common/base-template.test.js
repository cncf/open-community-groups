import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/common/base.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("common base template", () => {
  it("uses the OCG favicon when no custom favicon is configured", async () => {
    // Load the base template before checking favicon sources.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify custom favicon URLs remain supported.
    expect(template).to.include('href="{{ favicon_url }}" sizes="any"');

    // Verify pages fall back to the default OCG favicon.
    expect(template).to.include('href="/static/images/favicon.svg" type="image/svg+xml" sizes="any"');
  });
});
