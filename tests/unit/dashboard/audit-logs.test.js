import { expect } from "@open-wc/testing";

import { initializeAuditLogs } from "/static/js/dashboard/audit-logs.js";
import { waitForAnimationFrames } from "/tests/unit/test-utils/async.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("dashboard audit logs", () => {
  const buildAuditLogsFixture = () => {
    document.body.innerHTML = `
      <button id="open-audit-log-filters-modal" type="button"></button>
      <span id="audit-log-filters-active-indicator" class="hidden"></span>
      <div id="audit-log-filters-modal" class="hidden">
        <div id="overlay-audit-log-filters-modal"></div>
        <button id="close-audit-log-filters-modal" type="button"></button>
        <form id="audit-log-filters-form">
          <select id="audit-action" name="action">
            <option value="">All actions</option>
            <option value="member-added" selected>Member added</option>
          </select>
          <input id="audit-actor" name="actor" value="">
          <input id="audit-date-from" name="date_from" value="">
          <input id="audit-date-to" name="date_to" value="">
          <a id="reset-audit-log-filters" href="/dashboard/logs">Reset</a>
        </form>
      </div>
      <div data-audit-log-details-group>
        <button
          type="button"
          data-audit-log-details-trigger
          aria-controls="audit-log-details-1"
          aria-expanded="false"
        ></button>
        <div id="audit-log-details-1" data-audit-log-details-card class="hidden"></div>
      </div>
      <div data-audit-log-details-group>
        <button
          type="button"
          data-audit-log-details-trigger
          aria-controls="audit-log-details-2"
          aria-expanded="false"
        ></button>
        <div id="audit-log-details-2" data-audit-log-details-card class="hidden"></div>
      </div>
    `;
  };

  beforeEach(() => {
    resetDom();
    buildAuditLogsFixture();
  });

  afterEach(() => {
    resetDom();
  });

  it("initializes filter modal controls once", () => {
    // Run initialization twice to verify modal event handlers are not duplicated.
    initializeAuditLogs();
    initializeAuditLogs();

    // Verify active filters are reflected on the filter button.
    expect(
      document
        .getElementById("audit-log-filters-active-indicator")
        .classList.contains("hidden"),
    ).to.equal(false);
    expect(
      document
        .getElementById("open-audit-log-filters-modal")
        .getAttribute("aria-pressed"),
    ).to.equal("true");

    // Open and close the modal to verify one click produces one toggle.
    document.getElementById("open-audit-log-filters-modal").click();
    expect(
      document
        .getElementById("audit-log-filters-modal")
        .classList.contains("hidden"),
    ).to.equal(false);

    document.getElementById("close-audit-log-filters-modal").click();
    expect(
      document
        .getElementById("audit-log-filters-modal")
        .classList.contains("hidden"),
    ).to.equal(true);
  });

  it("toggles details popovers from the document handlers", () => {
    // Initialize details popover behavior.
    initializeAuditLogs();

    const trigger = document.querySelector("[data-audit-log-details-trigger]");
    const card = document.getElementById("audit-log-details-1");

    // Open the details popover from its trigger.
    trigger.click();
    expect(trigger.getAttribute("aria-expanded")).to.equal("true");
    expect(card.classList.contains("hidden")).to.equal(false);

    // Close the details popover from an outside click.
    document.body.click();
    expect(trigger.getAttribute("aria-expanded")).to.equal("false");
    expect(card.classList.contains("hidden")).to.equal(true);
  });

  it("keeps a hovered previous popover hidden when another opens", () => {
    // Simulate the pointer remaining over the first trigger group.
    const groups = document.querySelectorAll("[data-audit-log-details-group]");
    const triggers = document.querySelectorAll("[data-audit-log-details-trigger]");
    const firstCard = document.getElementById("audit-log-details-1");
    const secondCard = document.getElementById("audit-log-details-2");
    Object.defineProperty(groups[0], "matches", {
      value: (selector) => selector === ":hover",
    });
    initializeAuditLogs();

    // Open each trigger in turn as a keyboard user can.
    triggers[0].click();
    triggers[1].click();

    // Keep the visual and accessible states synchronized.
    expect(groups[0].getAttribute("data-audit-log-hover-disabled")).to.equal(
      "true",
    );
    expect(triggers[0].getAttribute("aria-expanded")).to.equal("false");
    expect(firstCard.classList.contains("hidden")).to.equal(true);
    expect(triggers[1].getAttribute("aria-expanded")).to.equal("true");
    expect(secondCard.classList.contains("hidden")).to.equal(false);
  });

  it("places a clicked popover above its trigger when there is no room below", () => {
    // Put the first row near the viewport bottom with a card overflowing below.
    const trigger = document.querySelector("[data-audit-log-details-trigger]");
    const card = document.getElementById("audit-log-details-1");
    stubDetailsGeometry(card, {
      cardBottom: window.innerHeight + 200,
      groupBottom: window.innerHeight - 30,
      groupTop: window.innerHeight - 60,
    });
    initializeAuditLogs();

    // Open the details popover from its trigger.
    trigger.click();

    // Verify the card flips above the trigger.
    expect(trigger.getAttribute("aria-expanded")).to.equal("true");
    expect(card.getAttribute("data-placement")).to.equal("top");
  });

  it("keeps a popover that fits below its trigger in the default placement", () => {
    // Put the first row near the viewport top with a card that fits below.
    const trigger = document.querySelector("[data-audit-log-details-trigger]");
    const card = document.getElementById("audit-log-details-1");
    stubDetailsGeometry(card, {
      cardBottom: 300,
      groupBottom: 130,
      groupTop: 100,
    });
    initializeAuditLogs();

    // Open the details popover from its trigger.
    trigger.click();

    // Verify the card keeps no placement attribute.
    expect(card.hasAttribute("data-placement")).to.equal(false);
  });

  it("clears a previous top placement before measuring a reopened popover", () => {
    // Open the first row popover while it has no room below.
    const trigger = document.querySelector("[data-audit-log-details-trigger]");
    const card = document.getElementById("audit-log-details-1");
    const geometry = stubDetailsGeometry(card, {
      cardBottom: window.innerHeight + 200,
      groupBottom: window.innerHeight - 30,
      groupTop: window.innerHeight - 60,
    });
    initializeAuditLogs();
    trigger.click();
    expect(card.getAttribute("data-placement")).to.equal("top");

    // Close it, scroll the row up and reopen it.
    trigger.click();
    Object.assign(geometry, {
      cardBottom: 300,
      groupBottom: 130,
      groupTop: 100,
    });
    geometry.placementsSeen.length = 0;
    trigger.click();

    // Verify the card is measured in the default placement and stays there.
    expect(geometry.placementsSeen).to.deep.equal([null]);
    expect(card.hasAttribute("data-placement")).to.equal(false);
  });

  it("measures the hovered popover when the pointer enters its group", () => {
    // Put the first row near the viewport bottom with a card overflowing below.
    const group = document.querySelector("[data-audit-log-details-group]");
    const card = document.getElementById("audit-log-details-1");
    stubDetailsGeometry(card, {
      cardBottom: window.innerHeight + 200,
      groupBottom: window.innerHeight - 30,
      groupTop: window.innerHeight - 60,
    });
    initializeAuditLogs();

    // Hover the details group.
    group.dispatchEvent(new MouseEvent("mouseenter"));

    // Verify the hovered card flips above the trigger.
    expect(card.getAttribute("data-placement")).to.equal("top");
  });

  it("retries the hover measurement once the card is rendered", async () => {
    // Report the card as unrendered until the hover styles apply.
    const group = document.querySelector("[data-audit-log-details-group]");
    const card = document.getElementById("audit-log-details-1");
    const geometry = stubDetailsGeometry(card, {
      cardBottom: window.innerHeight + 200,
      groupBottom: window.innerHeight - 30,
      groupTop: window.innerHeight - 60,
      rendered: false,
    });
    initializeAuditLogs();

    // Hover the details group, then let the card render before the next frame.
    group.dispatchEvent(new MouseEvent("mouseenter"));
    expect(card.hasAttribute("data-placement")).to.equal(false);
    geometry.rendered = true;
    await waitForAnimationFrames(1);

    // Verify the retry flips the card above the trigger.
    expect(card.getAttribute("data-placement")).to.equal("top");
  });

  it("leaves an unrendered popover without a placement", async () => {
    // Report the card as unrendered even though it would overflow below.
    const group = document.querySelector("[data-audit-log-details-group]");
    const card = document.getElementById("audit-log-details-1");
    stubDetailsGeometry(card, {
      cardBottom: window.innerHeight + 200,
      groupBottom: window.innerHeight - 30,
      groupTop: window.innerHeight - 60,
      rendered: false,
    });
    initializeAuditLogs();

    // Hover the details group and wait for the retry frame.
    group.dispatchEvent(new MouseEvent("mouseenter"));
    await waitForAnimationFrames(1);

    // Verify the card is never placed.
    expect(card.hasAttribute("data-placement")).to.equal(false);
  });

  it("initializes swapped audit log content on htmx load", () => {
    // Dispatch the lifecycle event used by swapped dashboard content.
    dispatchHtmxLoad(document.body);

    // Verify the swapped content is bound without calling the initializer directly.
    expect(document.getElementById("audit-log-filters-modal").dataset.bound).to.equal(
      "true",
    );
    expect(
      document
        .querySelector("[data-audit-log-details-group]")
        .getAttribute("data-audit-log-hover-bound"),
    ).to.equal("true");
  });
});

/**
 * Stubs the measured geometry of a details card and its group.
 * @param {HTMLElement} card - Details popover card.
 * @param {{cardBottom: number, groupBottom: number, groupTop: number, rendered?: boolean}} options
 *   Viewport coordinates and whether the card has client rects.
 * @returns {{cardBottom: number, groupBottom: number, groupTop: number, placementsSeen: Array<string|null>,
 *   rendered: boolean}} Mutable geometry read by the stubs, plus the card placement seen on each measure.
 */
const stubDetailsGeometry = (card, { rendered = true, ...coordinates }) => {
  const geometry = { ...coordinates, placementsSeen: [], rendered };
  const group = card.closest("[data-audit-log-details-group]");

  card.getClientRects = () => (geometry.rendered ? [{}] : []);
  card.getBoundingClientRect = () => {
    geometry.placementsSeen.push(card.getAttribute("data-placement"));
    return { bottom: geometry.cardBottom, top: geometry.groupBottom };
  };
  group.getBoundingClientRect = () => ({
    bottom: geometry.groupBottom,
    top: geometry.groupTop,
  });

  return geometry;
};
