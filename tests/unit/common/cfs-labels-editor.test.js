import { expect } from "@open-wc/testing";

import "/static/js/common/cfs-labels-editor.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("cfs-labels-editor", () => {
  useMountedElementsCleanup("cfs-labels-editor");

  it("normalizes and sorts the initial label rows", async () => {
    // Render the cfs-labels-editor fixture.
    const element = await mountLitComponent("cfs-labels-editor", {
      colors: ["blue", "green"],
      labels: [
        { event_cfs_label_id: 2, name: "Frontend", color: "green" },
        { event_cfs_label_id: 1, name: "Backend", color: "invalid" },
        { event_cfs_label_id: 3, name: "", color: "blue" },
      ],
    });

    // The editor keeps only valid labels sorted by name.
    expect(element._rows.map((row) => row.name)).to.deep.equal([
      "Backend",
      "Frontend",
    ]);
    expect(element._rows[0].color).to.equal("blue");
  });

  it("adds rows, updates color, and keeps one empty row after removals", async () => {
    // Render the cfs-labels-editor fixture.
    const element = await mountLitComponent("cfs-labels-editor", {
      colors: ["blue", "green"],
      labels: [],
    });

    // Add a row, update its color, and remove rows back to one draft.
    element._addRow();
    const rowId = element._rows[1]._row_id;
    element._setRowColor(rowId, "green");
    element._removeRow(element._rows[0]._row_id);
    element._removeRow(rowId);

    // The editor falls back to one empty draft row after removals.
    expect(element._rows).to.have.length(1);
    expect(element._rows[0].name).to.equal("");
  });

  it("preserves a custom legend across reconnects", async () => {
    // Create the cfs-labels-editor fixture element.
    const element = document.createElement("cfs-labels-editor");
    element.innerHTML = `
      <p slot="legend">
        Custom <a href="/docs/cfs-labels">legend</a>
      </p>
    `;
    document.body.append(element);

    // Render the custom legend into the form legend slot.
    await element.updateComplete;

    // The rendered legend keeps the custom link markup.
    let renderedLegend = element.querySelector(".form-legend");
    expect(renderedLegend?.innerHTML).to.contain('href="/docs/cfs-labels"');

    // Reconnect the fixture element.
    element.remove();
    document.body.append(element);

    // Request a component update after reconnecting.
    element.requestUpdate();
    await element.updateComplete;

    // The reconnected legend keeps the custom link markup.
    renderedLegend = element.querySelector(".form-legend");
    expect(renderedLegend?.innerHTML).to.contain('href="/docs/cfs-labels"');
  });

  it("clears the cached legend when the slotted legend is removed before reconnect", async () => {
    // Create the cfs-labels-editor fixture element.
    const element = document.createElement("cfs-labels-editor");
    element.innerHTML = `
      <p slot="legend">
        Custom <a href="/docs/cfs-labels">legend</a>
      </p>
    `;
    document.body.append(element);

    // Render the custom legend into the form legend slot.
    await element.updateComplete;

    // The rendered legend keeps the custom link markup.
    let renderedLegend = element.querySelector(".form-legend");
    expect(renderedLegend?.innerHTML).to.contain('href="/docs/cfs-labels"');

    // Reconnect the fixture element.
    element.remove();
    element.innerHTML = "<div></div>";
    document.body.append(element);

    // Re-render without the slotted legend and clear the cached legend HTML.
    await element.updateComplete;
    expect(element._legendHtml).to.equal("");
  });
});
