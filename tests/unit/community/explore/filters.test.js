import { expect } from "@open-wc/testing";

import {
  cleanInputField,
  closeFiltersDrawer,
  getDefaultDateRange,
  getFirstAndLastDayOfMonth,
  hasActiveCalendarFilters,
  hasActiveFilters,
  openFiltersDrawer,
  resetFilters,
  resetDateFiltersOnCalendarViewMode,
  triggerChangeOnForm,
  unckeckAllKinds,
  updateDateInput,
  updateSortInputsFromSelector,
} from "/static/js/community/explore/filters.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx } from "/tests/unit/test-utils/globals.js";

describe("explore filters", () => {
  let htmx;

  beforeEach(() => {
    resetDom();
    htmx = mockHtmx();
  });

  afterEach(() => {
    resetDom();
    htmx.restore();
  });

  it("opens and closes the mobile filters drawer", () => {
    document.body.innerHTML = `
      <div id="drawer-filters" class="-translate-x-full"></div>
      <div id="drawer-backdrop" class="hidden"></div>
    `;

    openFiltersDrawer();
    expect(document.getElementById("drawer-filters")?.classList.contains("-translate-x-full")).to.equal(false);
    expect(document.getElementById("drawer-backdrop")?.classList.contains("hidden")).to.equal(false);

    closeFiltersDrawer();
    expect(document.getElementById("drawer-filters")?.classList.contains("-translate-x-full")).to.equal(true);
    expect(document.getElementById("drawer-backdrop")?.classList.contains("hidden")).to.equal(true);
  });

  it("cleans inputs and optionally triggers a form change", () => {
    document.body.innerHTML = `
      <form id="events-form"></form>
      <input id="search" value="cncf" />
    `;

    cleanInputField("search", "events-form");

    expect(document.getElementById("search")?.value).to.equal("");
    expect(htmx.triggerCalls).to.deep.equal([[document.getElementById("events-form"), "change"]]);
  });

  it("only triggers changes from search when the query is not empty", () => {
    document.body.innerHTML = `
      <form id="events-form"></form>
      <input id="ts_query" value="" />
    `;

    triggerChangeOnForm("events-form", true);
    expect(htmx.triggerCalls).to.deep.equal([]);

    document.getElementById("ts_query").value = "kubecon";
    triggerChangeOnForm("events-form", true);

    expect(htmx.triggerCalls).to.deep.equal([[document.getElementById("events-form"), "change"]]);
  });

  it("updates sort inputs from the selector value", () => {
    document.body.innerHTML = `
      <select id="sort_selector">
        <option value="date-desc" selected>Date</option>
      </select>
      <input id="sort_by" value="" />
      <input id="sort_direction" value="" />
    `;

    updateSortInputsFromSelector(
      document.getElementById("sort_selector"),
      "sort_by",
      "sort_direction",
    );

    expect(document.getElementById("sort_by")?.value).to.equal("date");
    expect(document.getElementById("sort_direction")?.value).to.equal("desc");
  });

  it("formats and updates date ranges", () => {
    expect(getFirstAndLastDayOfMonth(new Date("2025-02-15T12:00:00Z"))).to.deep.equal({
      first: "2025-02-01",
      last: "2025-02-28",
    });

    document.body.innerHTML = `
      <input name="date_from" value="" />
      <input name="date_to" value="" />
    `;

    updateDateInput(new Date("2025-03-20T12:00:00Z"));

    expect(document.querySelector('input[name="date_from"]')?.value).to.equal("2025-03-01");
    expect(document.querySelector('input[name="date_to"]')?.value).to.equal("2025-03-31");

    const defaultRange = getDefaultDateRange();
    expect(defaultRange.from).to.match(/^\d{4}-\d{2}-\d{2}$/);
    expect(defaultRange.to).to.match(/^\d{4}-\d{2}-\d{2}$/);
  });

  it("detects active filters from kinds, custom filters, dates, and text search", () => {
    const { from, to } = getDefaultDateRange();
    document.body.innerHTML = `
      <form id="events-form">
        <input type="checkbox" name="kind[]" checked />
        <input name="date_from" value="${from}" />
        <input name="date_to" value="${to}" />
        <collapsible-filter name="region" selected='["emea"]'></collapsible-filter>
      </form>
      <input name="ts_query" value="" />
    `;

    expect(hasActiveFilters("events-form")).to.equal(true);

    document.body.innerHTML = `
      <form id="events-form">
        <input name="date_from" value="${from}" />
        <input name="date_to" value="${to}" />
      </form>
      <input name="ts_query" value="" />
    `;

    expect(hasActiveFilters("events-form")).to.equal(false);

    document.querySelector('input[name="ts_query"]').value = "cloud native";
    expect(hasActiveFilters("events-form")).to.equal(true);
  });

  it("clears hidden date filters and checked kinds", () => {
    document.body.innerHTML = `
      <input type="hidden" name="date_from" value="2025-01-01" />
      <input type="hidden" name="date_to" value="2025-12-31" />
      <input type="checkbox" name="kind[]" checked />
      <input type="checkbox" name="kind[]" checked />
    `;

    resetDateFiltersOnCalendarViewMode();
    unckeckAllKinds();

    expect(document.querySelector('input[name="date_from"]')?.value).to.equal("");
    expect(document.querySelector('input[name="date_to"]')?.value).to.equal("");
    expect(document.querySelectorAll("input[name='kind[]']:checked")).to.have.length(0);
  });

  it("resets filters, custom components, search, and sort inputs back to defaults", async () => {
    const { from, to } = getDefaultDateRange();
    const collapsible = document.createElement("collapsible-filter");
    collapsible.cleanSelected = () => {
      collapsible.setAttribute("data-cleared", "true");
    };
    collapsible.updateComplete = Promise.resolve();

    const multiSelect = document.createElement("multi-select-filter");
    multiSelect.cleanSelected = () => {
      multiSelect.setAttribute("data-cleared", "true");
    };
    multiSelect.updateComplete = Promise.resolve();

    document.body.innerHTML = `
      <form id="events-form">
        <input type="checkbox" name="kind[]" checked />
        <input type="radio" name="view" value="" />
        <input type="date" name="date_from" value="2025-01-01" />
        <input type="date" name="date_to" value="2025-12-31" />
      </form>
      <input name="ts_query" value="kubecon" />
      <select id="sort_selector">
        <option value="date-asc">Date</option>
        <option value="name" selected>Name</option>
      </select>
      <input id="sort_by" value="name" />
      <input id="sort_direction" value="desc" />
    `;
    document.getElementById("events-form")?.append(collapsible, multiSelect);

    await resetFilters("events-form");

    expect(collapsible.dataset.cleared).to.equal("true");
    expect(multiSelect.dataset.cleared).to.equal("true");
    expect(document.querySelectorAll('input[name="kind[]"]:checked')).to.have.length(0);
    expect(document.querySelector('input[name="date_from"]')?.value).to.equal(from);
    expect(document.querySelector('input[name="date_to"]')?.value).to.equal(to);
    expect(document.querySelector('input[name="ts_query"]')?.value).to.equal("");
    expect(document.getElementById("sort_selector")?.value).to.equal("date-asc");
    expect(document.getElementById("sort_by")?.value).to.equal("date");
    expect(document.getElementById("sort_direction")?.value).to.equal("asc");
    expect(document.querySelector('input[type="radio"][value=""]')?.checked).to.equal(true);
    expect(htmx.triggerCalls.at(-1)).to.deep.equal([document.getElementById("events-form"), "change"]);
  });

  it("detects active calendar filters from current-month dates and other active filters", () => {
    const { first, last } = getFirstAndLastDayOfMonth();
    document.body.innerHTML = `
      <form id="events-form">
        <input name="date_from" value="${first}" />
        <input name="date_to" value="${last}" />
      </form>
      <input name="ts_query" value="" />
    `;

    expect(hasActiveCalendarFilters("events-form")).to.equal(false);

    document.querySelector('input[name="ts_query"]').value = "cloud";
    expect(hasActiveCalendarFilters("events-form")).to.equal(true);

    document.querySelector('input[name="ts_query"]').value = "";
    document.querySelector('input[name="date_to"]').value = "2099-12-31";
    expect(hasActiveCalendarFilters("events-form")).to.equal(true);
  });
});
