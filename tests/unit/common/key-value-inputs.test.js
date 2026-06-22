import { expect } from "@open-wc/testing";

import "/static/js/common/key-value-inputs.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

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
    expect(element._itemsArray).to.deep.equal([{ id: 0, key: "Website", value: "https://example.com" }]);
    expect(element.querySelector('input[type="hidden"]').name).to.equal("links[Website]");
    expect(element.querySelector('input[type="hidden"]').value).to.equal("https://example.com");
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
    expect(element._itemsArray).to.deep.equal([{ id: 2, key: "", value: "" }]);
    expect(element.items).to.deep.equal({});
  });

  it("keeps row identity stable when rows are removed", async () => {
    // Render the key-value-inputs fixture.
    const element = await mountLitComponent("key-value-inputs", {
      items: {
        Website: "https://example.com",
        Docs: "https://example.com/docs",
      },
    });

    // Remove the first row, then update the remaining row by its stable ID.
    const remainingId = element._itemsArray[1].id;
    element._removeItem(element._itemsArray[0].id);
    element._updateItem(remainingId, "value", "https://example.com/help");
    await element.updateComplete;

    // The surviving row keeps its identity and receives the update.
    expect(element._itemsArray).to.deep.equal([
      { id: remainingId, key: "Docs", value: "https://example.com/help" },
    ]);
    expect(element.items).to.deep.equal({
      Docs: "https://example.com/help",
    });
  });

  it("marks duplicate keys invalid", async () => {
    // Render the key-value-inputs fixture.
    const element = await mountLitComponent("key-value-inputs", {
      fieldName: "links",
    });

    // Fill two rows with the same non-empty key.
    element._addItem();
    element._updateItem(0, "key", "Website");
    element._updateItem(0, "value", "https://example.com");
    element._updateItem(1, "key", "Website");
    element._updateItem(1, "value", "https://example.com/docs");
    await element.updateComplete;

    // Duplicate keys receive native validation feedback.
    const keyInputs = element.querySelectorAll("[data-key-input-id]");
    expect(keyInputs[0].validationMessage).to.equal("Each key must be unique.");
    expect(keyInputs[1].validationMessage).to.equal("Each key must be unique.");
    expect(keyInputs[0].getAttribute("aria-invalid")).to.equal("true");
  });
});
