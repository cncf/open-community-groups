import { expect, waitUntil } from "@open-wc/testing";

import "/static/js/dashboard/event/sessions/card.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

// Labels long enough to overflow a narrow card.
const LONG_LABELS = [
  {
    color: "#bfdbfe",
    event_label_id: "label-1",
    name: "Observability and platform engineering",
  },
  {
    color: "#fecaca",
    event_label_id: "label-2",
    name: "Cloud native security and compliance",
  },
  {
    color: "#bbf7d0",
    event_label_id: "label-3",
    name: "Developer experience and tooling",
  },
];

// Tailwind's sr-only rule; unit tests load no stylesheet.
const SR_ONLY_CSS = `.sr-only {
  border-width: 0;
  clip-path: inset(50%);
  height: 1px;
  margin: -1px;
  overflow: hidden;
  padding: 0;
  position: absolute;
  white-space: nowrap;
  width: 1px;
}`;

describe("session-card", () => {
  useMountedElementsCleanup("session-card");

  it("renders session summary and dispatches action events", async () => {
    // Render a session card with speaker overflow.
    const element = await mountLitComponent("session-card", {
      session: {
        name: "Opening Keynote",
        kind: "talk",
        starts_at: "2025-05-10T09:00",
        ends_at: "2025-05-10T10:00",
        location: "Main Hall",
        speakers: [
          { name: "Ada Lovelace", username: "ada", featured: true },
          { name: "Grace Hopper", username: "grace" },
          { name: "Katherine Johnson", username: "katherine" },
          { name: "Margaret Hamilton", username: "margaret" },
          { name: "Radia Perlman", username: "radia" },
          { name: "Hedy Lamarr", username: "hedy" },
        ],
      },
      sessionKinds: [{ session_kind_id: "talk", display_name: "Talk" }],
    });
    const events = [];
    element.addEventListener("edit", () => events.push("edit"));
    element.addEventListener("delete", () => events.push("delete"));

    // Trigger the card action buttons.
    element.querySelector('button[title="Edit"]').click();
    element.querySelector('button[title="Delete"]').click();

    // The card renders summary text and bubbles action events.
    expect(element.textContent).to.include("09:00");
    expect(element.textContent).to.include("10:00");
    expect(element.textContent).to.include("Opening Keynote");
    expect(element.textContent).to.include("Talk · Main Hall");
    expect(element.textContent).to.include("+1");
    expect(element.firstElementChild.classList.contains("hover:border-primary-300")).to.equal(true);
    expect(element.firstElementChild.classList.contains("hover:shadow-sm")).to.equal(true);
    expect(events).to.deep.equal(["edit", "delete"]);
  });

  it("does not render rollover styles when disabled", async () => {
    // Render a disabled session card.
    const element = await mountLitComponent("session-card", {
      disabled: true,
      session: { name: "Past session" },
    });

    // Disabled cards and actions do not expose interactive rollover styles.
    expect(element.firstElementChild.classList.contains("hover:border-primary-300")).to.equal(false);
    expect(element.firstElementChild.classList.contains("hover:shadow-sm")).to.equal(false);
    expect(Array.from(element.querySelectorAll("button")).every((button) => button.disabled)).to.equal(true);
  });

  it("renders chips for the named labels assigned to the session", async () => {
    // Render a session card assigned to named, blank, and unknown labels.
    const element = await mountLitComponent("session-card", {
      labels: [
        { color: "#bfdbfe", event_label_id: "label-1", name: "Backend" },
        { color: "#fecaca", event_label_id: "label-2", name: " " },
        { color: "#bbf7d0", event_label_id: "label-3", name: "Unassigned" },
      ],
      session: {
        label_ids: ["label-1", "label-2", "unknown"],
        name: "Opening Keynote",
      },
    });

    // Only the assigned named label renders, with the shared chip color style.
    const chips = Array.from(element.querySelectorAll(".custom-badge"));
    expect(chips.map((chip) => chip.textContent.trim())).to.deep.equal(["Backend"]);
    expect(chips[0].getAttribute("style")).to.include("--label-color:#bfdbfe");

    // Sessions without labels render no labels row but keep the labeled card height.
    element.session = { name: "Closing" };
    await settleCard(element);
    expect(element.querySelector("[data-session-labels]")).to.equal(null);
    const content = element.querySelector("[data-session-content]");
    expect(content.classList.contains("min-h-[4.625rem]")).to.equal(true);
    expect(content.classList.contains("justify-center")).to.equal(true);
  });

  it("does not reserve labels height when the event has no named labels", async () => {
    // Render a session card for an event without named labels.
    const element = await mountLitComponent("session-card", {
      labels: [{ color: "#bfdbfe", event_label_id: "label-1", name: " " }],
      session: { label_ids: ["label-1"], name: "Opening Keynote" },
    });

    // No labels row or labeled card height is reserved.
    expect(element.querySelector("[data-session-labels]")).to.equal(null);
    expect(element.querySelector("[data-session-content]").classList.contains("min-h-[4.625rem]")).to.equal(
      false,
    );
  });

  it("stretches the time bar to the card content height", async () => {
    // Render a session card.
    const element = await mountLitComponent("session-card", {
      session: { name: "Opening Keynote" },
    });

    // The time bar stretches instead of using a fixed height.
    const bar = element.querySelector(".bg-primary-300");
    expect(bar.classList.contains("self-stretch")).to.equal(true);
    expect(bar.classList.contains("h-10")).to.equal(false);
  });

  it("collapses overflowing labels behind a counter with a tooltip", async () => {
    // Render a narrow session card with long labels.
    const element = await mountNarrowCard("Opening Keynote");

    // Only the first label stays visible and the counter shows the hidden labels.
    const chips = Array.from(element.querySelectorAll(".custom-badge"));
    const moreTrigger = element.querySelector("[data-session-labels-more]");
    const moreButton = moreTrigger.querySelector("button");
    expect(chips.map((chip) => chip.textContent.trim())).to.deep.equal([LONG_LABELS[0].name]);
    expect(moreTrigger.textContent.trim().startsWith("+2")).to.equal(true);
    expect(normalizeWhitespace(moreButton.textContent)).to.equal("+2 more labels");

    // The counter tooltip lists every assigned label.
    const tooltip = element.querySelector('[role="tooltip"]');
    expect(moreButton.getAttribute("aria-describedby")).to.equal(tooltip.id);
    expect(tooltip.hasAttribute("data-tooltip-panel")).to.equal(true);
    expect(
      Array.from(tooltip.querySelectorAll("[data-session-label-name]")).map((chip) =>
        chip.textContent.trim(),
      ),
    ).to.deep.equal(LONG_LABELS.map((label) => label.name));

    // Widening the card shows every label and removes the counter.
    element.style.width = "4000px";
    await waitUntil(() => element.querySelectorAll(".custom-badge").length === LONG_LABELS.length);
    expect(element.querySelector("[data-session-labels-more]")).to.equal(null);
  });

  it("uses unique tooltip ids per card", async () => {
    // Render two narrow cards with overflowing labels.
    const cards = [await mountNarrowCard("First"), await mountNarrowCard("Second")];

    // Each card references its own tooltip.
    const ids = cards.map((card) => card.querySelector('[role="tooltip"]')?.id);
    expect(ids[0]).to.be.a("string");
    expect(ids[0]).to.not.equal(ids[1]);
  });

  it("renders the counter as a tooltip trigger next to its panel", async () => {
    // Render a narrow session card with long labels.
    const element = await mountNarrowCard("Opening Keynote");

    // The wrapper holds the trigger button and its tooltip panel as siblings.
    const moreTrigger = element.querySelector("[data-session-labels-more]");
    const moreButton = moreTrigger.querySelector(":scope > button");
    const tooltip = moreTrigger.querySelector(":scope > [role='tooltip'][data-tooltip-panel]");
    expect(moreButton.getAttribute("aria-describedby")).to.equal(tooltip.id);
    expect(moreButton.contains(tooltip)).to.equal(false);

    // The trigger only uses tooltip semantics, with its name taken from its text.
    expect(moreButton.hasAttribute("aria-expanded")).to.equal(false);
    expect(moreButton.hasAttribute("aria-controls")).to.equal(false);
    expect(moreButton.hasAttribute("aria-label")).to.equal(false);
  });

  it("names a single hidden label in the singular", async () => {
    // Render a narrow session card with two long labels.
    const element = await mountNarrowCard("Opening Keynote", { labels: LONG_LABELS.slice(0, 2) });

    // One chip stays visible and the counter names the hidden label.
    const moreButton = element.querySelector("[data-session-labels-more] button");
    expect(element.querySelectorAll(".custom-badge")).to.have.length(1);
    expect(normalizeWhitespace(moreButton.textContent)).to.equal("+1 more label");
  });

  it("moves every label to the counter when no chip fits", async () => {
    // Hide the counter's sr-only suffix as the stylesheet does, so the counter has its real width.
    const srOnlyStyle = document.createElement("style");
    srOnlyStyle.textContent = SR_ONLY_CSS;
    document.head.append(srOnlyStyle);

    try {
      // Render a narrow card, then leave less than the minimum chip width (48px) next to the counter.
      const element = await mountNarrowCard("Opening Keynote");
      const row = element.querySelector("[data-session-labels]");
      const counterWidth = element
        .querySelector("[data-session-labels-more] > button")
        .getBoundingClientRect().width;
      const chromeWidth = element.getBoundingClientRect().width - row.clientWidth;
      element.style.width = `${chromeWidth + counterWidth + 40}px`;
      await waitUntil(
        () => element.querySelector(".custom-badge") === null,
        "labels were not moved to the counter",
      );

      // No chip renders and the counter shows the labels total.
      const moreButton = element.querySelector("[data-session-labels-more] button");
      expect(normalizeWhitespace(moreButton.textContent)).to.equal("3 labels");
      expect(element.querySelectorAll("[data-session-label-name]")).to.have.length(LONG_LABELS.length);
    } finally {
      srOnlyStyle.remove();
    }
  });

  it("fits the labels after a hidden container is shown", async () => {
    // Render a narrow session card inside a hidden container.
    const container = document.createElement("div");
    container.hidden = true;
    document.body.append(container);
    const element = await mountNarrowCard("Opening Keynote", { parent: container });

    // Showing the container fits the labels behind the counter.
    container.hidden = false;
    await waitUntil(() => isFittedBehindCounter(element), "labels were not fitted after showing");
  });

  it("fits the labels again after the card is hidden and shown", async () => {
    // Render a narrow session card inside a visible container.
    const container = document.createElement("div");
    document.body.append(container);
    const element = await mountNarrowCard("Opening Keynote", { parent: container });
    await waitUntil(() => isFittedBehindCounter(element), "labels were not fitted on first show");

    // Hiding the container drops the fit until the card has a width again.
    container.hidden = true;
    await waitUntil(
      () => element.querySelectorAll(".custom-badge").length === LONG_LABELS.length,
      "labels were not measured again after hiding",
    );

    // Showing the container fits the labels again.
    container.hidden = false;
    await waitUntil(() => isFittedBehindCounter(element), "labels were not fitted after showing again");
  });
});

/**
 * Checks whether a narrow card shows one chip and the "+2" counter.
 * @param {HTMLElement} element Session card element.
 * @returns {boolean} Whether the labels are fitted behind the counter.
 */
const isFittedBehindCounter = (element) =>
  element.querySelectorAll(".custom-badge").length === 1 &&
  normalizeWhitespace(element.querySelector("[data-session-labels-more] button")?.textContent || "") ===
    "+2 more labels";

/**
 * Mounts a narrow session card assigned to every given label.
 * @param {string} name Session name.
 * @param {{labels?: Array<Object>, parent?: HTMLElement, width?: string}} [options] Labels, the
 *   element the card is appended to and the card width.
 * @returns {Promise<HTMLElement>} Settled session card.
 */
const mountNarrowCard = async (
  name,
  { labels = LONG_LABELS, parent = document.body, width = "200px" } = {},
) => {
  const element = document.createElement("session-card");
  element.style.display = "block";
  element.style.width = width;
  Object.assign(element, {
    labels,
    session: {
      label_ids: labels.map((label) => label.event_label_id),
      name,
    },
  });
  parent.append(element);
  await settleCard(element);
  return element;
};

/**
 * Collapses whitespace runs and trims the result.
 * @param {string} value Text to normalize.
 * @returns {string} Normalized text.
 */
const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

/**
 * Waits until the card finishes its labels measurement updates.
 * @param {HTMLElement} element Session card element.
 * @returns {Promise<void>}
 */
const settleCard = async (element) => {
  while (!(await element.updateComplete)) {
    // Keep waiting while the labels fit schedules another update.
  }
};
