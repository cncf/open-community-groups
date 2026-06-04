import { expect } from "@open-wc/testing";

import "/static/js/common/cfs-label-selector.js";
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
});
