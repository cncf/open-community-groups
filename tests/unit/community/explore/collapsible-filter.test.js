import { expect } from "@open-wc/testing";

import "/static/js/community/explore/collapsible-filter.js";
import { mockHtmx } from "/tests/unit/test-utils/globals.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("collapsible-filter", () => {
  useMountedElementsCleanup("collapsible-filter");

  let htmx;

  beforeEach(() => {
    htmx = mockHtmx();
  });

  afterEach(() => {
    htmx.restore();
  });

  it("expands when a hidden option is selected initially", async () => {
    // Render the collapsible-filter fixture.
    const element = await mountLitComponent("collapsible-filter", {
      options: [
        { value: "a", name: "A" },
        { value: "b", name: "B" },
        { value: "c", name: "C" },
      ],
      selected: ["c"],
      maxVisibleItems: 1,
    });

    // Expands when a hidden option is selected initially.
    expect(element.isCollapsed).to.equal(false);
    expect(element.visibleOptions).to.have.length(3);
  });

  it("supports single selection through checkbox changes and clears back to any", async () => {
    // Build the DOM fixture with filters form.
    document.body.innerHTML = '<form id="filters-form"></form>';
    const form = document.getElementById("filters-form");
    const element = document.createElement("collapsible-filter");
    Object.assign(element, {
      options: [
        { value: "a", name: "A" },
        { value: "b", name: "B" },
      ],
      selected: ["a"],
      singleSelection: true,
    });
    form.append(element);
    await element.updateComplete;

    // Select the second option through its checkbox.
    const optionInputs = element.querySelectorAll('input[type="checkbox"]');
    optionInputs[1].dispatchEvent(new Event("change", { bubbles: true }));
    await element.updateComplete;

    // Single selection keeps only the newly chosen option.
    expect(element.selected).to.deep.equal(["b"]);

    // Clear the selected option back to the "any" state.
    element.querySelector("ul button")?.click();
    await element.updateComplete;

    // Clearing selection triggers the form change again.
    expect(element.selected).to.deep.equal([]);
    expect(htmx.triggerCalls).to.deep.equal([
      [form, "change"],
      [form, "change"],
    ]);
  });

  it("resets dependent filters when configured and an option is selected", async () => {
    // Build the DOM fixture with filters form.
    document.body.innerHTML = '<form id="filters-form"></form>';
    const form = document.getElementById("filters-form");
    const dependentCalls = [];
    const otherCollapsible = document.createElement("collapsible-filter");
    otherCollapsible.cleanSelected = () => {
      dependentCalls.push("collapsible");
    };
    const multiSelect = document.createElement("multi-select-filter");
    multiSelect.cleanSelected = () => {
      dependentCalls.push("multi-select");
    };

    // Create the collapsible-filter fixture element.
    const element = document.createElement("collapsible-filter");
    Object.assign(element, {
      options: [{ value: "spain", name: "Spain" }],
      selected: [],
      resetDependentFilters: true,
    });

    // Add the filter beside dependent filters that expose cleanSelected.
    form.append(element, otherCollapsible, multiSelect);
    await element.updateComplete;

    // Selecting the option clears dependent filters.
    element
      .querySelector('input[type="checkbox"]')
      ?.dispatchEvent(new Event("change", { bubbles: true }));
    await element.updateComplete;

    // Dependent filters are reset after the selected option changes.
    expect(element.selected).to.deep.equal(["spain"]);
    expect(dependentCalls).to.deep.equal(["collapsible", "multi-select"]);
  });
});
