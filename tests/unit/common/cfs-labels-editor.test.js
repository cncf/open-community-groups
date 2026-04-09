import { expect } from "@open-wc/testing";

import "/static/js/common/cfs-labels-editor.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";

describe("cfs-labels-editor", () => {
  afterEach(() => {
    removeMountedElements("cfs-labels-editor");
    resetDom();
  });

  it("normalizes and sorts the initial label rows", async () => {
    const element = await mountLitComponent("cfs-labels-editor", {
      colors: ["blue", "green"],
      labels: [
        { event_cfs_label_id: 2, name: "Frontend", color: "green" },
        { event_cfs_label_id: 1, name: "Backend", color: "invalid" },
        { event_cfs_label_id: 3, name: "", color: "blue" },
      ],
    });

    expect(element._rows.map((row) => row.name)).to.deep.equal(["Backend", "Frontend"]);
    expect(element._rows[0].color).to.equal("blue");
  });

  it("adds rows, updates color, and keeps one empty row after removals", async () => {
    const element = await mountLitComponent("cfs-labels-editor", {
      colors: ["blue", "green"],
      labels: [],
    });

    element._addRow();
    const rowId = element._rows[1]._row_id;
    element._setRowColor(rowId, "green");
    element._removeRow(element._rows[0]._row_id);
    element._removeRow(rowId);

    expect(element._rows).to.have.length(1);
    expect(element._rows[0].name).to.equal("");
  });
});
