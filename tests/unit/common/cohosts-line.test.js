import { expect } from "@open-wc/testing";

import { fitCohostsLines, hideCohostsPanel } from "/static/js/common/cohosts-line.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

const FULL_NAMES = "Co-hosted with Cloud Native Madrid, Green Software Madrid, Kubernetes Barcelona";

// Minimal stand-ins for the Tailwind utilities the fitting logic relies on.
const UTILITY_STYLES = `
  .hidden { display: none; }
  .sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; }
  .truncate { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
`;

/**
 * Renders a co-hosts credit line inside a card link of the given width.
 * @param {{width?: string}} [options] Fixture options.
 * @returns {{card: HTMLAnchorElement, full: HTMLElement, line: HTMLElement, summary: HTMLElement}}
 */
const renderLine = ({ width = "900px" } = {}) => {
  document.body.innerHTML = `
    <style>${UTILITY_STYLES}</style>
    <a href="/event" id="card" style="display: block; width: ${width}; font: 12px/16px sans-serif;">
      <span data-cohosts-line title="${FULL_NAMES}" style="display: flex; min-width: 0; max-width: 100%;">
        <span data-cohosts-full class="truncate">${FULL_NAMES}</span>
        <span data-cohosts-summary class="hidden truncate" aria-hidden="true">Co-hosted with 3 groups</span>
        <template data-cohosts-panel-template>
          <div data-cohosts-panel aria-hidden="true" style="position: fixed; width: 256px; height: 120px;">
            <ul>
              <li>Cloud Native Madrid</li>
              <li>Green Software Madrid</li>
              <li>Kubernetes Barcelona</li>
            </ul>
          </div>
        </template>
      </span>
    </a>
  `;

  const line = document.querySelector("[data-cohosts-line]");
  return {
    card: document.getElementById("card"),
    full: line.querySelector("[data-cohosts-full]"),
    line,
    summary: line.querySelector("[data-cohosts-summary]"),
  };
};

/**
 * Waits for a timer-driven hide to settle.
 * @param {number} ms Milliseconds to wait.
 * @returns {Promise<void>}
 */
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

describe("co-hosts line", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    hideCohostsPanel();
    resetDom();
  });

  it("keeps the full co-host names when they fit on one line", () => {
    // Render a credit with enough room for every name.
    const { full, line, summary } = renderLine();

    // Fit the rendered credit.
    fitCohostsLines(document);

    // Keep the full copy and its title for later hovers.
    expect(line.dataset.cohostsFit).to.equal("full");
    expect(line.getAttribute("title")).to.equal(FULL_NAMES);
    expect(full.classList.contains("truncate")).to.equal(true);
    expect(summary.classList.contains("hidden")).to.equal(true);
  });

  it("reduces overflowing names to a count while keeping them for screen readers", () => {
    // Render a credit that is too narrow for every name.
    const { full, line, summary } = renderLine({ width: "160px" });

    // Fit the rendered credit.
    fitCohostsLines(document);

    // Show the count and move the full names to screen-reader-only text.
    expect(line.dataset.cohostsFit).to.equal("summary");
    expect(line.hasAttribute("title")).to.equal(false);
    expect(full.classList.contains("sr-only")).to.equal(true);
    expect(full.classList.contains("truncate")).to.equal(false);
    expect(full.textContent).to.equal(FULL_NAMES);
    expect(summary.classList.contains("hidden")).to.equal(false);
  });

  it("measures each line once so later size changes never swap the copy", () => {
    // Fit a credit that has enough room.
    const { card, line, summary } = renderLine();
    fitCohostsLines(document);

    // Narrow the card and fit again.
    card.style.width = "160px";
    fitCohostsLines(document);

    // Keep the first decision.
    expect(line.dataset.cohostsFit).to.equal("full");
    expect(summary.classList.contains("hidden")).to.equal(true);
  });

  it("waits to measure lines that are not rendered yet", () => {
    // Render a narrow credit inside a hidden card.
    const { card, line } = renderLine({ width: "160px" });
    card.style.display = "none";

    // Skip the hidden credit.
    fitCohostsLines(document);
    expect(line.dataset.cohostsFit).to.equal(undefined);

    // Measure it once the card is shown.
    card.style.display = "block";
    fitCohostsLines(card);
    expect(line.dataset.cohostsFit).to.equal("summary");
  });

  it("drops the co-hosts panel below the hovered count and hides it after leaving", async () => {
    // Fit a reduced credit.
    const { summary } = renderLine({ width: "160px" });
    fitCohostsLines(document);

    // Hover the visible count.
    summary.dispatchEvent(new PointerEvent("pointerover", { bubbles: true }));

    // Render the panel in the body right below the count.
    const panel = document.body.querySelector(":scope > [data-cohosts-panel]");
    expect(panel).to.exist;
    expect(panel.textContent).to.include("Green Software Madrid");
    expect(panel.style.top).to.equal(`${summary.getBoundingClientRect().bottom + 4}px`);

    // Leave the count for an unrelated element.
    summary.dispatchEvent(new PointerEvent("pointerout", { bubbles: true, relatedTarget: document.body }));
    await wait(150);

    // Remove the panel after the hide delay.
    expect(document.body.querySelector(":scope > [data-cohosts-panel]")).to.equal(null);
  });

  it("keeps the panel open while the pointer moves from the count into it", async () => {
    // Open the panel from a reduced credit.
    const { summary } = renderLine({ width: "160px" });
    fitCohostsLines(document);
    summary.dispatchEvent(new PointerEvent("pointerover", { bubbles: true }));
    const panel = document.body.querySelector(":scope > [data-cohosts-panel]");

    // Move the pointer from the count into the panel.
    summary.dispatchEvent(new PointerEvent("pointerout", { bubbles: true, relatedTarget: panel }));
    await wait(150);

    // Keep the panel open.
    expect(panel.isConnected).to.equal(true);
  });

  it("does not open a panel for credits that show the full names", () => {
    // Fit a credit with enough room.
    const { summary } = renderLine();
    fitCohostsLines(document);

    // Hover the hidden count.
    summary.dispatchEvent(new PointerEvent("pointerover", { bubbles: true }));

    // Skip the panel.
    expect(document.body.querySelector(":scope > [data-cohosts-panel]")).to.equal(null);
  });

  it("dismisses the panel with Escape, when card focus leaves, and before HTMX history saves", () => {
    // Open the panel from a reduced credit.
    const { card, summary } = renderLine({ width: "160px" });
    fitCohostsLines(document);
    summary.dispatchEvent(new PointerEvent("pointerover", { bubbles: true }));

    // Press Escape.
    document.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));
    expect(document.body.querySelector(":scope > [data-cohosts-panel]")).to.equal(null);

    // Reopen the panel and move focus away from the card.
    summary.dispatchEvent(new PointerEvent("pointerover", { bubbles: true }));
    card.dispatchEvent(new FocusEvent("focusout", { bubbles: true }));
    expect(document.body.querySelector(":scope > [data-cohosts-panel]")).to.equal(null);

    // Reopen the panel and let HTMX snapshot the page before navigating.
    summary.dispatchEvent(new PointerEvent("pointerover", { bubbles: true }));
    document.dispatchEvent(new CustomEvent("htmx:beforeHistorySave", { bubbles: true }));
    expect(document.body.querySelector(":scope > [data-cohosts-panel]")).to.equal(null);
  });
});
