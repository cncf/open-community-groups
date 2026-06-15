import { expect } from "@open-wc/testing";

import "/static/js/community/explore/multi-select-filter.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("multi-select-filter", () => {
  useMountedElementsCleanup("multi-select-filter");

  it("filters typed options and renders hidden inputs for selected values", async () => {
    // Render the DOM fixture for filtering typed options and renders hidden inputs.
    document.body.innerHTML = '<form id="filters-form"></form>';
    const form = document.getElementById("filters-form");
    const filterChangeEvents = [];
    form.addEventListener("filter-change", (event) => filterChangeEvents.push(event));
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

    // Read the rendered DOM state for filtering typed options and renders hidden inputs.
    const input = element.querySelector('input[type="text"]');
    input.dispatchEvent(new FocusEvent("focus"));
    input.value = "sec";
    input.dispatchEvent(new Event("input", { bubbles: true }));
    await element.updateComplete;

    // Verify filters typed options and renders hidden inputs for selected values.
    expect(element._filteredOptions).to.deep.equal([{ value: "security", name: "Security" }]);

    // Verify filters typed options and renders hidden inputs.
    element.querySelector('[role="option"]')?.click();
    await element.updateComplete;

    // Verify filters typed options and renders hidden inputs for selected values.
    expect(element.selected).to.deep.equal(["security"]);
    expect(element.querySelector('input[type="hidden"][value="security"]')).to.not.equal(null);
    expect(element.textContent).to.include("Security");

    // Verify selected options stay mirrored in hidden inputs.
    element.querySelectorAll(".icon-close")[1]?.closest("button")?.click();
    await element.updateComplete;

    // Verify filters typed options and renders hidden inputs for selected values.
    expect(element.selected).to.deep.equal([]);
    expect(filterChangeEvents).to.have.length(2);
    expect(filterChangeEvents[0].target).to.equal(element);
    expect(filterChangeEvents[1].target).to.equal(element);
  });

  it("supports keyboard navigation and closes on outside clicks", async () => {
    // Call mount lit component.
    const element = await mountLitComponent("multi-select-filter", {
      options: [
        { value: "cloud", name: "Cloud" },
        { value: "security", name: "Security" },
      ],
    });

    // Read the listbox and options used by keyboard navigation.
    const input = element.querySelector('input[type="text"]');
    input.dispatchEvent(new FocusEvent("focus"));
    await element.updateComplete;

    // Dispatch the keydown event.
    element.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }));
    element.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
    await element.updateComplete;

    // Verify supports keyboard navigation and closes on outside clicks.
    expect(element.selected).to.deep.equal(["cloud"]);
    expect(element._combobox.isOpen).to.equal(true);

    // Click outside the filter to close the options.
    document.dispatchEvent(new MouseEvent("click", { bubbles: true, composed: true }));
    await waitForMicrotask();

    // Verify supports keyboard navigation and closes on outside clicks.
    expect(element._combobox.isOpen).to.equal(false);
  });
});
