import { expect } from "@open-wc/testing";

import "/static/js/common/key-value-inputs.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";

describe("key-value-inputs", () => {
  afterEach(() => {
    removeMountedElements("key-value-inputs");
    resetDom();
  });

  it("normalizes object values and renders hidden inputs for filled rows", async () => {
    const element = await mountLitComponent("key-value-inputs", {
      items: {
        Website: "https://example.com",
      },
      fieldName: "links",
    });

    expect(element._itemsArray).to.deep.equal([{ key: "Website", value: "https://example.com" }]);
    expect(element.querySelector('input[type="hidden"]').name).to.equal("links[Website]");
    expect(element.querySelector('input[type="hidden"]').value).to.equal("https://example.com");
  });

  it("adds and removes rows while keeping at least one empty row", async () => {
    const element = await mountLitComponent("key-value-inputs", {
      maxItems: 2,
    });

    element._addItem();
    await element.updateComplete;
    expect(element._itemsArray).to.have.length(2);
    expect(element._isAddButtonDisabled()).to.equal(true);

    element._removeItem(0);
    element._removeItem(0);
    await element.updateComplete;

    expect(element._itemsArray).to.deep.equal([{ key: "", value: "" }]);
    expect(element.items).to.deep.equal({});
  });
});
