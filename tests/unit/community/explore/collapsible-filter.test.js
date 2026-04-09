import { expect } from "@open-wc/testing";

import "/static/js/community/explore/collapsible-filter.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx } from "/tests/unit/test-utils/globals.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";

describe("collapsible-filter", () => {
  let htmx;

  beforeEach(() => {
    htmx = mockHtmx();
  });

  afterEach(() => {
    htmx.restore();
    removeMountedElements("collapsible-filter");
    resetDom();
  });

  it("expands when a hidden option is selected initially", async () => {
    const element = await mountLitComponent("collapsible-filter", {
      options: [
        { value: "a", name: "A" },
        { value: "b", name: "B" },
        { value: "c", name: "C" },
      ],
      selected: ["c"],
      maxVisibleItems: 1,
    });

    expect(element.isCollapsed).to.equal(false);
    expect(element.visibleOptions).to.have.length(3);
  });

  it("toggles selections and triggers a parent form change", async () => {
    document.body.innerHTML = '<form id="filters-form"></form>';
    const form = document.getElementById("filters-form");
    const element = document.createElement("collapsible-filter");
    Object.assign(element, {
      options: [{ value: "a", name: "A" }],
      selected: [],
    });
    form.append(element);
    await element.updateComplete;

    await element._onSelect("a");

    expect(element.selected).to.deep.equal(["a"]);
    expect(htmx.triggerCalls).to.deep.equal([[form, "change"]]);
  });
});
