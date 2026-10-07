import { expect } from "@open-wc/testing";

import { labelColorStyle, normalizeLabels } from "/static/js/common/labels.js";

describe("labels", () => {
  it("normalizes named labels with unique string ids", () => {
    // Build mixed label payloads.
    const labels = [
      { event_label_id: 12, name: " Backend ", color: " blue " },
      { event_label_id: 12, name: "Duplicate", color: "red" },
      { event_label_id: " ", name: "Ignored", color: "gray" },
      { event_label_id: 13, name: "  ", color: "red" },
      null,
    ];

    // Only named labels with ids remain, trimmed and deduplicated.
    expect(normalizeLabels(labels)).to.deep.equal([{ color: "blue", event_label_id: "12", name: "Backend" }]);
    expect(normalizeLabels(null)).to.deep.equal([]);
    expect(normalizeLabels("[]")).to.deep.equal([]);
  });

  it("builds the shared chip color style", () => {
    // The style derives the border and background from one color variable.
    expect(labelColorStyle("#bfdbfe")).to.equal(
      "--label-color:#bfdbfe;border-color:var(--label-color);background-color:color-mix(in srgb, var(--label-color) 30%, transparent);",
    );
  });
});
