import { expect } from "@open-wc/testing";

import "/static/js/common/modals/images-gallery.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("images-gallery", () => {
  useMountedElementsCleanup("images-gallery");

  it("opens the modal and navigates through the image carousel", async () => {
    // Render the images-gallery fixture.
    const element = await mountLitComponent("images-gallery", {
      images: ["https://example.com/1.png", "https://example.com/2.png"],
      title: "Gallery",
    });

    // Open the modal at the first image and lock body scrolling.
    element._openModal(0);
    await element.updateComplete;

    // The modal opens on the first image and disables body scroll.
    expect(element._isModalOpen).to.equal(true);
    expect(element._currentIndex).to.equal(0);
    expect(document.body.style.overflow).to.equal("hidden");

    // ArrowRight advances to the next gallery image.
    element._handleKeydown({ key: "ArrowRight" });
    expect(element._currentIndex).to.equal(1);

    // ArrowLeft returns to the previous gallery image.
    element._handleKeydown({ key: "ArrowLeft" });
    expect(element._currentIndex).to.equal(0);
  });

  it("renders gallery images inside stable positioned containers", async () => {
    // Render the images-gallery fixture.
    const element = await mountLitComponent("images-gallery", {
      images: ["https://example.com/1.png"],
      title: "Gallery",
    });

    // Read the inline images that should keep relative positioning.
    const thumbnailButton = [...element.querySelectorAll("button")].find(
      (button) => button.querySelector('img[alt="Gallery image 1"]'),
    );
    const mobileImage = [
      ...element.querySelectorAll('img[alt="Gallery image 1"]'),
    ].find((image) => image.parentElement?.classList.contains("md:hidden"));

    // Inline gallery image containers keep relative positioning.
    expect(thumbnailButton?.classList.contains("relative")).to.equal(true);
    expect(mobileImage?.parentElement?.classList.contains("relative")).to.equal(
      true,
    );

    // Open the modal to inspect the fixed-position carousel image.
    element._openModal(0);
    await element.updateComplete;

    // Modal carousel images use absolute positioning instead.
    const modalImage = [
      ...element.querySelectorAll('img[alt="Gallery image 1"]'),
    ].find((image) => image.classList.contains("top-1/2"));
    expect(modalImage?.parentElement?.classList.contains("absolute")).to.equal(
      true,
    );
    expect(modalImage?.parentElement?.classList.contains("relative")).to.equal(
      false,
    );
  });

  it("closes the modal from escape and background clicks", async () => {
    // Render the images-gallery fixture.
    const element = await mountLitComponent("images-gallery", {
      images: ["https://example.com/1.png"],
    });

    // Open the modal.
    element._openModal(0);
    await element.updateComplete;

    // Escape closes the modal and restores body scrolling.
    element._handleKeydown({ key: "Escape" });
    expect(element._isModalOpen).to.equal(false);
    expect(document.body.style.overflow).to.equal("");

    // Reopen the modal and close it from a background click.
    element._openModal(0);
    element._handleModalBackgroundClick({
      target: {
        tagName: "DIV",
        parentElement: null,
      },
    });

    // Background clicks close the reopened modal.
    expect(element._isModalOpen).to.equal(false);
  });
});
