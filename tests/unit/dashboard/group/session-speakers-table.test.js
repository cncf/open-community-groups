import { expect } from "@open-wc/testing";

import "/static/js/dashboard/group/session-speakers-table.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("session-speakers-table", () => {
  useMountedElementsCleanup("session-speakers-table");

  it("deduplicates speakers and lists sessions with their featured state", async () => {
    const speaker = { user_id: "21", username: "grace", name: "Grace Hopper" };
    const element = await mountLitComponent("session-speakers-table", {
      canAwardBadges: true,
      eventId: "event-1",
      sessions: [
        { name: "Opening", speakers: [{ ...speaker, featured: false }] },
        { name: "Closing", speakers: [{ ...speaker, featured: true }] },
      ],
    });

    const tableHeaders = [...element.querySelectorAll("th")].map((header) => header.textContent.trim());
    const speakerRows = element.querySelectorAll("tbody tr");

    expect(tableHeaders).to.deep.equal(["Speaker", "Featured speaker", "Sessions", "Actions"]);
    expect(speakerRows).to.have.length(1);
    expect(speakerRows[0].children[1].querySelector(".icon-star")).to.not.equal(null);
    expect(element.textContent).to.include("Closing, Opening");
    expect(element.querySelector("[data-badge-award-open]").dataset.userIds).to.equal("21");

    element.awardsDisabled = true;
    await element.updateComplete;
    expect(element.querySelector("[data-badge-award-open]").disabled).to.equal(true);
  });
});
