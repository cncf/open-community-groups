import { expect } from "@open-wc/testing";

import "/static/js/community/explore/multi-select-filter.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { renderViewportBottomLayout } from "/tests/unit/test-utils/dom.js";
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
      title: "Group",
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
    expect(input.getAttribute("role")).to.equal("combobox");
    expect(input.getAttribute("aria-expanded")).to.equal("true");
    const listbox = element.querySelector('[role="listbox"]');
    expect(listbox?.id).to.not.equal("");
    expect(input.getAttribute("aria-controls")).to.equal(listbox?.id);
    expect(listbox?.children[0]?.getAttribute("role")).to.equal("option");

    // Verify filters typed options and renders hidden inputs.
    element.querySelector('[role="option"]')?.click();
    await element.updateComplete;

    // Verify filters typed options and renders hidden inputs for selected values.
    expect(element.selected).to.deep.equal(["security"]);
    expect(element.querySelector('input[type="hidden"][value="security"]')).to.not.equal(null);
    expect(element.textContent).to.include("Security");
    expect(input.value).to.equal("");
    expect(element.querySelector('[aria-label="Clear Group"]')).to.equal(null);
    expect(element.querySelector('[aria-label="Remove Security"]')).to.not.equal(null);

    // Verify selected options stay mirrored in hidden inputs.
    element.querySelector('[aria-label="Remove Security"]').click();
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
      title: "Group",
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
    const firstOption = element.querySelector('[role="option"]');
    expect(firstOption?.id).to.not.equal("");
    expect(input.getAttribute("aria-activedescendant")).to.equal(firstOption?.id);

    // Click outside the filter to close the options.
    document.dispatchEvent(new MouseEvent("click", { bubbles: true, composed: true }));
    await waitForMicrotask();

    // Verify supports keyboard navigation and closes on outside clicks.
    expect(element._combobox.isOpen).to.equal(false);
  });

  it("emits one current filter-change and no native change per toggle", async () => {
    // Render the filter inside a form.
    document.body.innerHTML = '<form id="filters-form"></form>';
    const form = document.getElementById("filters-form");
    const element = document.createElement("multi-select-filter");
    Object.assign(element, {
      title: "Group",
      name: "group",
      options: [
        { value: "cloud", name: "Cloud" },
        { value: "ai", name: "AI" },
      ],
    });
    form.append(element);
    await element.updateComplete;
    const filterChangeValues = [];
    let changeEvents = 0;
    form.addEventListener("filter-change", () => {
      filterChangeValues.push(new FormData(form).getAll("group[]"));
    });
    form.addEventListener("change", () => {
      changeEvents += 1;
    });

    // Toggle options through the listbox.
    element.querySelector('input[type="text"]').dispatchEvent(new FocusEvent("focus"));
    await element.updateComplete;
    element.querySelectorAll('[role="option"]')[1].click();
    await element.updateComplete;
    element.querySelectorAll('[role="option"]')[0].click();
    await element.updateComplete;

    // Verify the kept option order and the current form values.
    expect(
      [...element.querySelectorAll('[role="option"]')].map((option) => option.textContent.trim()),
    ).to.deep.equal(["Cloud", "AI"]);
    expect(filterChangeValues).to.deep.equal([["ai"], ["ai", "cloud"]]);
    expect(changeEvents).to.equal(0);
  });

  it("opens the options above the search box near the viewport bottom", async () => {
    // Render the filter near the bottom of the viewport.
    renderViewportBottomLayout(80);
    document.head.insertAdjacentHTML(
      "beforeend",
      '<style id="multi-select-filter-test-styles">.max-h-48 { max-height: 12rem; }</style>',
    );
    const element = await mountLitComponent("multi-select-filter", {
      title: "Group",
      options: Array.from({ length: 12 }, (_, index) => ({
        value: `group-${index}`,
        name: `Group ${index}`,
      })),
    });

    // Open the options dropdown.
    element.querySelector('input[type="text"]').dispatchEvent(new FocusEvent("focus"));
    await element.updateComplete;

    // Verify the options open upward and stay inside the viewport.
    const search = element.querySelector("[data-multi-select-search]");
    const dropdownBounds = element.querySelector("[data-multi-select-dropdown]").getBoundingClientRect();
    document.getElementById("multi-select-filter-test-styles").remove();
    expect(dropdownBounds.height).to.be.greaterThan(0);
    expect(dropdownBounds.bottom).to.be.at.most(search.getBoundingClientRect().top);
    expect(dropdownBounds.top).to.be.at.least(0);
  });

  it("gives two same-name filters different listbox ids", async () => {
    // Render the same filter twice, as the sidebar and the phone sheet do.
    const properties = {
      title: "Group",
      name: "group",
      options: [{ value: "cloud", name: "Cloud" }],
    };
    const filters = [
      await mountLitComponent("multi-select-filter", properties),
      await mountLitComponent("multi-select-filter", properties),
    ];

    // Open each dropdown and read the listbox its search box controls.
    const listboxIds = [];
    for (const filter of filters) {
      const input = filter.querySelector('input[type="text"]');
      input.dispatchEvent(new FocusEvent("focus"));
      await filter.updateComplete;

      const listbox = filter.querySelector('[role="listbox"]');
      expect(listbox?.id).to.not.equal("");
      expect(input.getAttribute("aria-controls")).to.equal(listbox?.id);
      listboxIds.push(listbox?.id);
    }

    // Verify the two listboxes do not share an id.
    expect(listboxIds[0]).to.not.equal(listboxIds[1]);
  });

  it("keeps focus on the next chip after a removal and marks chips and search with focus keys", async () => {
    // Render the filter with two selected groups.
    const element = await mountLitComponent("multi-select-filter", {
      title: "Group",
      name: "group",
      options: [
        { value: "cloud", name: "Cloud" },
        { value: "ai", name: "AI" },
      ],
      selected: ["cloud", "ai"],
    });
    const focusKeysOnChange = [];
    element.addEventListener("filter-change", () =>
      focusKeysOnChange.push(document.activeElement?.dataset.focusKey),
    );

    // Verify the search input and chip remove buttons carry stable focus keys.
    const input = element.querySelector('input[role="combobox"]');
    expect(input.dataset.focusKey).to.equal("search");
    const removeButtons = [...element.querySelectorAll("[data-multi-select-chip-remove]")];
    expect(removeButtons.map((button) => button.dataset.focusKey)).to.deep.equal(["chip:cloud", "chip:ai"]);

    // Remove the first chip from the keyboard focus.
    const cloudButton = element.querySelector('[aria-label="Remove Cloud"]');
    cloudButton.focus();
    cloudButton.click();
    await element.updateComplete;

    // Verify focus moved to the next chip before the filter change was emitted.
    expect(element.selected).to.deep.equal(["ai"]);
    expect(document.activeElement?.getAttribute("aria-label")).to.equal("Remove AI");
    expect(focusKeysOnChange).to.deep.equal(["chip:ai"]);
  });
});
