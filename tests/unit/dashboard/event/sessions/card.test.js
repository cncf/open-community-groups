import { expect, waitUntil } from "@open-wc/testing";

import "/static/js/dashboard/event/sessions/card.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

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
    expect(Array.from(element.querySelectorAll("button")).every((button) => button.disabled)).to.equal(
      true,
    );
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
    expect(
      element.querySelector("[data-session-content]").classList.contains("min-h-[4.625rem]"),
    ).to.equal(false);
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
    const moreButton = element.querySelector("[data-session-labels-more]");
    expect(chips.map((chip) => chip.textContent.trim())).to.deep.equal([LONG_LABELS[0].name]);
    expect(moreButton.textContent.trim().startsWith("+2")).to.equal(true);
    expect(moreButton.getAttribute("aria-label")).to.equal("2 more labels");

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
});

/**
 * Mounts a 200px wide session card assigned to every long label.
 * @param {string} name Session name.
 * @returns {Promise<HTMLElement>} Settled session card.
 */
const mountNarrowCard = async (name) => {
  const element = document.createElement("session-card");
  element.style.display = "block";
  element.style.width = "200px";
  Object.assign(element, {
    labels: LONG_LABELS,
    session: {
      label_ids: LONG_LABELS.map((label) => label.event_label_id),
      name,
    },
  });
  document.body.append(element);
  await settleCard(element);
  return element;
};

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
