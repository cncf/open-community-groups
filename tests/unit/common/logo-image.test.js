import { expect } from "@open-wc/testing";

import "/static/js/common/logo-image.js";
import { mountLitComponent } from "/tests/unit/test-utils/lit.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("logo-image", () => {
  afterEach(() => {
    resetDom();
  });

  it("shows the placeholder when there is no image url", async () => {
    const element = await mountLitComponent("logo-image", { placeholder: "OC" });

    const placeholder = element.querySelector(".absolute.inset-0");

    expect(placeholder?.textContent?.trim()).to.equal("OC");
    expect(placeholder?.className).to.include("flex");
  });

  it("shows the image after a successful load event", async () => {
    const element = await mountLitComponent("logo-image", {
      imageUrl: "https://example.com/avatar.png",
      placeholder: "OC",
    });

    let placeholder = element.querySelector(".absolute.inset-0");
    const image = element.querySelector("img");

    expect(placeholder?.className).to.include("flex");
    expect(image?.className).to.include("opacity-0");

    image?.dispatchEvent(new Event("load"));
    await element.updateComplete;

    placeholder = element.querySelector(".absolute.inset-0");

    expect(placeholder?.className).to.include("hidden");
    expect(image?.className).to.not.include("opacity-0");
  });

  it("hides the component after an image error when hide-on-error is enabled", async () => {
    const element = await mountLitComponent("logo-image", {
      imageUrl: "https://example.com/avatar.png",
      hideOnError: true,
    });

    const image = element.querySelector("img");
    image?.dispatchEvent(new Event("error"));
    await element.updateComplete;

    expect(element.children.length).to.equal(0);
  });
});
