import { expect } from "@open-wc/testing";

import "/static/js/common/image-field.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";
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
    fetchMock.setImpl(async () => ({
      status: 201,
      async json() {
        return { url: "https://example.com/image.png" };
      },
    }));

    const element = await mountLitComponent("image-field", {
      label: "Banner",
      name: "banner_image",
    });
    const values = [];

    element.addEventListener("image-change", (event) => {
      values.push(event.detail.value);
    });

    await element._uploadFile(new File(["data"], "banner.png", { type: "image/png" }));
    await element.updateComplete;

    expect(values).to.deep.equal(["https://example.com/image.png"]);
    expect(element.value).to.equal("https://example.com/image.png");
    expect(element.querySelector('input[name="banner_image"]').value).to.equal("https://example.com/image.png");
  });

  it("clears the image value when remove is triggered", async () => {
    const element = await mountLitComponent("image-field", {
      value: "https://example.com/image.png",
    });

    element._handleRemove();
    await element.updateComplete;

    expect(element.value).to.equal("");
  });
});
