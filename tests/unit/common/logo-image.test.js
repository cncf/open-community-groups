import { expect } from "@open-wc/testing";

import "/static/js/common/logo-image.js";
import { mountLitComponent } from "/tests/unit/test-utils/lit.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("logo-image", () => {
  afterEach(() => {
    resetDom();
  });

  it("shows the placeholder when there is no image url", async () => {
    // Render the logo-image fixture.
    const element = await mountLitComponent("logo-image", {
      placeholder: "OC",
    });

    // Collect the absolute.inset 0 element.
    const placeholder = element.querySelector(".absolute.inset-0");

    // The rendered text shows the scenario data.
    expect(placeholder?.textContent?.trim()).to.equal("OC");
    expect(placeholder?.className).to.include("flex");
  });

  it("shows the image after a successful load event", async () => {
    // Render the logo-image fixture.
    const element = await mountLitComponent("logo-image", {
      imageUrl: "https://example.com/avatar.png",
      placeholder: "OC",
    });

    // Collect the placeholder and image elements.
    let placeholder = element.querySelector(".absolute.inset-0");
    const image = element.querySelector("img");

    // The placeholder is visible while the image is still loading.
    expect(placeholder?.className).to.include("flex");
    expect(image?.className).to.include("opacity-0");

    // Load the image and verify the fallback state clears.
    image?.dispatchEvent(new Event("load"));
    await element.updateComplete;

    // Collect the absolute.inset 0 element.
    placeholder = element.querySelector(".absolute.inset-0");

    // The loaded image replaces the placeholder.
    expect(placeholder?.className).to.include("hidden");
    expect(image?.className).to.not.include("opacity-0");
  });

  it("hides the component after an image error when hide-on-error is enabled", async () => {
    // Render the logo-image fixture.
    const element = await mountLitComponent("logo-image", {
      imageUrl: "https://example.com/avatar.png",
      hideOnError: true,
    });

    // Collect the image element.
    const image = element.querySelector("img");
    image?.dispatchEvent(new Event("error"));
    await element.updateComplete;

    // The component clears its content after the image error.
    expect(element.children.length).to.equal(0);
  });
});
