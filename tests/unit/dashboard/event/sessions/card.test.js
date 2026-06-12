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
    expect(events).to.deep.equal(["edit", "delete"]);
  });
});
