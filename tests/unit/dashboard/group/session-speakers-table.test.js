import { expect } from "@open-wc/testing";

import "/static/js/dashboard/group/session-speakers-table.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("session-speakers-table", () => {
  useMountedElementsCleanup("session-speakers-table");

  it("keeps the session speakers table visible with an empty-state row", async () => {
    // Render the table without session-level speakers.
    const element = await mountLitComponent("session-speakers-table", {
      canAwardBadges: true,
      eventId: "event-1",
      sessions: [],
    });
    const table = element.querySelector('table[aria-label="Session-level speakers"]');
    const emptyState = table.querySelector("tbody td");

    // Verify the stable columns and empty-state row.
    expect([...table.querySelectorAll("th")].map((header) => header.textContent.trim())).to.deep.equal([
      "Name",
      "Featured",
      "Sessions",
      "Actions",
    ]);
    expect(emptyState.textContent.trim()).to.equal("No session-level speakers added yet.");
    expect(emptyState.getAttribute("colspan")).to.equal("4");
    expect(emptyState.classList.contains("text-center")).to.equal(true);
  });

  it("deduplicates speakers and lists sessions with their featured state", async () => {
    // Render one speaker assigned to two sessions with mixed featured states.
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

    // Verify the speaker is deduplicated and retains every session relationship.
    expect(tableHeaders).to.deep.equal(["Name", "Featured", "Sessions", "Actions"]);
    expect(speakerRows).to.have.length(1);
    expect(speakerRows[0].children[1].querySelector(".icon-star").classList.contains("size-4")).to.equal(
      true,
    );
    expect(element.textContent).to.include("Closing, Opening");
    expect(element.querySelector("[data-badge-award-open]").dataset.userIds).to.equal("21");

    // Disable awards and verify the row action follows the table state.
    element.awardsDisabled = true;
    await element.updateComplete;
    expect(element.querySelector("[data-badge-award-open]").disabled).to.equal(true);
  });

  it("keeps non-featured session speaker cells visually empty", async () => {
    // Render a speaker that is not featured in any session.
    const element = await mountLitComponent("session-speakers-table", {
      sessions: [
        {
          name: "Opening",
          speakers: [{ user_id: "21", username: "grace", featured: false }],
        },
      ],
    });
    const featuredCell = element.querySelector("tbody tr").children[1];

    // Verify assistive text is retained without a visible placeholder glyph.
    expect(featuredCell.textContent.trim()).to.equal("No");
    expect(featuredCell.querySelector(".sr-only")).to.not.equal(null);
    expect(featuredCell.textContent).to.not.include("—");
  });

  it("marks featured session speakers in the identity cell without a title", async () => {
    // Render one featured and one regular session speaker.
    const element = await mountLitComponent("session-speakers-table", {
      sessions: [
        {
          name: "Opening",
          speakers: [
            { user_id: "21", username: "grace", name: "Grace Hopper", featured: true },
            { user_id: "22", username: "ada", name: "Ada Lovelace", featured: false },
          ],
        },
      ],
    });
    const rows = [...element.querySelectorAll("tbody tr")];
    const featuredRow = rows.find((row) => row.textContent.includes("Grace Hopper"));
    const regularRow = rows.find((row) => row.textContent.includes("Ada Lovelace"));
    const marker = featuredRow.children[0].querySelector("[data-featured-speaker-marker]");

    // Verify only the featured row carries the marker and its accessible text.
    expect(marker).to.not.equal(null);
    expect(marker.querySelector(".sr-only").textContent.trim()).to.equal("Featured speaker");
    expect(featuredRow.children[0].querySelector("[title]")).to.equal(null);
    expect(regularRow.children[0].querySelector("[data-featured-speaker-marker]")).to.equal(null);
  });

  it("drops the actions column from the read-only empty state", async () => {
    // Render the table without badge awards or session-level speakers.
    const element = await mountLitComponent("session-speakers-table", {
      canAwardBadges: false,
      sessions: [],
    });
    const table = element.querySelector('table[aria-label="Session-level speakers"]');

    // Verify the headers and the empty-state colspan without actions.
    expect([...table.querySelectorAll("th")].map((header) => header.textContent.trim())).to.deep.equal([
      "Name",
      "Featured",
      "Sessions",
    ]);
    expect(table.querySelector("tbody td").getAttribute("colspan")).to.equal("3");
  });
});
