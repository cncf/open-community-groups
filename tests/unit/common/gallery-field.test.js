import { expect } from "@open-wc/testing";

import "/static/js/common/gallery-field.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";

describe("gallery-field", () => {
  afterEach(() => {
    removeMountedElements("gallery-field");
    resetDom();
  });

  it("reorders and removes gallery images while emitting updates", async () => {
    const element = await mountLitComponent("gallery-field", {
      images: ["https://example.com/1.png", "https://example.com/2.png"],
      fieldName: "gallery",
    });
    const received = [];

    element.addEventListener("images-change", (event) => {
      received.push(event.detail.images);
    });

    element._reorderImages(0, 1);
    element._handleRemoveImage(0);
    await element.updateComplete;

    expect(element.images).to.deep.equal(["https://example.com/1.png"]);
    expect(received[0]).to.deep.equal(["https://example.com/2.png", "https://example.com/1.png"]);
    expect(received[1]).to.deep.equal(["https://example.com/1.png"]);
  });

  it("hides the add tile when the gallery reaches its limit", async () => {
    const element = await mountLitComponent("gallery-field", {
      images: ["1", "2"],
      maxImages: 2,
    });

    expect(element._showAddTile).to.equal(false);
    expect(element._remainingSlots).to.equal(0);
  });
});
