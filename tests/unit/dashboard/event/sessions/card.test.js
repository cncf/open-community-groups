import { expect } from "@open-wc/testing";

import "/static/js/dashboard/event/sessions/card.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

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

    // Sessions without labels render no chips.
    element.session = { name: "Closing" };
    await element.updateComplete;
    expect(element.querySelector(".custom-badge")).to.equal(null);
  });
});
