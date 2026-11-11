import { expect } from "@open-wc/testing";

import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import "/static/js/community/explore/collapsible-filter.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";
import { stubMatchMedia } from "/tests/unit/test-utils/media.js";

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

  it("outlines an option label while its hidden checkbox has focus", async () => {
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
      expect(label.classList.contains("has-[:focus-visible]:outline-2")).to.equal(true);
      expect(label.classList.contains("has-[:focus-visible]:outline-offset-2")).to.equal(true);
      expect(label.classList.contains("has-[:focus-visible]:outline-focus")).to.equal(true);
    });
  });

  it("exposes collapsed state and context to assistive technologies", async () => {
    // Render the collapsible-filter fixture inside a form.
    const element = await mountInForm("f", {
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
    const optionList = element.querySelector("#f-region-filter-options");
    const collapseButton = element.querySelector(".collapse-btn");
    const showMoreButton = element.querySelector(".mt-4 button");
    const anyButton = element.querySelector("ul button");

    expect(optionList).to.not.equal(null);
    expect(collapseButton?.getAttribute("aria-expanded")).to.equal("false");
    expect(collapseButton?.getAttribute("aria-controls")).to.equal("f-region-filter-options");
    expect(showMoreButton?.getAttribute("aria-expanded")).to.equal("false");
    expect(showMoreButton?.getAttribute("aria-controls")).to.equal("f-region-filter-options");
    expect(anyButton?.getAttribute("aria-label")).to.equal("Any Region");

    // Expanding updates the ARIA state alongside the visible state.
    showMoreButton?.click();
    await element.updateComplete;

    expect(collapseButton?.getAttribute("aria-expanded")).to.equal("true");
    expect(showMoreButton?.getAttribute("aria-expanded")).to.equal("true");
  });

  it("scopes the option list id to its form", async () => {
    // Render the same filter in two forms, as the sidebar and the phone sheet do.
    const properties = {
      title: "Region",
      name: "region",
      options: [
        { value: "emea", name: "EMEA" },
        { value: "latam", name: "LATAM" },
      ],
      maxVisibleItems: 1,
    };
    const sidebarFilter = await mountInForm("events-form", properties);
    const sheetFilter = await mountInForm("events-form-mobile", properties);

    // Each filter owns a distinct list id.
    const sidebarList = sidebarFilter.querySelector("ul");
    const sheetList = sheetFilter.querySelector("ul");
    expect(sidebarList?.id).to.equal("events-form-region-filter-options");
    expect(sheetList?.id).to.equal("events-form-mobile-region-filter-options");

    // Both collapse controls point at the list of their own filter.
    [
      [sidebarFilter, sidebarList],
      [sheetFilter, sheetList],
    ].forEach(([filter, list]) => {
      const controls = [...filter.querySelectorAll("[aria-controls]")];
      expect(controls.map((control) => control.getAttribute("aria-controls"))).to.deep.equal([
        list?.id,
        list?.id,
      ]);
    });
  });

  it("marks Any as pressed only without a selection", async () => {
    // Render a filter with nothing selected.
    const element = await mountLitComponent("collapsible-filter", {
      title: "Region",
      name: "region",
      options: [{ value: "emea", name: "EMEA" }],
    });
    const anyButton = element.querySelector('button[aria-label="Any Region"]');
    expect(anyButton?.getAttribute("aria-pressed")).to.equal("true");

    // Selecting an option releases Any.
    element.querySelector('input[value="emea"]')?.dispatchEvent(new Event("change", { bubbles: true }));
    await element.updateComplete;
    expect(anyButton?.getAttribute("aria-pressed")).to.equal("false");

    // Choosing Any again presses it.
    anyButton?.click();
    await element.updateComplete;
    expect(anyButton?.getAttribute("aria-pressed")).to.equal("true");
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
    const media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
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
      media.restore();
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
    otherCollapsible.toggleAttribute("data-community-dependent", true);
    otherCollapsible.cleanSelected = () => {
      dependentCalls.push("collapsible");
    };
    const multiSelect = document.createElement("multi-select-filter");
    multiSelect.toggleAttribute("data-community-dependent", true);
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

  it("keeps unmarked filters such as distance when the community changes", async () => {
    // Build a community filter beside a marked filter and an unmarked distance filter.
    const { cleanCalls, community } = await mountCommunityFilters();

    // Select a community.
    community.querySelector('input[value="one"]')?.dispatchEvent(new Event("change", { bubbles: true }));
    await community.updateComplete;

    // Only the marked filter is cleared; distance keeps its value.
    expect(community.selected).to.deep.equal(["one"]);
    expect(cleanCalls).to.deep.equal(["region"]);
  });

  it("clears marked filters when Any is selected", async () => {
    // Build a selected community filter beside a marked and an unmarked filter.
    const { cleanCalls, community } = await mountCommunityFilters(["one"]);

    // Choose Any in the community filter.
    community.querySelector('button[aria-label="Any Community"]')?.click();
    await community.updateComplete;

    // The community clears with the marked filter, and distance keeps its value.
    expect(community.selected).to.deep.equal([]);
    expect(cleanCalls).to.deep.equal(["region"]);
  });
});

/**
 * Mounts a community filter in a form beside a marked region filter and an
 * unmarked distance filter that record their cleanSelected calls.
 * @param {string[]} [selected=[]] - Initially selected community values
 * @returns {Promise<{cleanCalls: string[], community: HTMLElement}>} Fixture parts
 */
const mountCommunityFilters = async (selected = []) => {
  document.body.innerHTML = '<form id="filters-form"></form>';
  const form = document.getElementById("filters-form");
  const cleanCalls = [];

  // Create the sibling filters with recording cleanSelected stubs.
  const region = document.createElement("collapsible-filter");
  region.setAttribute("name", "region");
  region.toggleAttribute("data-community-dependent", true);
  region.cleanSelected = () => cleanCalls.push("region");
  const distance = document.createElement("collapsible-filter");
  distance.setAttribute("name", "distance");
  distance.cleanSelected = () => cleanCalls.push("distance");

  // Create the community filter that resets dependent filters.
  const community = document.createElement("collapsible-filter");
  Object.assign(community, {
    title: "Community",
    name: "community",
    options: [
      { value: "one", name: "One" },
      { value: "two", name: "Two" },
    ],
    selected,
    singleSelection: true,
    resetDependentFilters: true,
  });

  form.append(community, region, distance);
  await community.updateComplete;

  return { cleanCalls, community };
};

/**
 * Mounts a collapsible filter inside a form with the given id.
 * @param {string} formId - Id of the wrapping form
 * @param {object} properties - Filter properties
 * @returns {Promise<HTMLElement>} Rendered filter
 */
const mountInForm = async (formId, properties) => {
  const form = document.createElement("form");
  form.id = formId;
  document.body.append(form);

  const element = document.createElement("collapsible-filter");
  Object.assign(element, properties);
  form.append(element);
  await element.updateComplete;

  return element;
};
