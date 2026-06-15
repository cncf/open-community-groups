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
  searchOnEnter,
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
    // Render the DOM fixture for opening and closes the mobile filters drawer.
    document.body.innerHTML = `
      <div id="drawer-filters" class="-translate-x-full"></div>
      <div id="drawer-backdrop" class="hidden"></div>
    `;

    // Verify opens and closes the mobile filters drawer.
    openFiltersDrawer();
    expect(document.getElementById("drawer-filters")?.classList.contains("-translate-x-full")).to.equal(
      false,
    );
    expect(document.getElementById("drawer-backdrop")?.classList.contains("hidden")).to.equal(false);

    // Verify opens and closes the mobile filters drawer.
    closeFiltersDrawer();
    expect(document.getElementById("drawer-filters")?.classList.contains("-translate-x-full")).to.equal(true);
    expect(document.getElementById("drawer-backdrop")?.classList.contains("hidden")).to.equal(true);
  });

  it("cleans inputs and optionally triggers a form change", () => {
    // Render the DOM fixture for cleaning inputs and optionally triggers a form.
    document.body.innerHTML = `
      <form id="events-form"></form>
      <input id="search" value="cncf" />
    `;

    // Call clean input field.
    cleanInputField("search", "events-form");

    // Assert the saved value was updated.
    expect(document.getElementById("search")?.value).to.equal("");
    expect(htmx.triggerCalls).to.deep.equal([[document.getElementById("events-form"), "change"]]);
  });

  it("only triggers changes from search when the query is not empty", () => {
    // Render the DOM fixture for only triggers changes from search when the query.
    document.body.innerHTML = `
      <form id="events-form"></form>
      <input id="ts_query" value="" />
    `;

    // Empty search text does not trigger a change.
    triggerChangeOnForm("events-form", true);
    expect(htmx.triggerCalls).to.deep.equal([]);

    // Update the input before asserting it only triggers changes from search.
    document.getElementById("ts_query").value = "kubecon";
    triggerChangeOnForm("events-form", true);

    // Non-empty search text triggers a change.
    expect(htmx.triggerCalls).to.deep.equal([[document.getElementById("events-form"), "change"]]);
  });

  it("redirects escaped text searches when pressing enter outside a form", () => {
    // Prepare assigned URLs for redirecting to explore with special characters.
    const assignedUrls = [];
    const executeSearchOnEnter = new Function(
      "document",
      `const searchOnEnter = ${searchOnEnter.toString()}; return searchOnEnter;`,
    )({
      location: {
        set href(url) {
          assignedUrls.push(url);
        },
      },
    });

    // Press Enter in a search input without a form target.
    executeSearchOnEnter({
      key: "Enter",
      currentTarget: {
        value: "cloud & native?",
        blur() {},
      },
    });

    // Submitted search text is escaped in the explore redirect.
    expect(assignedUrls).to.deep.equal(["/explore?ts_query=cloud+%26+native%3F"]);
  });

  it("blurs the search input when enter search is delegated from document", () => {
    // Render the form target used by delegated search.
    document.body.innerHTML = `<form id="events-form"></form>`;

    // Prepare the delegated key event with the input as the original target.
    let blurred = false;
    const input = {
      blur() {
        blurred = true;
      },
      value: "conference",
    };

    // Press Enter from a document-level listener.
    searchOnEnter(
      {
        currentTarget: document,
        key: "Enter",
        target: input,
      },
      "events-form",
    );

    // The search submits and the original input is blurred.
    expect(htmx.triggerCalls).to.deep.equal([[document.getElementById("events-form"), "change"]]);
    expect(blurred).to.equal(true);
  });

  it("updates sort inputs from the selector value", () => {
    // Render the DOM fixture for updating sort inputs from the selector value.
    document.body.innerHTML = `
      <select id="sort_selector">
        <option value="date-desc" selected>Date</option>
      </select>
      <input id="sort_by" value="" />
      <input id="sort_direction" value="" />
    `;

    // Call update sort inputs from selector.
    updateSortInputsFromSelector(document.getElementById("sort_selector"), "sort_by", "sort_direction");

    // Assert the saved value was updated.
    expect(document.getElementById("sort_by")?.value).to.equal("date");
    expect(document.getElementById("sort_direction")?.value).to.equal("desc");
  });

  it("formats and updates date ranges", () => {
    // Verify formats and updates date ranges.
    expect(getFirstAndLastDayOfMonth(new Date("2025-02-15T12:00:00Z"))).to.deep.equal({
      first: "2025-02-01",
      last: "2025-02-28",
    });

    // Render the DOM fixture for formatting and updates date ranges.
    document.body.innerHTML = `
      <input name="date_from" value="" />
      <input name="date_to" value="" />
    `;

    // Call update date input.
    updateDateInput(new Date("2025-03-20T12:00:00Z"));

    // Assert the saved value was updated.
    expect(document.querySelector('input[name="date_from"]')?.value).to.equal("2025-03-01");
    expect(document.querySelector('input[name="date_to"]')?.value).to.equal("2025-03-31");

    // Prepare default range for formatting and updates date ranges.
    const defaultRange = getDefaultDateRange();
    expect(defaultRange.from).to.match(/^\d{4}-\d{2}-\d{2}$/);
    expect(defaultRange.to).to.match(/^\d{4}-\d{2}-\d{2}$/);
  });

  it("detects active filters from kinds, custom filters, dates, and text search", () => {
    // Keep references to the fixture controls under assertion.
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

    // Verify detects active filters from kinds, custom filters, dates, and text.
    expect(hasActiveFilters("events-form")).to.equal(true);

    // Render the DOM fixture for detecting active filters from kinds, custom.
    document.body.innerHTML = `
      <form id="events-form">
        <input name="date_from" value="${from}" />
        <input name="date_to" value="${to}" />
      </form>
      <input name="ts_query" value="" />
    `;

    // Verify detects active filters from kinds, custom filters, dates, and text.
    expect(hasActiveFilters("events-form")).to.equal(false);

    // Add a search query and assert the form becomes active.
    document.querySelector('input[name="ts_query"]').value = "cloud native";
    expect(hasActiveFilters("events-form")).to.equal(true);
  });

  it("clears hidden date filters and checked kinds", () => {
    // Render date filters and selected kind checkboxes.
    document.body.innerHTML = `
      <input type="hidden" name="date_from" value="2025-01-01" />
      <input type="hidden" name="date_to" value="2025-12-31" />
      <input type="checkbox" name="kind[]" checked />
      <input type="checkbox" name="kind[]" checked />
    `;

    // Call reset date filters on calendar view mode.
    resetDateFiltersOnCalendarViewMode();
    unckeckAllKinds();

    // Assert the saved value was updated.
    expect(document.querySelector('input[name="date_from"]')?.value).to.equal("");
    expect(document.querySelector('input[name="date_to"]')?.value).to.equal("");
    expect(document.querySelectorAll("input[name='kind[]']:checked")).to.have.length(0);
  });

  it("resets filters, custom components, search, and sort inputs back to defaults", async () => {
    // Keep references to the fixture controls under assertion.
    const { from, to } = getDefaultDateRange();
    const collapsible = document.createElement("collapsible-filter");
    collapsible.cleanSelected = () => {
      collapsible.setAttribute("data-cleared", "true");
    };
    collapsible.updateComplete = Promise.resolve();

    // Prepare multi select for resetting filters, custom components, search.
    const multiSelect = document.createElement("multi-select-filter");
    multiSelect.cleanSelected = () => {
      multiSelect.setAttribute("data-cleared", "true");
    };
    multiSelect.updateComplete = Promise.resolve();

    // Render the DOM fixture for resetting filters, custom components, search.
    document.body.innerHTML = `
      <div id="entity-section">
        <form id="events-form">
          <input type="checkbox" name="kind[]" checked />
          <input type="radio" name="view" value="" />
          <input type="date" name="date_from" value="2025-01-01" />
          <input type="date" name="date_to" value="2025-12-31" />
        </form>
        <input name="ts_query" value="kubecon" />
      </div>
      <input id="outside-search" name="ts_query" value="dashboard" />
      <select id="sort_selector">
        <option value="date-asc">Date</option>
        <option value="name" selected>Name</option>
      </select>
      <input id="sort_by" value="name" />
      <input id="sort_direction" value="desc" />
    `;
    document.getElementById("events-form")?.append(collapsible, multiSelect);

    // Resetting clears filters, custom components, search, and sort.
    await resetFilters("events-form");

    // Resetting restores filters, custom inputs, search, and sort.
    expect(collapsible.dataset.cleared).to.equal("true");
    expect(multiSelect.dataset.cleared).to.equal("true");
    expect(document.querySelectorAll('input[name="kind[]"]:checked')).to.have.length(0);
    expect(document.querySelector('input[name="date_from"]')?.value).to.equal(from);
    expect(document.querySelector('input[name="date_to"]')?.value).to.equal(to);
    expect(document.querySelector('input[name="ts_query"]')?.value).to.equal("");
    expect(document.getElementById("outside-search")?.value).to.equal("dashboard");
    expect(document.getElementById("sort_selector")?.value).to.equal("date-asc");
    expect(document.getElementById("sort_by")?.value).to.equal("date");
    expect(document.getElementById("sort_direction")?.value).to.equal("asc");
    expect(document.querySelector('input[type="radio"][value=""]')?.checked).to.equal(true);
    expect(htmx.triggerCalls.at(-1)).to.deep.equal([document.getElementById("events-form"), "change"]);
  });

  it("resets hidden date filters without requiring a search input", async () => {
    // Render the calendar-mode form without the external search field.
    const { first, last } = getFirstAndLastDayOfMonth();
    document.body.innerHTML = `
      <div id="entity-section">
        <form id="events-form">
          <input type="hidden" name="date_from" value="2025-01-01" />
          <input type="hidden" name="date_to" value="2025-12-31" />
        </form>
      </div>
    `;

    // Resetting should not depend on the optional text search field.
    await resetFilters("events-form");

    // Hidden calendar date fields reset to the current month range.
    expect(document.querySelector('input[name="date_from"]')?.value).to.equal(first);
    expect(document.querySelector('input[name="date_to"]')?.value).to.equal(last);
    expect(htmx.triggerCalls.at(-1)).to.deep.equal([document.getElementById("events-form"), "change"]);
  });

  it("detects active calendar filters from current-month dates and other active filters", () => {
    // Keep references to the fixture controls under assertion.
    const { first, last } = getFirstAndLastDayOfMonth();
    document.body.innerHTML = `
      <form id="events-form">
        <input name="date_from" value="${first}" />
        <input name="date_to" value="${last}" />
      </form>
      <input name="ts_query" value="" />
    `;

    // Verify detects active calendar filters from current-month dates and other.
    expect(hasActiveCalendarFilters("events-form")).to.equal(false);

    // Set the input value to cloud.
    document.querySelector('input[name="ts_query"]').value = "cloud";
    expect(hasActiveCalendarFilters("events-form")).to.equal(true);

    // Assert the behavior after the update.
    document.querySelector('input[name="ts_query"]').value = "";
    document.querySelector('input[name="date_to"]').value = "2099-12-31";
    expect(hasActiveCalendarFilters("events-form")).to.equal(true);
  });
});
