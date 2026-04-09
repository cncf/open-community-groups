import { expect } from "@open-wc/testing";

import "/static/js/community/explore/multi-select-filter.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx } from "/tests/unit/test-utils/globals.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";

describe("multi-select-filter", () => {
  let htmx;

  beforeEach(() => {
    htmx = mockHtmx();
  });

  afterEach(() => {
    htmx.restore();
    removeMountedElements("multi-select-filter");
    resetDom();
  });

  it("filters typed options and renders hidden inputs for selected values", async () => {
    document.body.innerHTML = '<form id="filters-form"></form>';
    const form = document.getElementById("filters-form");
    const element = document.createElement("multi-select-filter");
    Object.assign(element, {
      options: [
        { value: "cloud", name: "Cloud" },
        { value: "security", name: "Security" },
      ],
      selected: [],
    });
    form.append(element);
    await element.updateComplete;

    const input = element.querySelector('input[type="text"]');
    input.dispatchEvent(new FocusEvent("focus"));
    input.value = "sec";
    input.dispatchEvent(new Event("input", { bubbles: true }));
    await element.updateComplete;

    expect(element._filteredOptions).to.deep.equal([{ value: "security", name: "Security" }]);

    element.querySelector('[role="option"]')?.click();
    await element.updateComplete;

    expect(element.selected).to.deep.equal(["security"]);
    expect(element.querySelector('input[type="hidden"][value="security"]')).to.not.equal(null);
    expect(element.textContent).to.include("Security");

    element.querySelectorAll(".icon-close")[1]?.closest("button")?.click();
    await element.updateComplete;

    expect(element.selected).to.deep.equal([]);
    expect(htmx.triggerCalls).to.deep.equal([[form, "change"], [form, "change"]]);
  });

  it("supports keyboard navigation and closes on outside clicks", async () => {
    const element = await mountLitComponent("multi-select-filter", {
      options: [
        { value: "cloud", name: "Cloud" },
        { value: "security", name: "Security" },
      ],
    });

    const input = element.querySelector('input[type="text"]');
    input.dispatchEvent(new FocusEvent("focus"));
    await element.updateComplete;

    element.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }));
    element.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
    await element.updateComplete;

    expect(element.selected).to.deep.equal(["cloud"]);
    expect(element._isOpen).to.equal(true);

    document.dispatchEvent(new MouseEvent("click", { bubbles: true, composed: true }));
    await waitForMicrotask();

    expect(element._isOpen).to.equal(false);
  });
});
