import { expect } from "@open-wc/testing";

import "/static/js/common/cfs-label-selector.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";

describe("cfs-label-selector", () => {
  afterEach(() => {
    removeMountedElements("cfs-label-selector");
    resetDom();
  });

  it("normalizes labels and prunes invalid selections", async () => {
    const element = await mountLitComponent("cfs-label-selector", {
      labels: [
        { event_cfs_label_id: 1, name: "Backend", color: "blue" },
        { event_cfs_label_id: 1, name: "Duplicate", color: "red" },
        { event_cfs_label_id: 2, name: "Frontend", color: "green" },
        { event_cfs_label_id: "", name: "Ignored", color: "gray" },
      ],
      selected: ["1", "missing"],
    });

    await element.updateComplete;

    expect(element.labels).to.deep.equal([
      { event_cfs_label_id: "1", name: "Backend", color: "blue" },
      { event_cfs_label_id: "2", name: "Frontend", color: "green" },
    ]);
    expect(element.selected).to.deep.equal(["1"]);
  });

  it("toggles selections while respecting the maximum selection count", async () => {
    const element = await mountLitComponent("cfs-label-selector", {
      labels: [
        { event_cfs_label_id: "1", name: "Backend", color: "blue" },
        { event_cfs_label_id: "2", name: "Frontend", color: "green" },
      ],
      maxSelected: 1,
    });
    let changeEvents = 0;

    element.addEventListener("change", () => {
      changeEvents += 1;
    });

    element._toggleSelection("1");
    element._toggleSelection("2");
    element._toggleSelection("1");

    expect(element.selected).to.deep.equal([]);
    expect(changeEvents).to.equal(2);
  });
});
