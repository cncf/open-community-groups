import { expect } from "@open-wc/testing";

import "/static/js/community/explore/multi-select-filter.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx } from "/tests/unit/test-utils/globals.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";

describe("multi-select-filter", () => {
  let htmx;

  beforeEach(() => {
    htmx = mockHtmx();
  });

  afterEach(() => {
    htmx.restore();
    removeMountedElements("multi-select-filter");
    resetDom();
  });

  it("filters options from the current query", async () => {
    const element = await mountLitComponent("multi-select-filter", {
      options: [
        { value: "cloud", name: "Cloud" },
        { value: "security", name: "Security" },
      ],
    });

    element._handleSearchInput({
      target: { value: "sec" },
    });

    expect(element._filteredOptions).to.deep.equal([{ value: "security", name: "Security" }]);
  });

  it("selects and removes options while triggering form changes", async () => {
    document.body.innerHTML = '<form id="filters-form"></form>';
    const form = document.getElementById("filters-form");
    const element = document.createElement("multi-select-filter");
    Object.assign(element, {
      options: [{ value: "cloud", name: "Cloud" }],
      selected: [],
    });
    form.append(element);
    await element.updateComplete;

    await element._toggleOption("cloud");
    await element._removeOption("cloud", { stopPropagation() {} });

    expect(element.selected).to.deep.equal([]);
    expect(htmx.triggerCalls).to.deep.equal([
      [form, "change"],
      [form, "change"],
    ]);
  });
});
