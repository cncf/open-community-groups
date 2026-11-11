import { expect } from "@open-wc/testing";

import { initializeAgendaBadges, CLAMP_MEDIA_QUERY } from "/static/js/event/agenda-badges.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { stubMatchMedia } from "/tests/unit/test-utils/media.js";

// Two 50px badges plus the 4px gap fit the 110px row, so a third badge wraps.
const BADGE_WIDTH = 50;
const ROW_WIDTH = 110;

/** Waits for a ResizeObserver callback and its layout to settle. */
const settle = () =>
  new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));

/**
 * Renders a clamped badge row with fixed-size badges that wrap predictably.
 * @param {number} count Number of badges to render.
 * @returns {HTMLElement} Badge row container.
 */
const renderRow = (count) => {
  const row = document.createElement("div");
  row.dataset.badgeClamp = "";
  row.style.cssText = `display:flex;flex-wrap:wrap;align-content:flex-start;gap:4px;width:${ROW_WIDTH}px`;
  for (let index = 0; index < count; index += 1) {
    const badge = document.createElement("span");
    badge.textContent = `L${index}`;
    badge.style.cssText = `display:inline-block;box-sizing:border-box;width:${BADGE_WIDTH}px;height:14px`;
    row.append(badge);
  }
  document.body.append(row);
  return row;
};

/**
 * Counts the distinct top offsets of the still-visible elements.
 * @param {HTMLElement[]} elements Candidate elements.
 * @returns {number} Number of occupied lines.
 */
const visibleLineCount = (elements) => {
  const tops = [];
  elements
    .filter((element) => !element.hidden)
    .forEach((element) => {
      const top = element.getBoundingClientRect().top;
      if (!tops.some((value) => Math.abs(value - top) <= 1)) {
        tops.push(top);
      }
    });
  return tops.length;
};

describe("agenda badges clamp", () => {
  let media;

  beforeEach(() => {
    resetDom();
    // The clamp only runs on narrow layouts, so simulate one.
    media = stubMatchMedia({ [CLAMP_MEDIA_QUERY]: true });
  });

  afterEach(() => {
    media.restore();
    resetDom();
  });

  it("folds badges past the visible lines behind a +N toggle", async () => {
    const row = renderRow(8);

    initializeAgendaBadges(document);
    await settle();

    const badges = Array.from(row.querySelectorAll("span"));
    const toggle = row.querySelector("button");

    // The toggle appears with a count and some badges stay folded.
    expect(toggle.hidden).to.equal(false);
    expect(toggle.textContent).to.match(/^\+\d+$/);
    expect(toggle.getAttribute("aria-expanded")).to.equal("false");
    expect(badges.some((badge) => badge.hidden)).to.equal(true);

    // The visible badges and the toggle never spill past two lines.
    expect(visibleLineCount([...badges, toggle])).to.be.at.most(2);
  });

  it("keeps a short list fully visible without a toggle", async () => {
    const row = renderRow(2);

    initializeAgendaBadges(document);
    await settle();

    const badges = Array.from(row.querySelectorAll("span"));
    const toggle = row.querySelector("button");

    expect(toggle.hidden).to.equal(true);
    expect(badges.every((badge) => !badge.hidden)).to.equal(true);
  });

  it("leaves every badge visible on desktop", async () => {
    // Desktop keeps the previous wrapped layout with no fold.
    media.setMatches(CLAMP_MEDIA_QUERY, false);
    const row = renderRow(8);

    initializeAgendaBadges(document);
    await settle();

    const badges = Array.from(row.querySelectorAll("span"));
    const toggle = row.querySelector("button");

    expect(toggle.hidden).to.equal(true);
    expect(badges.every((badge) => !badge.hidden)).to.equal(true);
  });

  it("expands and collapses on toggle click", async () => {
    const row = renderRow(8);

    initializeAgendaBadges(document);
    await settle();

    const badges = Array.from(row.querySelectorAll("span"));
    const toggle = row.querySelector("button");

    // Expanding reveals every badge and relabels the toggle.
    toggle.click();
    expect(badges.every((badge) => !badge.hidden)).to.equal(true);
    expect(toggle.textContent).to.equal("Show less");
    expect(toggle.getAttribute("aria-expanded")).to.equal("true");

    // Collapsing folds the overflow again.
    toggle.click();
    expect(badges.some((badge) => badge.hidden)).to.equal(true);
    expect(toggle.textContent).to.match(/^\+\d+$/);
    expect(toggle.getAttribute("aria-expanded")).to.equal("false");
  });

  it("re-folds a bound row when the viewport becomes narrow", async () => {
    // Start on desktop: the full list stays visible with no toggle.
    media.setMatches(CLAMP_MEDIA_QUERY, false);
    const row = renderRow(8);

    initializeAgendaBadges(document);
    await settle();

    const badges = Array.from(row.querySelectorAll("span"));
    const toggle = row.querySelector("button");
    expect(toggle.hidden).to.equal(true);

    // Narrowing drives the media-change listener, which re-clamps the row.
    media.setMatches(CLAMP_MEDIA_QUERY, true);
    await settle();

    expect(toggle.hidden).to.equal(false);
    expect(badges.some((badge) => badge.hidden)).to.equal(true);
  });

  it("drops a stale toggle from a restored snapshot instead of binding it as a badge", async () => {
    const row = renderRow(8);

    // Simulate an htmx history snapshot: a previously injected toggle serialized into the row.
    const stale = document.createElement("button");
    stale.type = "button";
    stale.dataset.badgeToggle = "";
    stale.textContent = "+3";
    row.append(stale);

    initializeAgendaBadges(document);
    await settle();

    const toggles = row.querySelectorAll("[data-badge-toggle]");
    const badges = Array.from(row.querySelectorAll("span"));

    // The stale toggle is removed and exactly one freshly bound toggle remains.
    expect(stale.isConnected).to.equal(false);
    expect(toggles.length).to.equal(1);
    expect(toggles[0]).to.not.equal(stale);

    // The fold math used only the real badges, and the fresh toggle works.
    const toggle = toggles[0];
    expect(toggle.hidden).to.equal(false);
    expect(toggle.textContent).to.match(/^\+\d+$/);
    expect(badges.some((badge) => badge.hidden)).to.equal(true);

    toggle.click();
    expect(badges.every((badge) => !badge.hidden)).to.equal(true);
  });
});
