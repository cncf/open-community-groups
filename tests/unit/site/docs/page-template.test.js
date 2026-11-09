import { expect } from "@open-wc/testing";

/**
 * Loads a repository file served by the test runner.
 * @param {string} path - Repository path.
 * @returns {Promise<string>} File text.
 */
const loadFile = async (path) => {
  const response = await fetch(path);

  expect(response.ok, path).to.equal(true);

  return response.text();
};

describe("site docs phone shell", () => {
  it("renders the Contents bar before the Docsify mount and hides it off phones", async () => {
    const template = await loadFile("/ocg-server/templates/site/docs/page.html");

    // Verify the bar keeps overflow-hidden on desktop and sits outside the app node.
    expect(template).to.include("relative overflow-hidden phone:overflow-visible");
    expect(template.indexOf("data-docs-bar")).to.be.lessThan(template.indexOf('id="ocg-docs-app"'));
    expect(template).to.include('<div class="cta-bar not-phone:hidden" data-docs-bar>');
    expect(template).to.include("data-docs-bar-section>Documentation</p>");
    expect(template).to.include("data-docs-bar-page></p>");
  });

  it("keeps every shell.css phone rule behind the bar gate", async () => {
    const stylesheet = await loadFile("/ocg-server/static/docs/assets/shell.css");
    const opening = "@media screen and (width < 48rem) and (not (pointer: fine)) {";

    // Verify one phone block closes the file.
    expect(stylesheet.split(opening)).to.have.length(2);
    const block = stylesheet.slice(stylesheet.indexOf(opening) + opening.length);

    // Verify each selector needs the bar, so older cached HTML keeps today's layout.
    const selectors = block.match(/^[^{}@/]*\{/gmu).map((selector) => selector.trim());
    expect(selectors.length).to.be.greaterThan(20);
    selectors
      .filter((selector) => selector !== "{")
      .forEach((selector) => {
        expect(selector, selector).to.include("[data-docs-bar]");
      });
  });
});
