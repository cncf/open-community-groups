import { expect } from "@open-wc/testing";

import "/static/js/common/multiple-inputs.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";

describe("multiple-inputs", () => {
  afterEach(() => {
    removeMountedElements("multiple-inputs");
    resetDom();
  });

  it("normalizes initial values and renders hidden inputs", async () => {
    const element = await mountLitComponent("multiple-inputs", {
      items: ["Ada", "Grace"],
      fieldName: "speakers",
    });

    expect(element.items.map((item) => item.value)).to.deep.equal(["Ada", "Grace"]);
    expect(
      Array.from(element.querySelectorAll('input[type="hidden"]')).map((input) => input.value),
    ).to.deep.equal(["Ada", "Grace"]);
  });

  it("falls back to text inputs and protects the last required row", async () => {
    const element = await mountLitComponent("multiple-inputs", {
      inputType: "unsupported",
      required: true,
    });

    expect(element._getValidInputType()).to.equal("text");

    const firstItemId = element.items[0].id;
    element._removeItem(firstItemId);

    expect(element.items).to.have.length(1);
    expect(element.querySelector('input[type="text"]')).to.not.equal(null);
  });
});
