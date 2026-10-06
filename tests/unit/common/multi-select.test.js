import { expect } from "@open-wc/testing";

import { MultiSelect } from "/static/js/common/multi-select.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { renderViewportBottomLayout } from "/tests/unit/test-utils/dom.js";
import {
  mountLitComponent,
  mountLitComponentWithAttributes,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

const OPTIONS = [
  { value: "3", name: "Cloud" },
  { value: "1", name: "AI" },
  { value: "2", name: "Backend" },
];

/**
 * Mounts a multi-select inside a form so tests can read submitted values.
 * @param {object} properties Component properties
 * @returns {Promise<{element: MultiSelect, form: HTMLFormElement}>}
 */
const mountInForm = async (properties) => {
  document.body.innerHTML = '<form id="multi-select-form"></form>';
  const form = document.getElementById("multi-select-form");
  const element = document.createElement("multi-select");
  Object.assign(element, { name: "filters[regions]", ...properties });
  form.append(element);
  await element.updateComplete;
  return { element, form };
};

/**
 * Opens the dropdown through the search input focus.
 * @param {MultiSelect} element Mounted component
 * @returns {Promise<HTMLInputElement>}
 */
const openDropdown = async (element) => {
  const input = element.querySelector('input[role="combobox"]');
  input.dispatchEvent(new FocusEvent("focus"));
  await element.updateComplete;
  return input;
};

/**
 * Dispatches a keydown event on the component.
 * @param {MultiSelect} element Mounted component
 * @param {string} key Keyboard key
 * @returns {Promise<void>}
 */
const pressKey = async (element, key) => {
  element.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true }));
  await element.updateComplete;
};

describe("multi-select", () => {
  useMountedElementsCleanup("multi-select");

  it("registers the custom element once", () => {
    expect(customElements.get("multi-select")).to.equal(MultiSelect);
  });

  it("normalizes options and selections from JSON attributes", async () => {
    // Render the component the way server templates do.
    const element = await mountLitComponentWithAttributes("multi-select", {
      attributes: {
        name: "filters[regions]",
        options: JSON.stringify([
          { value: 7, name: " Europe ", color: "" },
          { value: "7", name: "Duplicate" },
          { value: "", name: "Ignored" },
          { value: "8", name: "" },
          { value: "9", name: "Asia", color: "red" },
        ]),
        selected: JSON.stringify([7, "7", ""]),
      },
    });

    // Verify the normalized options and selections.
    expect(element.options).to.deep.equal([
      { value: "7", name: "Europe" },
      { value: "9", name: "Asia", color: "red" },
    ]);
    expect(element.selected).to.deep.equal(["7"]);
  });

  it("prunes selections missing from the options after rendering", async () => {
    // Render the component with a stale selection.
    const { element, form } = await mountInForm({ options: OPTIONS, selected: ["1", "2"] });
    const submittedValues = [];
    element.addEventListener("change", () => {
      submittedValues.push(new FormData(form).getAll("filters[regions][]"));
    });

    // Replace the options so one selection becomes invalid.
    element.options = OPTIONS.filter((option) => option.value !== "2");
    await element.updateComplete;
    await waitForMicrotask();

    // Verify the change event sees the pruned hidden inputs.
    expect(element.selected).to.deep.equal(["1"]);
    expect(submittedValues).to.deep.equal([["1"]]);
  });

  it("sorts options alphabetically unless keep-order is set", async () => {
    // Render one sorted and one ordered component.
    const sorted = await mountLitComponent("multi-select", { options: OPTIONS });
    const ordered = await mountLitComponentWithAttributes("multi-select", {
      attributes: { "keep-order": "" },
      properties: { options: OPTIONS },
    });

    // Open both dropdowns.
    await openDropdown(sorted);
    await openDropdown(ordered);

    // Verify the option order.
    const names = (element) =>
      [...element.querySelectorAll('[role="option"]')].map((option) => option.textContent.trim());
    expect(ordered.keepOrder).to.equal(true);
    expect(names(sorted)).to.deep.equal(["AI", "Backend", "Cloud"]);
    expect(names(ordered)).to.deep.equal(["Cloud", "AI", "Backend"]);
  });

  it("toggles selections up to the maximum and renders name[] hidden inputs", async () => {
    // Render the component with a selection limit.
    const { element, form } = await mountInForm({ options: OPTIONS, maxSelected: 2 });
    let changeEvents = 0;
    element.addEventListener("change", () => {
      changeEvents += 1;
    });

    // Select options through the limit.
    await element._toggleSelection("1");
    await element._toggleSelection("2");
    await element._toggleSelection("3");
    await openDropdown(element);

    // Verify the limit blocks extra selections and disables remaining options.
    expect(element.selected).to.deep.equal(["1", "2"]);
    expect(changeEvents).to.equal(2);
    expect(new FormData(form).getAll("filters[regions][]")).to.deep.equal(["1", "2"]);
    const cloudOption = [...element.querySelectorAll('[role="option"]')].find(
      (option) => option.textContent.trim() === "Cloud",
    );
    expect(cloudOption.getAttribute("aria-disabled")).to.equal("true");

    // Deselect one option to free the limit.
    await element._toggleSelection("1");
    expect(element.selected).to.deep.equal(["2"]);
    expect(changeEvents).to.equal(3);
    expect(cloudOption.hasAttribute("aria-disabled")).to.equal(false);
  });

  it("emits change after the hidden inputs render for toggle, remove and clear", async () => {
    // Render the component inside a form.
    const { element, form } = await mountInForm({ options: OPTIONS, selectedInInput: true });
    const submittedValues = [];
    element.addEventListener("change", (event) => {
      expect(event.bubbles).to.equal(true);
      submittedValues.push(new FormData(form).getAll("filters[regions][]"));
    });

    // Toggle options through the listbox.
    await openDropdown(element);
    element.querySelector('[role="option"]').click();
    await element.updateComplete;
    element.querySelectorAll('[role="option"]')[1].click();
    await element.updateComplete;

    // Remove one chip and clear the rest.
    element.querySelector('[aria-label="Remove AI"]').click();
    await element.updateComplete;
    element.querySelector('[aria-label="Clear selection"]').click();
    await element.updateComplete;

    // Verify every listener saw the current form values.
    expect(submittedValues).to.deep.equal([["1"], ["1", "2"], ["2"], []]);
  });

  it("does not leak the search input change event", async () => {
    // Render the component and listen for change events.
    const { element, form } = await mountInForm({ options: OPTIONS });
    let changeEvents = 0;
    form.addEventListener("change", () => {
      changeEvents += 1;
    });

    // Commit a search query like a blur would.
    const input = await openDropdown(element);
    input.value = "Clo";
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
    await element.updateComplete;

    // Verify the query filtered the options without a change event.
    expect(element._filteredOptions).to.deep.equal([{ value: "3", name: "Cloud" }]);
    expect(changeEvents).to.equal(0);
  });

  it("blocks interactions while disabled", async () => {
    // Render the component with a selection.
    const element = await mountLitComponent("multi-select", {
      name: "filters[regions]",
      options: OPTIONS,
      selected: ["1"],
    });
    await openDropdown(element);
    let changeEvents = 0;
    element.addEventListener("change", () => {
      changeEvents += 1;
    });

    // Disable the component.
    element.disabled = true;
    await element.updateComplete;
    await element.updateComplete;

    // Try to change the selection.
    await element._toggleSelection("2");
    await element._removeSelection("1");
    await element._clearSelections();

    // Verify the selection and controls stay disabled.
    expect(element._combobox.isOpen).to.equal(false);
    expect(element.selected).to.deep.equal(["1"]);
    expect(changeEvents).to.equal(0);
    expect(element.querySelector('input[role="combobox"]').disabled).to.equal(true);
    expect(element.querySelector('[aria-label="Remove AI"]').disabled).to.equal(true);
  });

  it("renders neutral chips without a color and colored chips with one", async () => {
    // Render options with and without a color.
    const element = await mountLitComponent("multi-select", {
      options: [
        { value: "1", name: "Neutral" },
        { value: "2", name: "Colored", color: "#ff0000" },
      ],
      selected: ["1", "2"],
    });

    // Verify the chip styles.
    const neutralChip = element.querySelector('[title="Neutral"]');
    const coloredChip = element.querySelector('[title="Colored"]');
    expect(neutralChip.hasAttribute("style")).to.equal(false);
    expect(neutralChip.classList.contains("bg-stone-100")).to.equal(true);
    expect(coloredChip.getAttribute("style")).to.include("--label-color:#ff0000");
    expect(coloredChip.classList.contains("bg-stone-100")).to.equal(false);
  });

  it("cleans selections and the query without emitting events", async () => {
    // Render the component with a selection and a query.
    const element = await mountLitComponent("multi-select", {
      name: "filters[regions]",
      options: OPTIONS,
      selected: ["1", "2"],
    });
    element._combobox.setQuery("AI");
    let changeEvents = 0;
    element.addEventListener("change", () => {
      changeEvents += 1;
    });

    // Reset the component.
    element.cleanSelected();
    await element.updateComplete;

    // Verify the reset state.
    expect(element.selected).to.deep.equal([]);
    expect(element._combobox.query).to.equal("");
    expect(element.querySelectorAll('input[type="hidden"]')).to.have.length(0);
    expect(changeEvents).to.equal(0);
  });

  it("links the combobox, listbox and options with ARIA attributes", async () => {
    // Render a labelled component with an id and a legend.
    document.body.innerHTML = '<span id="regions-label">Regions</span>';
    const element = await mountLitComponentWithAttributes("multi-select", {
      attributes: {
        id: "regions",
        labelledby: "regions-label",
        legend: "Pick regions",
        name: "filters[regions]",
      },
      properties: { options: OPTIONS, selected: ["2"] },
    });

    // Open the dropdown and highlight the first option.
    const input = await openDropdown(element);
    await pressKey(element, "ArrowDown");

    // Verify the combobox attributes.
    const listbox = element.querySelector('[role="listbox"]');
    const options = element.querySelectorAll('[role="option"]');
    expect(input.getAttribute("aria-autocomplete")).to.equal("list");
    expect(input.getAttribute("aria-haspopup")).to.equal("listbox");
    expect(input.getAttribute("aria-expanded")).to.equal("true");
    expect(input.getAttribute("aria-controls")).to.equal("regions-listbox");
    expect(input.getAttribute("aria-labelledby")).to.equal("regions-label");
    expect(input.hasAttribute("aria-label")).to.equal(false);
    expect(input.getAttribute("aria-describedby")).to.equal("regions-legend");
    expect(document.getElementById("regions-legend").textContent).to.equal("Pick regions");
    expect(listbox.id).to.equal("regions-listbox");
    expect(listbox.getAttribute("aria-multiselectable")).to.equal("true");
    expect([...options].map((option) => option.id)).to.deep.equal([
      "regions-option-0",
      "regions-option-1",
      "regions-option-2",
    ]);
    expect(options[1].getAttribute("aria-selected")).to.equal("true");
    expect(options[0].getAttribute("aria-selected")).to.equal("false");
    expect(input.getAttribute("aria-activedescendant")).to.equal("regions-option-0");
    expect(options[0].classList.contains("bg-stone-100")).to.equal(true);

    // Close the dropdown.
    await pressKey(element, "Escape");

    // Verify the closed state.
    expect(input.getAttribute("aria-expanded")).to.equal("false");
    expect(input.hasAttribute("aria-activedescendant")).to.equal(false);
  });

  it("builds unique ids from the name and uses the label attribute", async () => {
    // Render two components without ids.
    const first = await mountLitComponent("multi-select", {
      label: "Categories",
      name: "filters[group_category_ids]",
      options: OPTIONS,
    });
    const second = await mountLitComponent("multi-select", {
      label: "Categories",
      name: "filters[group_category_ids]",
      options: OPTIONS,
    });

    // Verify the generated ids and accessible name.
    const firstInput = first.querySelector('input[role="combobox"]');
    const secondInput = second.querySelector('input[role="combobox"]');
    expect(firstInput.getAttribute("aria-label")).to.equal("Categories");
    expect(firstInput.getAttribute("aria-controls")).to.match(
      /^multi-select-filters-group_category_ids-\d+-listbox$/,
    );
    expect(firstInput.getAttribute("aria-controls")).to.not.equal(secondInput.getAttribute("aria-controls"));
  });

  it("navigates and selects options with the keyboard", async () => {
    // Render the component and open the dropdown.
    const element = await mountLitComponent("multi-select", {
      name: "filters[regions]",
      options: OPTIONS,
    });
    const input = await openDropdown(element);

    // Highlight the first option, then move up to wrap around to the last one.
    await pressKey(element, "ArrowDown");
    expect(input.getAttribute("aria-activedescendant")).to.match(/-option-0$/);
    await pressKey(element, "ArrowUp");
    expect(input.getAttribute("aria-activedescendant")).to.match(/-option-2$/);

    // Move down to wrap around to the first option and select it.
    await pressKey(element, "ArrowDown");
    await pressKey(element, "Enter");
    await element.updateComplete;
    expect(element.selected).to.deep.equal(["1"]);
    expect(element._combobox.isOpen).to.equal(true);

    // Toggle the same option off.
    await pressKey(element, "Enter");
    await element.updateComplete;
    expect(element.selected).to.deep.equal([]);
  });

  it("closes after selecting when close-on-select is set", async () => {
    // Render the component with close-on-select.
    const element = await mountLitComponentWithAttributes("multi-select", {
      attributes: { "close-on-select": "" },
      properties: { options: OPTIONS },
    });

    // Select an option.
    await openDropdown(element);
    element.querySelector('[role="option"]').click();
    await element.updateComplete;

    // Verify the dropdown closed.
    expect(element.selected).to.deep.equal(["1"]);
    expect(element._combobox.isOpen).to.equal(false);
  });

  it("opens the dropdown above the search input near the viewport bottom", async () => {
    // Render the component near the bottom of the viewport.
    renderViewportBottomLayout(80);
    const element = await mountLitComponent("multi-select", {
      options: Array.from({ length: 12 }, (_, index) => ({
        value: `${index + 1}`,
        name: `Option ${index + 1}`,
      })),
    });

    // Open the dropdown.
    await openDropdown(element);

    // Verify the dropdown opens upward and stays inside the viewport.
    const search = element.querySelector("[data-multi-select-search]");
    const dropdownBounds = element.querySelector("[data-multi-select-dropdown]").getBoundingClientRect();
    expect(dropdownBounds.height).to.be.greaterThan(0);
    expect(dropdownBounds.bottom).to.be.at.most(search.getBoundingClientRect().top);
    expect(dropdownBounds.top).to.be.at.least(0);
  });

  it("renders the empty message when no option matches", async () => {
    // Render the component and search for a missing option.
    const element = await mountLitComponentWithAttributes("multi-select", {
      attributes: { "empty-message": "No regions found" },
      properties: { options: OPTIONS },
    });
    const input = await openDropdown(element);
    input.value = "missing";
    input.dispatchEvent(new Event("input", { bubbles: true }));
    await element.updateComplete;

    // Verify the empty state.
    expect(element.querySelectorAll('[role="option"]')).to.have.length(0);
    expect(element.querySelector('[role="listbox"]').textContent.trim()).to.equal("No regions found");
  });

  it("handles large option sets", async () => {
    // Render a large option set.
    const element = await mountLitComponent("multi-select", {
      name: "filters[regions]",
      options: Array.from({ length: 2000 }, (_, index) => ({
        value: `${index}`,
        name: `Region ${String(index).padStart(4, "0")}`,
      })),
    });

    // Search and select a single option.
    const input = await openDropdown(element);
    expect(element.querySelectorAll('[role="option"]')).to.have.length(2000);
    input.value = "Region 1999";
    input.dispatchEvent(new Event("input", { bubbles: true }));
    await element.updateComplete;
    element.querySelector('[role="option"]').click();
    await element.updateComplete;

    // Verify the filtered result and selection.
    expect(element.querySelectorAll('[role="option"]')).to.have.length(1);
    expect(element.selected).to.deep.equal(["1999"]);
  });
});
