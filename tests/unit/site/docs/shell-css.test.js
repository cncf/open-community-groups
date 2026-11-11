import { expect } from "@open-wc/testing";

import { scopeCssRules } from "/static/js/site/docs/css-scope.js";

// Docs stylesheets, served from the content-hashed CSS tree.
const DOCS_STYLESHEETS = ["/ocg-server/static/css/docs/shell.css", "/ocg-server/static/css/docs/theme.css"];

// A color value: hex, a color function, a token read or a named color keyword.
const COLOR_VALUE =
  /#[0-9a-f]{3,8}\b|\b(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch|color|color-mix)\(|var\(--color-|\b(?:black|currentcolor|transparent|white)\b/iu;

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

/**
 * Lists the declarations of a stylesheet, comments removed.
 * @param {string} css - Stylesheet text.
 * @returns {{property: string, value: string}[]} Declarations in source order.
 */
const listDeclarations = (css) =>
  [...css.replace(/\/\*[\s\S]*?\*\//gu, "").matchAll(/([-\w]+)\s*:\s*([^;{}]+);/gu)].map(
    ([, property, value]) => ({ property, value: value.trim() }),
  );

describe("site docs shell stylesheet", () => {
  it("keeps every shell.css phone rule behind the bar gate", async () => {
    const stylesheet = await loadFile("/ocg-server/static/css/docs/shell.css");
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

  it("keeps theme.css free of color theme selectors once scoped", async () => {
    const stylesheet = await loadFile("/ocg-server/static/css/docs/theme.css");

    // Scoping rewrites html and :root, so a color theme selector would never match.
    const scoped = scopeCssRules(stylesheet, ".ocg-docs-root");
    expect(scoped).to.include(".ocg-docs-root");
    expect(scoped).not.to.include("data-theme");
  });

  it("paints every docs color through a token or a docs hook", async () => {
    for (const path of DOCS_STYLESHEETS) {
      const stylesheet = await loadFile(path);
      const declarations = listDeclarations(stylesheet);
      expect(declarations.length, path).to.be.greaterThan(50);

      // Verify the white and numbered primary shades are never read directly.
      expect(stylesheet, path).not.to.include("var(--color-white)");
      expect(stylesheet, path).not.to.match(/var\(--color-primary-\d/u);

      declarations.forEach(({ property, value }) => {
        const declaration = `${path}: ${property}: ${value}`;

        // Verify each hex color is the fallback of a custom property, so light keeps it.
        const unwrapped = value.replace(/var\(--[-\w]+,\s*#[0-9a-f]{3,8}\)/giu, "");
        expect(unwrapped, declaration).not.to.match(/#[0-9a-f]{3,8}\b/iu);

        // Verify rgba() only tints shadows.
        if (/\brgba\(/u.test(value)) {
          expect(property, declaration).to.equal("box-shadow");
        }

        // Verify the docs hooks get their colors only from the dark rule in styles.src.css.
        if (property.startsWith("--ocg-docs-")) {
          expect(value, declaration).not.to.match(COLOR_VALUE);
        }
      });
    }
  });
});
