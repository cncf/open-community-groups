import { expect } from "@open-wc/testing";

import { scopeCssRules } from "/static/js/site/docs-css-scope.js";

describe("site docs css scope", () => {
  it("scopes selector lists without splitting nested commas", () => {
    // Build CSS with a selector list and pseudo-class arguments.
    const css = '.button, a:is(.primary, .secondary), [data-label="A, B"] { color: red; }';

    // The helper scopes only top-level selectors.
    expect(scopeCssRules(css, ".ocg-docs-root")).to.equal(
      ".ocg-docs-root .button, .ocg-docs-root a:is(.primary, .secondary), " +
        '.ocg-docs-root [data-label="A, B"]{ color: red; }',
    );
  });

  it("replaces document root selectors with the docs scope", () => {
    // Build CSS with root-level selectors.
    const css = "html, body.ready, :root { --theme-color: #0094ff; }";

    // The helper replaces document roots instead of nesting below them.
    expect(scopeCssRules(css, ".ocg-docs-root")).to.equal(
      ".ocg-docs-root, .ocg-docs-root.ready, .ocg-docs-root{ --theme-color: #0094ff; }",
    );
  });

  it("scopes recursive at-rules while preserving global at-rules", () => {
    // Build CSS with one recursive at-rule and one global keyframes rule.
    const css =
      "@media (min-width: 768px) { .content { display: grid; } }" +
      "@keyframes fade { from { opacity: 0; } to { opacity: 1; } }";

    // The helper scopes nested selectors but keeps keyframes unchanged.
    expect(scopeCssRules(css, ".ocg-docs-root")).to.equal(
      "@media (min-width: 768px){.ocg-docs-root .content{ display: grid; } }" +
        "@keyframes fade{ from { opacity: 0; } to { opacity: 1; } }",
    );
  });
});
