import { expect } from "@open-wc/testing";

import "/static/js/common/speakers-selector.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";

describe("speakers-selector", () => {
  afterEach(() => {
    removeMountedElements("speakers-selector");
    resetDom();
  });

  it("opens the speaker modal with existing speaker ids disabled", async () => {
    const element = await mountLitComponent("speakers-selector", {
      selectedSpeakers: [{ user_id: "12", username: "ada", featured: false }],
      showAddButton: true,
    });
    const modal = element.querySelector("session-speaker-modal");
    let openCalls = 0;
    modal.open = () => {
      openCalls += 1;
    };

    element._openSpeakerModal();

    expect(openCalls).to.equal(1);
    expect(modal.disabledUserIds).to.deep.equal(["12"]);
  });

  it("adds speakers, emits changes, and ignores duplicates", async () => {
    const element = await mountLitComponent("speakers-selector");
    const received = [];

    element.addEventListener("speakers-changed", (event) => {
      received.push(event.detail.speakers);
    });

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

    expect(element.selectedSpeakers).to.deep.equal([
      { user_id: "21", username: "grace", name: "Grace Hopper", featured: true },
    ]);
    expect(received).to.have.length(1);
    expect(element.querySelector('input[name="speakers[0][user_id]"]').value).to.equal("21");
    expect(element.querySelector('input[name="speakers[0][featured]"]').value).to.equal("true");
  });
});
