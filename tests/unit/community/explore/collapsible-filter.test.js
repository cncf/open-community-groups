import { expect } from "@open-wc/testing";

import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import "/static/js/community/explore/collapsible-filter.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("collapsible-filter", () => {
  useMountedElementsCleanup("collapsible-filter");

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

  it("rings an option label on phones while its hidden checkbox has focus", async () => {
    // Render one selected and one unselected option.
    const element = await mountLitComponent("collapsible-filter", {
      title: "Region",
      name: "region",
      options: [
        { value: "emea", name: "EMEA" },
        { value: "latam", name: "LATAM" },
      ],
      selected: ["emea"],
    });

    // The checkbox is sr-only, so the label shows focus in both states.
    const labels = [...element.querySelectorAll("label")];
    expect(labels).to.have.length(2);
    labels.forEach((label) => {
      expect(label.classList.contains("phone:has-[:focus-visible]:ring-2")).to.equal(true);
      expect(label.classList.contains("phone:has-[:focus-visible]:ring-primary-300")).to.equal(true);
    });
  });

  it("exposes collapsed state and context to assistive technologies", async () => {
    // Render the collapsible-filter fixture.
    const element = await mountLitComponent("collapsible-filter", {
      title: "Region",
      name: "region",
      options: [
        { value: "emea", name: "EMEA" },
        { value: "latam", name: "LATAM" },
        { value: "apac", name: "APAC" },
      ],
      maxVisibleItems: 1,
    });

    // The collapse controls announce their current state and controlled list.
    const optionList = element.querySelector("#region-filter-options");
    const collapseButton = element.querySelector(".collapse-btn");
    const showMoreButton = element.querySelector(".mt-4 button");
    const anyButton = element.querySelector("ul button");

    expect(optionList).to.not.equal(null);
    expect(collapseButton?.getAttribute("aria-expanded")).to.equal("false");
    expect(collapseButton?.getAttribute("aria-controls")).to.equal("region-filter-options");
    expect(showMoreButton?.getAttribute("aria-expanded")).to.equal("false");
    expect(showMoreButton?.getAttribute("aria-controls")).to.equal("region-filter-options");
    expect(anyButton?.getAttribute("aria-label")).to.equal("Any Region");

    // Expanding updates the ARIA state alongside the visible state.
    showMoreButton?.click();
    await element.updateComplete;

    expect(collapseButton?.getAttribute("aria-expanded")).to.equal("true");
    expect(showMoreButton?.getAttribute("aria-expanded")).to.equal("true");
  });

  it("supports single selection through checkbox changes and clears back to any", async () => {
    // Build the DOM fixture with filters form.
    document.body.innerHTML = '<form id="filters-form"></form>';
    const form = document.getElementById("filters-form");
    const filterChangeEvents = [];
    form.addEventListener("filter-change", (event) => filterChangeEvents.push(event));
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

    // Assert the element state.
    expect(element.selected).to.deep.equal([]);
    expect(filterChangeEvents).to.have.length(2);
    expect(filterChangeEvents[0].target).to.equal(element);
    expect(filterChangeEvents[1].target).to.equal(element);
  });

  it("clears a single selection tapped again on phones, where the form applies later", async () => {
    // Render a selected single selection filter on a phone.
    const originalMatchMedia = window.matchMedia;
    window.matchMedia = (query) => ({ matches: query === PHONE_MEDIA_QUERY });
    const element = await mountLitComponent("collapsible-filter", {
      name: "community",
      options: [
        { value: "one", name: "One" },
        { value: "two", name: "Two" },
      ],
      selected: ["one"],
      singleSelection: true,
    });

    try {
      // Tap the selected option, which unchecks its checkbox.
      element.querySelector('input[value="one"]').click();
      await element.updateComplete;

      // Verify the selection follows the checkbox, so the highlight never outlives the value.
      expect(element.selected).to.deep.equal([]);
      expect(element.querySelector("input:checked")).to.equal(null);
    } finally {
      window.matchMedia = originalMatchMedia;
    }
  });

  it("keeps a single selection tapped again off phones", async () => {
    // Render a selected single selection filter.
    const element = await mountLitComponent("collapsible-filter", {
      name: "community",
      options: [{ value: "one", name: "One" }],
      selected: ["one"],
      singleSelection: true,
    });

    // Tap the selected option.
    element.querySelector('input[value="one"]').click();
    await element.updateComplete;

    // Verify the selection stays for the live request to resolve.
    expect(element.selected).to.deep.equal(["one"]);
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
    element.querySelector('input[type="checkbox"]')?.dispatchEvent(new Event("change", { bubbles: true }));
    await element.updateComplete;

    // Dependent filters are reset after the selected option changes.
    expect(element.selected).to.deep.equal(["spain"]);
    expect(dependentCalls).to.deep.equal(["collapsible", "multi-select"]);
  });
});
