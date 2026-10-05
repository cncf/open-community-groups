import { expect } from "@open-wc/testing";

import "/static/js/common/cfs-label-selector.js";
import { renderViewportBottomLayout } from "/tests/unit/test-utils/dom.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("cfs-label-selector", () => {
  useMountedElementsCleanup("cfs-label-selector");

  it("normalizes labels and prunes invalid selections", async () => {
    // Render the cfs-label-selector fixture.
    const element = await mountLitComponent("cfs-label-selector", {
      labels: [
        { event_cfs_label_id: 1, name: "Backend", color: "blue" },
        { event_cfs_label_id: 1, name: "Duplicate", color: "red" },
        { event_cfs_label_id: 2, name: "Frontend", color: "green" },
        { event_cfs_label_id: "", name: "Ignored", color: "gray" },
      ],
      selected: ["1", "missing"],
    });

    // Let the component finish rendering.
    await element.updateComplete;

    // The selected event carries the expected payload.
    expect(element.labels).to.deep.equal([
      { event_cfs_label_id: "1", name: "Backend", color: "blue" },
      { event_cfs_label_id: "2", name: "Frontend", color: "green" },
    ]);
    expect(element.selected).to.deep.equal(["1"]);
  });

  it("toggles selections while respecting the maximum selection count", async () => {
    // Render the cfs-label-selector fixture.
    const element = await mountLitComponent("cfs-label-selector", {
      labels: [
        { event_cfs_label_id: "1", name: "Backend", color: "blue" },
        { event_cfs_label_id: "2", name: "Frontend", color: "green" },
      ],
      maxSelected: 1,
    });
    let changeEvents = 0;

    // Track emitted change events while toggling selected labels.
    element.addEventListener("change", () => {
      changeEvents += 1;
    });

    // Toggle labels through the maximum selection boundary.
    element._toggleSelection("1");
    element._toggleSelection("2");
    element._toggleSelection("1");

    // The selected event carries the expected payload.
    expect(element.selected).to.deep.equal([]);
    expect(changeEvents).to.equal(2);
  });

  it("opens the labels above the search input near the viewport bottom", async () => {
    // Render the component near the bottom of the viewport.
    renderViewportBottomLayout(80);
    const element = await mountLitComponent("cfs-label-selector", {
      labels: Array.from({ length: 12 }, (_, index) => ({
        event_cfs_label_id: `${index + 1}`,
        name: `Label ${index + 1}`,
        color: "blue",
      })),
    });

    // Open the labels dropdown.
    element._combobox.open();
    await element.updateComplete;

    // The labels open upward and stay inside the viewport.
    const search = element.querySelector("[data-cfs-label-search]");
    const dropdownBounds = element.querySelector("[data-cfs-label-dropdown]").getBoundingClientRect();
    expect(dropdownBounds.height).to.be.greaterThan(0);
    expect(dropdownBounds.bottom).to.be.at.most(search.getBoundingClientRect().top);
    expect(dropdownBounds.top).to.be.at.least(0);
  });
});
