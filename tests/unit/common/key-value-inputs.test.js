import { expect } from "@open-wc/testing";

import "/static/js/common/key-value-inputs.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("key-value-inputs", () => {
  useMountedElementsCleanup("key-value-inputs");

  it("normalizes object values and renders hidden inputs for filled rows", async () => {
    // Render the key-value-inputs fixture.
    const element = await mountLitComponent("key-value-inputs", {
      items: {
        Website: "https://example.com",
      },
      fieldName: "links",
    });

    // Object values render one filled row and matching hidden input.
    expect(element._itemsArray).to.deep.equal([
      { key: "Website", value: "https://example.com" },
    ]);
    expect(element.querySelector('input[type="hidden"]').name).to.equal(
      "links[Website]",
    );
    expect(element.querySelector('input[type="hidden"]').value).to.equal(
      "https://example.com",
    );
  });

  it("adds and removes rows while keeping at least one empty row", async () => {
    // Render the key-value-inputs fixture.
    const element = await mountLitComponent("key-value-inputs", {
      maxItems: 2,
    });

    // Adding a row reaches the max and disables the add button.
    element._addItem();
    await element.updateComplete;
    expect(element._itemsArray).to.have.length(2);
    expect(element._isAddButtonDisabled()).to.equal(true);

    // Removing rows keeps one empty draft row.
    element._removeItem(0);
    element._removeItem(0);
    await element.updateComplete;

    // Empty draft rows are excluded from the submitted object value.
    expect(element._itemsArray).to.deep.equal([{ key: "", value: "" }]);
    expect(element.items).to.deep.equal({});
  });
});
