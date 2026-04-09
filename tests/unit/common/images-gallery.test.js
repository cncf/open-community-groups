import { expect } from "@open-wc/testing";

import "/static/js/common/images-gallery.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";

describe("images-gallery", () => {
  afterEach(() => {
    removeMountedElements("images-gallery");
    resetDom();
  });

  it("opens the modal and navigates through the image carousel", async () => {
    const element = await mountLitComponent("images-gallery", {
      images: ["https://example.com/1.png", "https://example.com/2.png"],
      title: "Gallery",
    });

    element._openModal(0);
    await element.updateComplete;

    expect(element._isModalOpen).to.equal(true);
    expect(element._currentIndex).to.equal(0);
    expect(document.body.style.overflow).to.equal("hidden");

    element._handleKeydown({ key: "ArrowRight" });
    expect(element._currentIndex).to.equal(1);

    element._handleKeydown({ key: "ArrowLeft" });
    expect(element._currentIndex).to.equal(0);
  });

  it("closes the modal from escape and background clicks", async () => {
    const element = await mountLitComponent("images-gallery", {
      images: ["https://example.com/1.png"],
    });

    element._openModal(0);
    await element.updateComplete;

    element._handleKeydown({ key: "Escape" });
    expect(element._isModalOpen).to.equal(false);
    expect(document.body.style.overflow).to.equal("");

    element._openModal(0);
    element._handleModalBackgroundClick({
      target: {
        tagName: "DIV",
        parentElement: null,
      },
    });

    expect(element._isModalOpen).to.equal(false);
  });
});
