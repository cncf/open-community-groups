import { expect } from "@open-wc/testing";

import "/static/js/common/logo-image.js";

describe("logo-image", () => {
  afterEach(() => {
    document.body.innerHTML = "";
  });

  it("shows the placeholder when there is no image url", async () => {
    const element = document.createElement("logo-image");
    element.placeholder = "OC";
    document.body.append(element);

    await element.updateComplete;

    const placeholder = element.querySelector(".absolute.inset-0");

    expect(placeholder?.textContent?.trim()).to.equal("OC");
    expect(placeholder?.className).to.include("flex");
  });

  it("shows the image after a successful load event", async () => {
    const element = document.createElement("logo-image");
    element.imageUrl = "https://example.com/avatar.png";
    element.placeholder = "OC";
    document.body.append(element);

    await element.updateComplete;

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
    const element = document.createElement("logo-image");
    element.imageUrl = "https://example.com/avatar.png";
    element.hideOnError = true;
    document.body.append(element);

    await element.updateComplete;

    const image = element.querySelector("img");
    image?.dispatchEvent(new Event("error"));
    await element.updateComplete;

    expect(element.children.length).to.equal(0);
  });
});
