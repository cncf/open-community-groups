import { expect } from "@open-wc/testing";

import "/static/js/community/explore/collapsible-filter.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx } from "/tests/unit/test-utils/globals.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";

describe("collapsible-filter", () => {
  let htmx;

  beforeEach(() => {
    htmx = mockHtmx();
  });

  afterEach(() => {
    htmx.restore();
    removeMountedElements("collapsible-filter");
    resetDom();
  });

  it("expands when a hidden option is selected initially", async () => {
    const element = await mountLitComponent("collapsible-filter", {
      options: [
        { value: "a", name: "A" },
        { value: "b", name: "B" },
        { value: "c", name: "C" },
      ],
      selected: ["c"],
      maxVisibleItems: 1,
    });

    expect(element.isCollapsed).to.equal(false);
    expect(element.visibleOptions).to.have.length(3);
  });

  it("supports single selection through checkbox changes and clears back to any", async () => {
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

    const optionInputs = element.querySelectorAll('input[type="checkbox"]');
    optionInputs[1].dispatchEvent(new Event("change", { bubbles: true }));
    await element.updateComplete;

    expect(element.selected).to.deep.equal(["b"]);

    element.querySelector("ul button")?.click();
    await element.updateComplete;

    expect(element.selected).to.deep.equal([]);
    expect(htmx.triggerCalls).to.deep.equal([
      [form, "change"],
      [form, "change"],
    ]);
  });

  it("resets dependent filters when configured and an option is selected", async () => {
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

    const element = document.createElement("collapsible-filter");
    Object.assign(element, {
      options: [{ value: "spain", name: "Spain" }],
      selected: [],
      resetDependentFilters: true,
    });

    form.append(element, otherCollapsible, multiSelect);
    await element.updateComplete;

    element.querySelector('input[type="checkbox"]')?.dispatchEvent(new Event("change", { bubbles: true }));
    await element.updateComplete;

    expect(element.selected).to.deep.equal(["spain"]);
    expect(dependentCalls).to.deep.equal(["collapsible", "multi-select"]);
  });
});
