import { expect } from "@open-wc/testing";

import "/static/js/common/label-selector.js";
import { renderViewportBottomLayout } from "/tests/unit/test-utils/dom.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("label-selector", () => {
  useMountedElementsCleanup("label-selector");

  it("normalizes labels and prunes invalid selections", async () => {
    // Render the label-selector fixture.
    const element = await mountLitComponent("label-selector", {
      labels: [
        { event_label_id: 1, name: "Backend", color: "blue" },
        { event_label_id: 1, name: "Duplicate", color: "red" },
        { event_label_id: 2, name: "Frontend", color: "green" },
        { event_label_id: "", name: "Ignored", color: "gray" },
      ],
      selected: ["1", "missing"],
    });

    // Let the component finish rendering.
    await element.updateComplete;

    // The selected event carries the expected payload.
    expect(element.labels).to.deep.equal([
      { event_label_id: "1", name: "Backend", color: "blue" },
      { event_label_id: "2", name: "Frontend", color: "green" },
    ]);
    expect(element.selected).to.deep.equal(["1"]);
  });

  it("toggles selections while respecting the maximum selection count", async () => {
    // Render the label-selector fixture.
    const element = await mountLitComponent("label-selector", {
      labels: [
        { event_label_id: "1", name: "Backend", color: "blue" },
        { event_label_id: "2", name: "Frontend", color: "green" },
      ],
      maxSelected: 1,
    });
    let changeEvents = 0;

    // Track emitted change events while toggling selected labels.
    element.addEventListener("change", () => {
      changeEvents += 1;
    });

    // Toggle labels through the maximum selection boundary.
    await element._toggleSelection("1");
    await element._toggleSelection("2");
    await element._toggleSelection("1");

    // The selected event carries the expected payload.
    expect(element.selected).to.deep.equal([]);
    expect(changeEvents).to.equal(2);
  });

  it("opens the labels above the search input near the viewport bottom", async () => {
    // Render the component near the bottom of the viewport.
    renderViewportBottomLayout(80);
    const element = await mountLitComponent("label-selector", {
      labels: Array.from({ length: 12 }, (_, index) => ({
        event_label_id: `${index + 1}`,
        name: `Label ${index + 1}`,
        color: "blue",
      })),
    });

    // Open the labels dropdown.
    element._combobox.open();
    await element.updateComplete;

    // The labels open upward and stay inside the viewport.
    const search = element.querySelector("[data-multi-select-search]");
    const dropdownBounds = element.querySelector("[data-multi-select-dropdown]").getBoundingClientRect();
    expect(dropdownBounds.height).to.be.greaterThan(0);
    expect(dropdownBounds.bottom).to.be.at.most(search.getBoundingClientRect().top);
    expect(dropdownBounds.top).to.be.at.least(0);
  });

  it("maps labels to options and keeps the hidden inputs current on change", async () => {
    // Render the selector inside a form.
    document.body.innerHTML = '<form id="labels-form"></form>';
    const form = document.getElementById("labels-form");
    const element = document.createElement("label-selector");
    element.labels = [
      { event_label_id: "2", name: "Frontend", color: "green" },
      { event_label_id: "1", name: "Backend", color: "blue" },
    ];
    form.append(element);
    await element.updateComplete;
    const submittedValues = [];
    element.addEventListener("change", () => {
      submittedValues.push(new FormData(form).getAll("label_ids[]"));
    });

    // Open the dropdown and select a label.
    element.querySelector('input[role="combobox"]').dispatchEvent(new FocusEvent("focus"));
    await element.updateComplete;
    element.querySelector('[role="option"]').click();
    await element.updateComplete;

    // Verify the options, colored chip and hidden input.
    expect(element.options).to.deep.equal([
      { color: "green", name: "Frontend", value: "2" },
      { color: "blue", name: "Backend", value: "1" },
    ]);
    expect(submittedValues).to.deep.equal([["1"]]);
    expect(element.querySelector('[title="Backend"]').getAttribute("style")).to.include("--label-color:blue");
    expect(element.querySelector('[aria-label="Remove Backend"]')).to.not.equal(null);
  });

  it("uses only the generic placement markers", async () => {
    // Render the selector with labels.
    const element = await mountLitComponent("label-selector", {
      labels: [{ event_label_id: "1", name: "Backend", color: "blue" }],
    });

    // Open the labels dropdown.
    element._combobox.open();
    await element.updateComplete;

    // Verify the generic markers exist and no domain-specific markers remain.
    const dropdown = element.querySelector("[data-multi-select-dropdown]");
    expect(element.querySelector("[data-multi-select-search]")).to.not.equal(null);
    expect(dropdown.getAttribute("role")).to.equal("listbox");
    const legacyMarkers = Array.from(element.querySelectorAll("*")).filter((node) =>
      node.getAttributeNames().some((name) => name.startsWith("data-cfs")),
    );
    expect(legacyMarkers).to.deep.equal([]);
  });
});
