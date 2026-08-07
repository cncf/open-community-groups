import { expect } from "@open-wc/testing";

import "/static/js/common/users/speakers-selector.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("speakers-selector", () => {
  useMountedElementsCleanup("speakers-selector");

  it("opens the speaker modal with existing speaker ids disabled", async () => {
    // Render the speakers-selector fixture.
    const element = await mountLitComponent("speakers-selector", {
      selectedSpeakers: [{ user_id: "12", username: "ada", featured: false }],
      showAddButton: true,
    });
    const modal = element.querySelector("session-speaker-modal");
    let openCalls = 0;
    modal.open = () => {
      openCalls += 1;
    };

    // Open the speaker modal and keep body scrolling locked.
    element._openSpeakerModal();

    // The modal opens with the existing speaker disabled.
    expect(openCalls).to.equal(1);
    expect(modal.disabledUserIds).to.deep.equal(["12"]);
  });

  it("adds speakers, emits changes, and ignores duplicates", async () => {
    // Render the speakers-selector fixture.
    const element = await mountLitComponent("speakers-selector");
    const received = [];

    // Listen for the emitted event.
    element.addEventListener("speakers-changed", (event) => {
      received.push(event.detail.speakers);
    });

    // Let the component finish rendering.
    element._handleSpeakerSelected({
      detail: {
        user: { user_id: "21", username: "grace", name: "Grace Hopper" },
        featured: true,
      },
    });
    element._handleSpeakerSelected({
      detail: {
        user: { user_id: "21", username: "grace", name: "Grace Hopper" },
        featured: false,
      },
    });
    await element.updateComplete;

    // Added speakers, emits changes, and ignores duplicates.
    expect(element.selectedSpeakers).to.deep.equal([
      {
        user_id: "21",
        username: "grace",
        name: "Grace Hopper",
        featured: true,
      },
    ]);
    expect(received).to.have.length(1);
    expect(element.querySelector("selected-user-pill")?.featured).to.equal(true);
    expect(element.querySelector('input[name="speakers[0][user_id]"]').value).to.equal("21");
    expect(element.querySelector('input[name="speakers[0][featured]"]').value).to.equal("true");
  });

  it("keeps the event speakers table visible with an empty-state row", async () => {
    // Render the event-level table display.
    const element = await mountLitComponent("speakers-selector", {
      displayMode: "table",
    });
    const title = [...element.querySelectorAll("div")].find(
      (candidate) => candidate.children.length === 0 && candidate.textContent.trim() === "Speakers",
    );
    const table = element.querySelector('table[aria-label="Event speakers"]');
    const emptyState = table.querySelector("tbody td");

    // Verify the title matches other event contributor sections.
    expect(title.tagName).to.equal("DIV");
    expect([...title.classList]).to.include.members([
      "text-xl",
      "lg:text-2xl",
      "font-medium",
      "text-stone-900",
    ]);

    // Verify the empty event speakers table remains visible.
    expect([...table.querySelectorAll("th")].map((header) => header.textContent.trim())).to.deep.equal([
      "Name",
      "Featured",
      "Actions",
    ]);
    expect(emptyState.textContent.trim()).to.equal("No event speakers added yet.");
    expect(emptyState.getAttribute("colspan")).to.equal("3");
    expect(emptyState.classList.contains("text-center")).to.equal(true);
  });

  it("renders event speakers as a table and deduplicates bulk award recipients", async () => {
    // Render the event speakers table with its header actions.
    const element = await mountLitComponent("speakers-selector", {
      additionalAwardUserIds: ["21", "22"],
      canAwardBadges: true,
      displayMode: "table",
      eventId: "event-1",
      selectedSpeakers: [{ user_id: "21", username: "grace", featured: true }],
      showAddButton: true,
      showAwardAll: true,
    });

    // Verify the featured column and right-aligned action order.
    const table = element.querySelector('table[aria-label="Event speakers"]');
    const tableHeaders = [...table.querySelectorAll("th")].map((header) => header.textContent.trim());
    const speakerRow = table.querySelector("tbody tr");
    const bulkAwardButton = element.querySelector("[data-badge-award-open]");
    const addSpeakerButton = [...element.querySelectorAll("button")].find(
      (button) => button.textContent.trim() === "Add speaker",
    );

    expect(tableHeaders).to.deep.equal(["Name", "Featured", "Actions"]);
    expect(speakerRow.children[0].querySelector(".icon-star")).to.equal(null);
    expect(speakerRow.children[1].querySelector(".icon-star").classList.contains("size-4")).to.equal(true);
    expect(bulkAwardButton.dataset.userIds).to.equal("21,22");
    expect(bulkAwardButton.hasAttribute("data-badge-award-all-speakers")).to.equal(true);
    expect(bulkAwardButton.textContent.trim()).to.equal("Award badge");
    expect(bulkAwardButton.classList.contains("btn-mini")).to.equal(false);
    expect(bulkAwardButton.nextElementSibling).to.equal(addSpeakerButton);
    expect(element.querySelectorAll("[data-badge-award-open]")).to.have.length(2);
    expect(
      speakerRow.querySelector("[data-badge-award-open]").hasAttribute("data-badge-award-all-speakers"),
    ).to.equal(false);

    // Remove the speaker through the existing row action.
    element.querySelector(".icon-trash")?.closest("button")?.click();
    await element.updateComplete;
    expect(element.selectedSpeakers).to.deep.equal([]);
  });

  it("keeps non-featured speaker cells visually empty", async () => {
    const element = await mountLitComponent("speakers-selector", {
      displayMode: "table",
      selectedSpeakers: [{ user_id: "21", username: "grace", featured: false }],
    });
    const featuredCell = element.querySelector("tbody tr").children[1];

    expect(featuredCell.textContent.trim()).to.equal("No");
    expect(featuredCell.querySelector(".sr-only")).to.not.equal(null);
    expect(featuredCell.textContent).to.not.include("—");
  });
});
