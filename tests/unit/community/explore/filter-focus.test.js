import { expect } from "@open-wc/testing";

import "/static/js/community/explore/collapsible-filter.js";
import "/static/js/community/explore/multi-select-filter.js";
import {
  captureFilterFocus,
  getFilterFocusKey,
  restoreFilterFocus,
} from "/static/js/community/explore/filter-focus.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

const REGION_OPTIONS = JSON.stringify([
  { value: "emea", name: "EMEA" },
  { value: "latam", name: "LATAM" },
]);

/**
 * Renders the sidebar filters form, or replaces it as a section swap does.
 * @param {string} [content] Form content markup.
 * @returns {HTMLFormElement} Rendered form.
 */
const renderForm = (content = "") => {
  document.body.innerHTML = `
    <button type="button" id="outside">Outside</button>
    <form id="events-form" class="filters-form">${content}</form>
  `;
  return document.getElementById("events-form");
};

/**
 * Renders a Region collapsible filter with the given options, as the server does.
 * @param {string} [options] Options JSON.
 * @returns {string} Filter markup.
 */
const regionFilter = (options = REGION_OPTIONS) =>
  `<collapsible-filter title="Region" name="region" options='${options}' selected="[]"></collapsible-filter>`;

describe("filter focus", () => {
  afterEach(() => {
    resetDom();
  });

  it("keys checkboxes by name and value and other inputs by name", () => {
    // Render one control of every kind.
    renderForm(`
      <input type="checkbox" name="kind[]" value="virtual" />
      <input type="radio" name="view_mode" value="list" />
      <input type="date" name="date_from" />
      <button type="button" data-focus-key="any" name="ignored">Any</button>
      <button type="button">Unnamed</button>
    `);
    const [checkbox, radio, date, any, unnamed] = document.querySelectorAll("input, button:not(#outside)");

    // Verify each control gets its stable key.
    expect(getFilterFocusKey(checkbox)).to.equal("kind[]=virtual");
    expect(getFilterFocusKey(radio)).to.equal("view_mode=list");
    expect(getFilterFocusKey(date)).to.equal("date_from");
    expect(getFilterFocusKey(any)).to.equal("any");
    expect(getFilterFocusKey(unnamed)).to.equal(null);
    expect(getFilterFocusKey(null)).to.equal(null);
  });

  it("restores a re-rendered checkbox in the same form", async () => {
    // Focus a Type checkbox and capture it before the swap.
    const checkboxes = `
      <input type="checkbox" name="kind[]" value="in-person" />
      <input type="checkbox" name="kind[]" value="virtual" />
    `;
    const form = renderForm(checkboxes);
    form.querySelector('[value="virtual"]').focus();
    const snapshot = captureFilterFocus(form);
    expect(snapshot).to.deep.equal({ filterName: null, formId: "events-form", key: "kind[]=virtual" });

    // Replace the form, which drops focus to the body.
    renderForm(checkboxes);
    expect(document.activeElement).to.equal(document.body);

    // Verify the new checkbox with the same key takes focus.
    await restoreFilterFocus(snapshot);
    expect(document.activeElement).to.equal(document.querySelector('[value="virtual"]'));
  });

  it("waits for Lit filters to render before restoring a data-focus-key control", async () => {
    // Focus the Any button of a rendered Region filter and capture it.
    const form = renderForm(regionFilter());
    const filter = form.querySelector("collapsible-filter");
    await filter.updateComplete;
    filter.querySelector('[data-focus-key="any"]').focus();
    const snapshot = captureFilterFocus(form);
    expect(snapshot).to.deep.equal({ filterName: "region", formId: "events-form", key: "any" });

    // Replace the form and restore before the new filter has rendered.
    renderForm(regionFilter());
    const restored = restoreFilterFocus(snapshot);
    expect(document.querySelector('[data-focus-key="any"]')).to.equal(null);
    await restored;

    // Verify the Any button of the new filter took focus.
    const anyButton = document.querySelector('[data-focus-key="any"]');
    expect(anyButton).to.not.equal(null);
    expect(document.activeElement).to.equal(anyButton);
  });

  it("restores a multi-select filter search without opening its options", async () => {
    // Focus the Group search of a rendered multi-select filter and capture it.
    const groupFilter = `<multi-select-filter title="Group" name="group" options='${REGION_OPTIONS}' selected="[]"></multi-select-filter>`;
    const form = renderForm(groupFilter);
    await form.querySelector("multi-select-filter").updateComplete;
    form.querySelector('[data-focus-key="search"]').focus();
    const snapshot = captureFilterFocus(form);

    // Replace the form and restore focus.
    renderForm(groupFilter);
    await restoreFilterFocus(snapshot);

    // Verify the new search input has focus and its options stay closed.
    const input = document.querySelector('[data-focus-key="search"]');
    expect(document.activeElement).to.equal(input);
    expect(input.getAttribute("aria-expanded")).to.equal("false");
  });

  it("falls back to the first control of the same filter when the focused one is gone", async () => {
    // Focus the LATAM option and capture it.
    const form = renderForm(`<input type="checkbox" name="kind[]" value="virtual" />${regionFilter()}`);
    const filter = form.querySelector("collapsible-filter");
    await filter.updateComplete;
    filter.querySelector('input[value="latam"]').focus();
    const snapshot = captureFilterFocus(form);
    expect(snapshot.key).to.equal("region[]=latam");

    // Re-render the filter without that option.
    renderForm(
      `<input type="checkbox" name="kind[]" value="virtual" />${regionFilter(
        JSON.stringify([{ value: "emea", name: "EMEA" }]),
      )}`,
    );
    await restoreFilterFocus(snapshot);

    // Verify focus lands on the first control of the Region filter, not outside it.
    const firstControl = document.querySelector("collapsible-filter button");
    expect(firstControl.dataset.focusKey).to.equal("any");
    expect(document.activeElement).to.equal(firstControl);
  });

  it("leaves focus alone when something else already has it", async () => {
    // Capture a focused checkbox.
    const checkbox = '<input type="checkbox" name="kind[]" value="virtual" />';
    const form = renderForm(checkbox);
    form.querySelector("input").focus();
    const snapshot = captureFilterFocus(form);

    // Replace the form and move focus elsewhere before the restore.
    renderForm(checkbox);
    const outside = document.getElementById("outside");
    outside.focus();
    await restoreFilterFocus(snapshot);

    // Verify focus stays where it was moved.
    expect(document.activeElement).to.equal(outside);
  });
});
