import { expect } from "@open-wc/testing";

import {
  getHtmxTriggerNames,
  hasHtmxTrigger,
} from "/static/js/common/htmx-triggers.js";

describe("htmx triggers", () => {
  it("parses comma-separated htmx trigger names", () => {
    // Build an HTMX response with the server's comma-separated trigger format.
    const xhr = {
      getResponseHeader: (name) =>
        name === "HX-Trigger" ? " refresh-body, refresh-dashboard , " : null,
    };

    // Assert trigger names are trimmed and blank entries are ignored.
    expect(getHtmxTriggerNames(xhr)).to.deep.equal([
      "refresh-body",
      "refresh-dashboard",
    ]);
    expect(hasHtmxTrigger(xhr, "refresh-body")).to.equal(true);
    expect(hasHtmxTrigger(xhr, "missing-trigger")).to.equal(false);
  });

  it("handles missing htmx trigger headers", () => {
    // Build response fixtures without a readable trigger header.
    const xhr = {
      getResponseHeader: () => null,
    };

    // Assert missing and invalid responses are treated as trigger-free.
    expect(getHtmxTriggerNames(xhr)).to.deep.equal([]);
    expect(getHtmxTriggerNames(null)).to.deep.equal([]);
    expect(hasHtmxTrigger({ status: 204 }, "refresh-body")).to.equal(false);
  });
});
