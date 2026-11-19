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
  restoreAppliedFilterValues,
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

  it("opens and closes the mobile filters drawer, keeping it inert while closed", () => {
    // Render the closed drawer as the server does.
    document.body.innerHTML = `
      <div id="drawer-filters" class="-translate-x-full" inert></div>
      <div id="drawer-backdrop" class="hidden"></div>
    `;
    const drawer = document.getElementById("drawer-filters");

    // Verify opening shows the drawer and makes it reachable.
    openFiltersDrawer();
    expect(drawer.classList.contains("-translate-x-full")).to.equal(false);
    expect(drawer.inert).to.equal(false);
    expect(document.getElementById("drawer-backdrop")?.classList.contains("hidden")).to.equal(false);

    // Verify closing hides the drawer and takes it out of reach again.
    closeFiltersDrawer();
    expect(drawer.classList.contains("-translate-x-full")).to.equal(true);
    expect(drawer.inert).to.equal(true);
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
    // Prepare loaded URLs for redirecting to explore with special characters.
    const loadedUrls = [];
    const executeSearchOnEnter = new Function(
      "loadPage",
      `const searchOnEnter = ${searchOnEnter.toString()}; return searchOnEnter;`,
    )((url) => {
      loadedUrls.push(url);
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
    expect(loadedUrls).to.deep.equal(["/explore?ts_query=cloud+%26+native%3F"]);
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
      <div id="entity-section">
        <form id="events-form">
          <input type="checkbox" name="kind[]" checked />
          <input name="date_from" value="${from}" />
          <input name="date_to" value="${to}" />
          <collapsible-filter name="region" selected='["emea"]'></collapsible-filter>
        </form>
        <input name="ts_query" value="" />
      </div>
    `;

    // Verify detects active filters from kinds, custom filters, dates, and text.
    expect(hasActiveFilters("events-form")).to.equal(true);

    // Render the DOM fixture for detecting active filters from kinds, custom.
    document.body.innerHTML = `
      <div id="entity-section">
        <form id="events-form">
          <input name="date_from" value="${from}" />
          <input name="date_to" value="${to}" />
        </form>
        <input name="ts_query" value="" />
      </div>
    `;

    // Verify detects active filters from kinds, custom filters, dates, and text.
    expect(hasActiveFilters("events-form")).to.equal(false);

    // Add a search query and assert the form becomes active.
    document.querySelector('input[name="ts_query"]').value = "cloud native";
    expect(hasActiveFilters("events-form")).to.equal(true);
  });

  it("ignores text searches outside the active explore section", () => {
    const { from, to } = getDefaultDateRange();
    document.body.innerHTML = `
      <div id="entity-section">
        <form id="events-form">
          <input name="date_from" value="${from}" />
          <input name="date_to" value="${to}" />
        </form>
        <input name="ts_query" value="" />
      </div>
      <input id="outside-search" name="ts_query" value="dashboard" />
    `;

    expect(hasActiveFilters("events-form")).to.equal(false);
  });

  it("clears scoped hidden date filters and checked kinds", () => {
    // Render date filters and selected kind checkboxes.
    document.body.innerHTML = `
      <form id="events-form">
        <input type="hidden" name="date_from" value="2025-01-01" />
        <input type="hidden" name="date_to" value="2025-12-31" />
      </form>
      <input id="outside-date-from" type="hidden" name="date_from" value="2026-01-01" />
      <input type="checkbox" name="kind[]" checked />
      <input type="checkbox" name="kind[]" checked />
    `;

    // Call reset date filters on calendar view mode.
    resetDateFiltersOnCalendarViewMode("events-form");
    unckeckAllKinds();

    // Assert the saved value was updated.
    expect(document.querySelector('#events-form input[name="date_from"]')?.value).to.equal("");
    expect(document.querySelector('#events-form input[name="date_to"]')?.value).to.equal("");
    expect(document.getElementById("outside-date-from")?.value).to.equal("2026-01-01");
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
      <div id="entity-section">
        <form id="events-form">
          <input name="date_from" value="${first}" />
          <input name="date_to" value="${last}" />
        </form>
        <input name="ts_query" value="" />
      </div>
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

  describe("restoreAppliedFilterValues", () => {
    it("puts each native control kind back to the value its markup declares", () => {
      // Render the applied controls as the server does.
      document.body.innerHTML = `
        <div id="root">
          <input type="checkbox" name="kind[]" value="virtual" checked />
          <input type="checkbox" name="kind[]" value="in-person" />
          <input type="radio" name="view_mode" value="list" checked />
          <input type="radio" name="view_mode" value="map" />
          <select id="declared-select">
            <option value="a">A</option>
            <option value="b" selected>B</option>
            <option value="c">C</option>
          </select>
          <select id="fallback-select">
            <option value="x">X</option>
            <option value="y">Y</option>
          </select>
          <input id="text-input" type="text" value="kubecon" />
          <input id="search-input" type="search" value="cloud" />
          <input id="date-input" type="date" value="2025-03-01" />
        </div>
      `;
      const root = document.getElementById("root");
      const [virtualKind, inPersonKind] = root.querySelectorAll('input[name="kind[]"]');
      const [listMode, mapMode] = root.querySelectorAll('input[name="view_mode"]');
      const declaredSelect = document.getElementById("declared-select");
      const fallbackSelect = document.getElementById("fallback-select");
      const textInput = document.getElementById("text-input");
      const searchInput = document.getElementById("search-input");
      const dateInput = document.getElementById("date-input");

      // Change every control as the user would before a failed request.
      virtualKind.checked = false;
      inPersonKind.checked = true;
      mapMode.checked = true;
      declaredSelect.value = "c";
      fallbackSelect.value = "y";
      textInput.value = "rust";
      searchInput.value = "";
      dateInput.value = "2025-04-01";

      restoreAppliedFilterValues(root);

      // Verify every control shows the applied value again.
      expect(virtualKind.checked).to.equal(true);
      expect(inPersonKind.checked).to.equal(false);
      expect(listMode.checked).to.equal(true);
      expect(mapMode.checked).to.equal(false);
      expect(declaredSelect.value).to.equal("b");
      expect(fallbackSelect.value).to.equal("x");
      expect(textInput.value).to.equal("kubecon");
      expect(searchInput.value).to.equal("cloud");
      expect(dateInput.value).to.equal("2025-03-01");
    });

    it("restores custom filters from their selected attribute", () => {
      // Render one filter with a restore method and one without it.
      document.body.innerHTML = `
        <div id="root">
          <collapsible-filter selected='["cncf"]'></collapsible-filter>
          <multi-select-filter selected='["group-a","group-b"]'></multi-select-filter>
          <multi-select-filter id="empty-filter"></multi-select-filter>
        </div>
      `;
      const collapsible = document.querySelector("collapsible-filter");
      const [multiSelect, emptyFilter] = document.querySelectorAll("multi-select-filter");
      const restoreCalls = [];
      collapsible.restoreSelected = (values) => restoreCalls.push(values);
      multiSelect.selected = ["group-c"];
      emptyFilter.selected = ["group-d"];

      restoreAppliedFilterValues(document.getElementById("root"));

      // Verify each filter gets the selection the server rendered.
      expect(restoreCalls).to.deep.equal([["cncf"]]);
      expect(multiSelect.selected).to.deep.equal(["group-a", "group-b"]);
      expect(emptyFilter.selected).to.deep.equal([]);
    });

    it("leaves hidden inputs alone except the sort inputs, which follow the restored selector", () => {
      // Render the sort controls and a hidden calendar date.
      document.body.innerHTML = `
        <div id="root">
          <select id="sort_selector">
            <option value="date-asc">Date (asc)</option>
            <option value="date-desc" selected>Date (desc)</option>
          </select>
          <input type="hidden" id="sort_by" name="sort_by" value="date" />
          <input type="hidden" id="sort_direction" name="sort_direction" value="desc" />
          <input type="hidden" name="date_from" value="2025-03-01" />
        </div>
      `;
      const selector = document.getElementById("sort_selector");
      const dateFrom = document.querySelector('input[name="date_from"]');

      // Change the sort and the hidden date as a failed request would leave them.
      selector.value = "date-asc";
      updateSortInputsFromSelector(selector, "sort_by", "sort_direction");
      dateFrom.value = "2025-04-01";

      restoreAppliedFilterValues(document.getElementById("root"));

      // Verify the sort inputs follow the selector and the hidden date stays.
      expect(selector.value).to.equal("date-desc");
      expect(document.getElementById("sort_by")?.value).to.equal("date");
      expect(document.getElementById("sort_direction")?.value).to.equal("desc");
      expect(dateFrom.value).to.equal("2025-04-01");
    });

    it("skips native inputs inside custom filters and the kept subtree", () => {
      // Render a custom filter with its own input and a kept sheet form.
      document.body.innerHTML = `
        <div id="root">
          <collapsible-filter selected="[]">
            <input type="checkbox" name="region[]" value="europe" />
          </collapsible-filter>
          <div id="sheet">
            <input type="checkbox" name="kind[]" value="virtual" />
            <multi-select-filter selected='["group-a"]'></multi-select-filter>
          </div>
        </div>
      `;
      const collapsible = document.querySelector("collapsible-filter");
      const filterInput = collapsible.querySelector("input");
      const sheetKind = document.querySelector('#sheet input[name="kind[]"]');
      const sheetFilter = document.querySelector("#sheet multi-select-filter");
      collapsible.restoreSelected = () => {};
      filterInput.checked = true;
      sheetKind.checked = true;
      sheetFilter.selected = ["group-b"];

      restoreAppliedFilterValues(document.getElementById("root"), {
        keep: document.getElementById("sheet"),
      });

      // Verify the filter input and the kept subtree keep their state.
      expect(filterInput.checked).to.equal(true);
      expect(sheetKind.checked).to.equal(true);
      expect(sheetFilter.selected).to.deep.equal(["group-b"]);
    });

    it("dispatches no change, input or filter-change event", () => {
      // Render changed controls under a listening root.
      document.body.innerHTML = `
        <form id="root">
          <input type="checkbox" name="kind[]" value="virtual" checked />
          <input type="text" name="ts_query" value="kubecon" />
          <select name="sort"><option value="a" selected>A</option><option value="b">B</option></select>
          <multi-select-filter selected='["group-a"]'></multi-select-filter>
        </form>
      `;
      const root = document.getElementById("root");
      root.querySelector('input[type="checkbox"]').checked = false;
      root.querySelector('input[type="text"]').value = "rust";
      root.querySelector("select").value = "b";
      const events = [];
      ["change", "input", "filter-change"].forEach((type) => {
        root.addEventListener(type, () => events.push(type), true);
      });

      restoreAppliedFilterValues(root);

      // Verify the restore stays silent, so no request leaves.
      expect(events).to.deep.equal([]);
      expect(htmx.triggerCalls).to.have.length(0);
    });
  });
});
