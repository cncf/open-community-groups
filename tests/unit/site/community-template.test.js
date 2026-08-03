import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/community/page.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("community page template", () => {
  it("exposes the community name as the page heading", async () => {
    // Load the public community template before checking its heading structure.
    const template = normalizeWhitespace(await loadTemplate());

    // Preserve the visible breadcrumb while exposing the page name to assistive technology.
    expect(template).to.include(
      '<h1 class="sr-only">{{ community.display_name }}</h1>',
    );
  });
});
