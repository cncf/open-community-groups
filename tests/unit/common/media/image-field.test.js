import { expect } from "@open-wc/testing";

import "/static/js/common/media/image-field.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("image-field", () => {
  useDashboardTestEnv({ withSwal: true, withScroll: true });
  useMountedElementsCleanup("image-field");

  let fetchMock;

  beforeEach(() => {
    fetchMock = mockFetch();
  });

  afterEach(() => {
    fetchMock.restore();
  });

  it("uploads an image and emits the new value", async () => {
    // Mock the fetch response.
    fetchMock.setImpl(async () => ({
      status: 201,
      async json() {
        return { url: "https://example.com/image.png" };
      },
    }));

    // Render the image-field fixture.
    const element = await mountLitComponent("image-field", {
      label: "Banner",
      name: "banner_image",
    });
    const values = [];

    // Listen for the emitted event.
    element.addEventListener("image-change", (event) => {
      values.push(event.detail.value);
    });

    // Upload the selected file and wait for the hidden input to update.
    await element._uploadFile(
      new File(["data"], "banner.png", { type: "image/png" }),
    );
    await element.updateComplete;

    // Uploads an image and emits the new value.
    expect(values).to.deep.equal(["https://example.com/image.png"]);
    expect(element.value).to.equal("https://example.com/image.png");
    expect(element.querySelector('input[name="banner_image"]').value).to.equal(
      "https://example.com/image.png",
    );
  });

  it("clears the image value when remove is triggered", async () => {
    // Render the image-field fixture.
    const element = await mountLitComponent("image-field", {
      value: "https://example.com/image.png",
    });

    // Remove the current image and wait for the hidden input to update.
    element._handleRemove();
    await element.updateComplete;

    // The image value is cleared after removal.
    expect(element.value).to.equal("");
  });

  it("does not show the generic supported formats text for Open Graph images", async () => {
    // Mount an Open Graph image field with explicit format guidance.
    const element = await mountLitComponent("image-field", {
      helpPrefixText: "Size required 1200 x 630 px. Format must be PNG, JPEG, or WebP.",
      imageKind: "banner",
      target: "open_graph",
    });

    // Set up help text.
    const helpText = element.querySelector(".form-legend").textContent.trim();
    const fileInput = element.querySelector('input[type="file"]');

    // Verify does not show the generic supported formats text for Open Graph images.
    expect(helpText).to.equal(
      "Size required 1200 x 630 px. Format must be PNG, JPEG, or WebP. Maximum size: 1MB.",
    );
    expect(helpText).not.to.include("Supported formats");
    expect(fileInput.accept).to.equal(".png,.jpg,.jpeg,.webp");
  });

  it("shows the generic supported formats text for banner images", async () => {
    // Mount a standard banner image field with generic guidance.
    const element = await mountLitComponent("image-field", {
      helpPrefixText: "Size required 2428 x 192 px.",
      imageKind: "banner",
      target: "banner",
    });

    // Set up help text.
    const helpText = element.querySelector(".form-legend").textContent.trim();
    const fileInput = element.querySelector('input[type="file"]');

    // Assert the accepted image formats copy.
    expect(helpText).to.include("Supported formats: SVG, PNG, JPEG, GIF, WEBP and TIFF.");
    expect(fileInput.accept).to.equal(".svg,.png,.jpg,.jpeg,.gif,.webp,.tif,.tiff");
  });
});
