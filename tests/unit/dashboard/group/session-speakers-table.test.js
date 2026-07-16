import { expect } from "@open-wc/testing";

import "/static/js/dashboard/group/session-speakers-table.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("session-speakers-table", () => {
  useMountedElementsCleanup("session-speakers-table");

  it("deduplicates speakers and lists every associated session", async () => {
    const speaker = { user_id: "21", username: "grace", name: "Grace Hopper" };
    const element = await mountLitComponent("session-speakers-table", {
      canAwardBadges: true,
      eventId: "event-1",
      sessions: [
        { name: "Opening", speakers: [speaker] },
        { name: "Closing", speakers: [speaker] },
      ],
    });

    expect(element.querySelectorAll("tbody tr")).to.have.length(1);
    expect(element.textContent).to.include("Closing, Opening");
    expect(element.querySelector("[data-badge-award-open]").dataset.userIds).to.equal("21");

    element.awardsDisabled = true;
    await element.updateComplete;
    expect(element.querySelector("[data-badge-award-open]").disabled).to.equal(true);
  });
});
