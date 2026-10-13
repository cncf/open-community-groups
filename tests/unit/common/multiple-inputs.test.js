import { expect } from "@open-wc/testing";

import "/static/js/common/multiple-inputs.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("multiple-inputs", () => {
  useMountedElementsCleanup("multiple-inputs");

  it("normalizes initial values and renders hidden inputs", async () => {
    // Render the multiple-inputs fixture.
    const element = await mountLitComponent("multiple-inputs", {
      items: ["Ada", "Grace"],
      fieldName: "speakers",
    });

    // Initial values render as submitted hidden inputs.
    expect(element.items.map((item) => item.value)).to.deep.equal(["Ada", "Grace"]);
    expect(
      Array.from(element.querySelectorAll('input[type="hidden"]')).map((input) => input.value),
    ).to.deep.equal(["Ada", "Grace"]);
  });

  it("normalizes values again after reconnects and attribute updates", async () => {
    // Render, disconnect, and reconnect a component with normalized item objects.
    const element = await mountLitComponent("multiple-inputs", {
      fieldName: "speakers",
      items: ["Ada"],
    });
    element.remove();
    document.body.append(element);
    await element.updateComplete;

    // Reconnection preserves string values instead of nesting the normalized objects.
    expect(element.items.map((item) => item.value)).to.deep.equal(["Ada"]);

    // Later attribute updates are normalized before Lit renders the next update.
    element.setAttribute("items", '["Grace"]');
    await element.updateComplete;
    expect(element.items.map((item) => item.value)).to.deep.equal(["Grace"]);
    expect(element.querySelector('input[type="hidden"]').value).to.equal("Grace");
  });

  it("falls back to text inputs and protects the last required row", async () => {
    // Render the multiple-inputs fixture.
    const element = await mountLitComponent("multiple-inputs", {
      inputType: "unsupported",
      required: true,
    });

    // Unsupported input types fall back to text inputs.
    expect(element._getValidInputType()).to.equal("text");

    // Removing the only required row keeps a draft row available.
    const firstItemId = element.items[0].id;
    element._removeItem(firstItemId);

    // The required component still renders one text input row.
    expect(element.items).to.have.length(1);
    expect(element.querySelector('input[type="text"]')).to.not.equal(null);
  });

  it("rejects values that do not match the pattern", async () => {
    // Render the multiple-inputs fixture with a pattern and its message.
    const element = await mountLitComponent("multiple-inputs", {
      items: ["newsletter", "News Letter"],
      pattern: "[a-z]+",
      patternMessage: "Use only lowercase letters.",
    });

    // Only the value breaking the pattern is invalid.
    const inputs = element.querySelectorAll("input[data-item-input]");
    expect(inputs[0].validationMessage).to.equal("");
    expect(inputs[1].validationMessage).to.equal("Use only lowercase letters.");
  });

  it("rejects duplicated and excluded values", async () => {
    // Render the multiple-inputs fixture with unique and excluded values.
    const element = await mountLitComponent("multiple-inputs", {
      items: ["podcast", "podcast", "email"],
      unique: true,
      excludedValues: ["email"],
      excludedMessage: "This medium is already accepted by default.",
    });

    // The repeated and excluded values are invalid.
    const inputs = element.querySelectorAll("input[data-item-input]");
    expect(inputs[0].validationMessage).to.equal("");
    expect(inputs[1].validationMessage).to.equal("This value is already in the list.");
    expect(inputs[2].validationMessage).to.equal("This medium is already accepted by default.");
  });

  it("updates validity as values change and accepts blank values", async () => {
    // Render the multiple-inputs fixture with an invalid value.
    const element = await mountLitComponent("multiple-inputs", {
      items: ["News", "  "],
      pattern: "[a-z]+",
    });
    const input = element.querySelector("input[data-item-input]");
    expect(input.validity.valid).to.equal(false);

    // Fix the value through the input event.
    input.value = "news";
    input.dispatchEvent(new Event("input"));
    await element.updateComplete;

    // The fixed value and the blank row are valid.
    const inputs = element.querySelectorAll("input[data-item-input]");
    expect(inputs[0].validity.valid).to.equal(true);
    expect(inputs[1].validity.valid).to.equal(true);
  });
});
