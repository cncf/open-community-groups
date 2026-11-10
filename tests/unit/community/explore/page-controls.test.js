import { expect, nextFrame, waitUntil } from "@open-wc/testing";

import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx, mockSwal } from "/tests/unit/test-utils/globals.js";

/**
 * Replaces matchMedia with a phone query whose state tests can change.
 * @returns {{setMatches: (next: boolean) => void}} Query controls.
 */
const mockPhoneQuery = () => {
  const listeners = new Set();
  const query = {
    addEventListener: (type, listener) => {
      if (type === "change") {
        listeners.add(listener);
      }
    },
    matches: false,
  };

  window.matchMedia = (text) => (text === PHONE_MEDIA_QUERY ? query : { matches: false });

  return {
    setMatches: (next) => {
      query.matches = next;
      listeners.forEach((listener) => listener({ matches: next }));
    },
  };
};

/**
 * Renders one button of the Events and Groups switch, which only the unpressed side can request.
 * @param {string} label Button text.
 * @param {string} entity Selected entity label.
 * @returns {string} Button markup.
 */
const renderSwitchButton = (label, entity) => {
  const pressed = label === entity;
  const request = pressed ? "" : `hx-get="/explore/${label.toLowerCase()}-section"`;
  return `<button type="button" aria-pressed="${pressed}" ${request}>${label}</button>`;
};

// Unit tests load no stylesheet, so the Active filters row and its items get fixed sizes: its
// 300px holds the 70px toggle and the 120px and 60px chips, but not the 140px one with them.
const CHIP_STYLE = "box-sizing: border-box; flex: none; padding: 0";
const ROW_STYLE = "display: flex; column-gap: 8px; padding: 0 12px; width: 300px";

/**
 * Renders the Explore shell the page controls act on.
 * @param {string} [entity="Events"] Selected entity label.
 */
const renderExplore = (entity = "Events") => {
  document.body.innerHTML = `
    <div id="entity-section">
      <div id="drawer-filters" class="-translate-x-full" tabindex="-1" aria-labelledby="drawer-label">
        <button id="close-filters" type="button"><div class="icon-close"></div></button>
        <form id="events-form-mobile" class="filters-form" hx-get="/explore/events-section">
          <input type="checkbox" name="kind[]" value="virtual" />
          <collapsible-filter name="community"><input type="checkbox" name="community[]" value="one" /></collapsible-filter>
          <div data-dependent>Old group filter</div>
        </form>
        <button class="reset-filters" type="button">Reset</button>
        <button type="button" data-apply-filters>Show results</button>
      </div>
      <div id="drawer-backdrop" class="hidden"></div>
      <div id="explore-filters">
        <form id="events-form" class="filters-form">
          <input type="checkbox" name="kind[]" value="virtual" checked />
          <input type="checkbox" name="kind[]" value="hybrid" checked />
          <multi-select-filter name="group">
            <input type="hidden" name="group[]" value="alpha" />
            <button type="button" aria-label="Remove Alpha group"></button>
          </multi-select-filter>
        </form>
      </div>
      <button id="open-filters" type="button"></button>
      <div role="group" aria-label="Show">
        ${renderSwitchButton("Events", entity)}
        ${renderSwitchButton("Groups", entity)}
      </div>
      <input id="ts_query" name="ts_query" />
      <div data-applied-filters>
        <button class="reset-filters" type="button">Reset</button>
        <div style="${ROW_STYLE}">
          <div id="applied-filters" role="group" aria-label="Applied filters" style="display: flex; flex-wrap: wrap; column-gap: 8px; min-width: 0">
            <button type="button" data-applied-filter="kind" data-applied-filter-value="virtual" style="${CHIP_STYLE}; width: 120px">Virtual</button>
            <button type="button" data-applied-filter="kind" data-applied-filter-value="hybrid" style="${CHIP_STYLE}; width: 140px">Hybrid</button>
            <button type="button" data-applied-filter="group" data-applied-filter-value="alpha" style="${CHIP_STYLE}; width: 60px">Alpha group</button>
          </div>
          <button type="button" data-applied-filters-toggle aria-controls="applied-filters" aria-expanded="false" hidden style="${CHIP_STYLE}; width: 70px">
            <span data-applied-filters-toggle-label></span>
          </button>
        </div>
      </div>
      <div id="results">1 - 10 of 12 results</div>
      <div id="cards-list"></div>
    </div>
    <div id="explore-filter-status" role="status"></div>
  `;
};

/**
 * Sends a cancelable HTMX confirm event from an element.
 * @param {Element} element Element issuing the request.
 * @returns {boolean} True when the request may go ahead.
 */
const confirmRequest = (element) =>
  element.dispatchEvent(new CustomEvent("htmx:confirm", { bubbles: true, cancelable: true }));

/**
 * Dispatches an HTMX lifecycle event from an element.
 * @param {Element} element Event target.
 * @param {string} type Event type.
 */
const fireHtmx = (element, type) => element.dispatchEvent(new CustomEvent(type, { bubbles: true }));

/** Replaces the section's markup, as a successful swap does. */
const swapSection = () => {
  const section = document.getElementById("entity-section");
  fireHtmx(document.body, "htmx:beforeHistorySave");
  renderExplore();
  fireHtmx(document.getElementById("entity-section") ?? section, "htmx:afterSettle");
};

const getDrawer = () => document.getElementById("drawer-filters");
const getForm = () => document.getElementById("events-form-mobile");

/**
 * Finds a button of the Events and Groups switch.
 * @param {string} label Button text.
 * @returns {HTMLButtonElement} Switch button.
 */
const getSwitchButton = (label) =>
  [...document.querySelectorAll('[aria-label="Show"] button')].find((button) => button.textContent === label);

/**
 * Lists the Active filters chips the card shows.
 * @returns {string[]} Chip texts.
 */
const getShownChips = () =>
  [...document.querySelectorAll("[data-applied-filter]")]
    .filter((chip) => !chip.hidden)
    .map((chip) => chip.textContent);

const getAppliedFiltersToggle = () => document.querySelector("[data-applied-filters-toggle]");
const isSheetOpen = () => !getDrawer().classList.contains("-translate-x-full");
const openSheet = () => document.getElementById("open-filters").click();

/** Changes the sheet's Community filter and waits for the form refresh to land. */
const refreshCommunity = async () => {
  const community = getForm().querySelector("collapsible-filter");
  community.dispatchEvent(new CustomEvent("filter-change", { bubbles: true, composed: true }));
  await waitUntil(() => !getForm().hasAttribute("aria-busy"));
};

/**
 * Stubs the section a form refresh reads.
 * @param {string} filter Text of the refreshed dependent filter.
 */
const stubRefresh = (filter) => {
  globalThis.fetch = async () =>
    new Response(`
      <form id="events-form-mobile">
        <collapsible-filter name="community"></collapsible-filter>
        <div data-dependent>${filter}</div>
      </form>
    `);
};

/** Reads the text of the dependent filter in the sheet's form. */
const getDependentFilter = () => getForm().querySelector("[data-dependent]").textContent;

describe("explore page controls", () => {
  const originalFetch = globalThis.fetch;
  const originalMatchMedia = window.matchMedia;
  let getPhoneListUrl;
  let htmx;
  let phoneQuery;
  let swal;

  before(async () => {
    phoneQuery = mockPhoneQuery();
    ({ getPhoneListUrl } = await import("/static/js/community/explore/page-controls.js"));
  });

  after(() => {
    window.matchMedia = originalMatchMedia;
  });

  beforeEach(() => {
    resetDom();
    renderExplore();
    htmx = mockHtmx();
    swal = mockSwal();
  });

  afterEach(() => {
    // Leave no sheet held open for the next test.
    fireHtmx(document.body, "htmx:beforeHistorySave");
    phoneQuery.setMatches(false);
    delete document.body.dataset.modalOpenCount;
    document.body.style.overflow = "";
    globalThis.fetch = originalFetch;
    htmx.restore();
    swal.restore();
    resetDom();
  });

  describe("off phones", () => {
    it("keeps the drawer and its requests as they are", () => {
      // Open the drawer through the same button phones use.
      openSheet();

      // Verify the drawer opens with none of the sheet's state.
      expect(isSheetOpen()).to.equal(true);
      expect(getDrawer().hasAttribute("role")).to.equal(false);
      expect(getDrawer().getAttribute("aria-labelledby")).to.equal("drawer-label");
      expect(document.body.style.overflow).to.equal("");

      // Verify a change still goes straight to the server.
      expect(confirmRequest(getForm())).to.equal(true);

      // Verify closing needs no apply.
      document.getElementById("close-filters").click();
      expect(isSheetOpen()).to.equal(false);
      expect(htmx.triggerCalls).to.have.length(0);
    });

    it("leaves focus alone after a switch press", () => {
      // The switch is hidden here, but a scripted press must leave nothing for a later phone swap.
      getSwitchButton("Groups").click();
      phoneQuery.setMatches(true);
      renderExplore("Groups");
      fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");
      expect(document.activeElement.tagName).to.equal("BODY");
    });

    it("holds no listener for a switch press and reports nothing", () => {
      // Record what the document binds during a press.
      const added = [];
      const { addEventListener } = document;
      document.addEventListener = function add(type, ...rest) {
        added.push(type);
        return addEventListener.call(this, type, ...rest);
      };

      // Press the switch and fail its request.
      const groups = getSwitchButton("Groups");
      groups.click();
      fireHtmx(groups, "htmx:responseError");
      document.addEventListener = addEventListener;

      // Verify nothing was bound, and nothing was reported.
      expect(added).to.deep.equal([]);
      expect(swal.calls).to.have.length(0);
    });

    it("writes no phone attribute and ignores paging swaps", () => {
      // Count scrolls on the swap target.
      const cards = document.getElementById("cards-list");
      let scrolls = 0;
      cards.scrollIntoView = () => {
        scrolls += 1;
      };

      // Fire the swap events phones react to.
      fireHtmx(cards, "htmx:afterSettle");
      fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");

      // Verify nothing was written or scrolled.
      expect(scrolls).to.equal(0);
      expect(document.querySelector("[hx-sync]")).to.equal(null);
      expect(document.getElementById("ts_query").hasAttribute("enterkeyhint")).to.equal(false);
    });
  });

  describe("on phones", () => {
    beforeEach(() => {
      phoneQuery.setMatches(true);
    });

    it("syncs both forms and the search key, and restores them after a swap", () => {
      // Verify the writes from the phone branch.
      const sync = "closest #entity-section:replace";
      expect(getForm().getAttribute("hx-sync")).to.equal(sync);
      expect(document.getElementById("events-form").getAttribute("hx-sync")).to.equal(sync);
      expect(document.getElementById("ts_query").getAttribute("enterkeyhint")).to.equal("search");

      // Verify a section swap brings them back.
      renderExplore();
      expect(getForm().hasAttribute("hx-sync")).to.equal(false);
      fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");
      expect(getForm().getAttribute("hx-sync")).to.equal(sync);
      expect(document.getElementById("ts_query").getAttribute("enterkeyhint")).to.equal("search");
    });

    it("opens as a modal sheet and closes back to the opener", () => {
      // Open the sheet from its trigger.
      document.getElementById("open-filters").focus();
      openSheet();

      // Verify the dialog semantics, the lock and the focus entry.
      const drawer = getDrawer();
      const closeButton = document.getElementById("close-filters");
      expect(drawer.getAttribute("role")).to.equal("dialog");
      expect(drawer.getAttribute("aria-modal")).to.equal("true");
      expect(drawer.getAttribute("aria-label")).to.equal("Filters");
      expect(drawer.hasAttribute("aria-labelledby")).to.equal(false);
      expect(closeButton.getAttribute("aria-label")).to.equal("Close filters");
      expect(document.body.style.overflow).to.equal("hidden");
      expect(document.activeElement).to.equal(closeButton);

      // Close with nothing pending.
      closeButton.click();

      // Verify the tablet tree returns and no request went out.
      expect(isSheetOpen()).to.equal(false);
      expect(drawer.hasAttribute("role")).to.equal(false);
      expect(drawer.hasAttribute("aria-modal")).to.equal(false);
      expect(drawer.hasAttribute("aria-label")).to.equal(false);
      expect(drawer.getAttribute("aria-labelledby")).to.equal("drawer-label");
      expect(closeButton.hasAttribute("aria-label")).to.equal(false);
      expect(document.body.style.overflow).to.equal("");
      expect(document.activeElement).to.equal(document.getElementById("open-filters"));
      expect(htmx.triggerCalls).to.have.length(0);
    });

    it("holds sheet requests back and applies them once on Show results", () => {
      // Change two filters inside the sheet.
      openSheet();
      expect(confirmRequest(getForm())).to.equal(false);
      expect(confirmRequest(getForm())).to.equal(false);

      // Verify requests from outside the sheet stay live.
      expect(confirmRequest(document.getElementById("events-form"))).to.equal(true);

      // Apply the pending changes.
      const apply = document.querySelector("[data-apply-filters]");
      apply.click();

      // Verify one trigger went out, past the guard, while the sheet waits for the swap.
      expect(htmx.triggerCalls.map(([form]) => form)).to.deep.equal([getForm()]);
      expect(confirmRequest(getForm())).to.equal(true);
      expect(isSheetOpen()).to.equal(true);
      expect(apply.disabled).to.equal(true);

      // Verify a second tap sends nothing more.
      document.getElementById("close-filters").click();
      expect(htmx.triggerCalls).to.have.length(1);

      // Verify the swap releases the sheet and focus returns to the new button.
      swapSection();
      expect(document.body.style.overflow).to.equal("");
      expect(getDrawer().hasAttribute("role")).to.equal(false);
      expect(document.activeElement).to.equal(document.getElementById("open-filters"));
    });

    for (const [name, close] of [
      ["close button", () => document.getElementById("close-filters").click()],
      ["scrim", () => document.getElementById("drawer-backdrop").click()],
      [
        "Escape",
        () => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", cancelable: true })),
      ],
    ]) {
      it(`applies pending changes on the ${name}`, () => {
        // Leave a pending change in the sheet.
        openSheet();
        confirmRequest(getForm());

        // Close it.
        close();

        // Verify the choices were applied.
        expect(htmx.triggerCalls.map(([form]) => form)).to.deep.equal([getForm()]);
      });
    }

    it("leaves an Escape a nested control already handled", () => {
      // Open the sheet and press Escape as a combobox would handle it.
      openSheet();
      const event = new KeyboardEvent("keydown", { key: "Escape", cancelable: true });
      event.preventDefault();
      document.dispatchEvent(event);

      // Verify the sheet stays.
      expect(isSheetOpen()).to.equal(true);
    });

    it("keeps Reset outside the guard", () => {
      // Open the sheet and leave a pending change.
      openSheet();
      confirmRequest(getForm());

      // Verify the desktop form Reset drives is not held back.
      document.querySelector(".reset-filters").click();
      expect(confirmRequest(document.getElementById("events-form"))).to.equal(true);
    });

    it("reports a failed apply and keeps the choices on screen", () => {
      // Apply a pending change and fail its request.
      openSheet();
      confirmRequest(getForm());
      document.querySelector("[data-apply-filters]").click();
      fireHtmx(getForm(), "htmx:responseError");

      // Verify the alert, the open sheet and a usable button.
      expect(swal.calls).to.have.length(1);
      expect(isSheetOpen()).to.equal(true);
      expect(document.querySelector("[data-apply-filters]").disabled).to.equal(false);

      // Verify the next close lets the person out, instead of failing again.
      document.getElementById("close-filters").click();
      expect(isSheetOpen()).to.equal(false);
      expect(htmx.triggerCalls).to.have.length(1);

      // Verify reopening keeps the pending choices, so closing tries again.
      openSheet();
      document.getElementById("close-filters").click();
      expect(htmx.triggerCalls).to.have.length(2);
    });

    it("applies a new choice made after a failed apply on close", () => {
      // Fail one apply.
      openSheet();
      confirmRequest(getForm());
      document.querySelector("[data-apply-filters]").click();
      fireHtmx(getForm(), "htmx:responseError");

      // Change something else, held back by the guard, and close.
      expect(confirmRequest(getForm())).to.equal(false);
      document.getElementById("close-filters").click();

      // Verify the close sent the choices instead of dropping them.
      expect(htmx.triggerCalls).to.have.length(2);
    });

    it("retries a failed apply from Show results", () => {
      // Fail one apply.
      openSheet();
      confirmRequest(getForm());
      document.querySelector("[data-apply-filters]").click();
      fireHtmx(getForm(), "htmx:sendError");

      // Tap Show results again.
      document.querySelector("[data-apply-filters]").click();

      // Verify the second request went out.
      expect(htmx.triggerCalls).to.have.length(2);
    });

    it("strips open state before a history snapshot", () => {
      // Open the sheet and take a snapshot, as Back does.
      openSheet();
      confirmRequest(getForm());
      fireHtmx(document.body, "htmx:beforeHistorySave");

      // Verify nothing open reaches the snapshot, and no apply went out.
      expect(isSheetOpen()).to.equal(false);
      expect(getDrawer().hasAttribute("role")).to.equal(false);
      expect(getDrawer().hasAttribute("aria-modal")).to.equal(false);
      expect(document.getElementById("drawer-backdrop").classList.contains("hidden")).to.equal(true);
      expect(document.body.style.overflow).to.equal("");
      expect(htmx.triggerCalls).to.have.length(0);
    });

    it("resets sheet state from the DOM on a history restore", () => {
      // Restore markup that kept the sheet open, with no module state behind it.
      const drawer = getDrawer();
      drawer.classList.remove("-translate-x-full");
      drawer.classList.add("hidden");
      drawer.setAttribute("aria-hidden", "true");
      drawer.setAttribute("role", "dialog");
      drawer.setAttribute("aria-modal", "true");
      drawer.removeAttribute("aria-labelledby");
      fireHtmx(document.body, "htmx:historyRestore");

      // Verify the drawer is closed, and can open again.
      expect(isSheetOpen()).to.equal(false);
      expect(drawer.classList.contains("hidden")).to.equal(false);
      expect(drawer.hasAttribute("aria-hidden")).to.equal(false);
      expect(drawer.hasAttribute("role")).to.equal(false);
      expect(drawer.getAttribute("aria-labelledby")).to.equal("drawer-label");
    });

    it("syncs phone attributes on a history restore, which no settle follows", () => {
      // Restore a snapshot taken above the phone width.
      document.querySelectorAll(".filters-form").forEach((form) => form.removeAttribute("hx-sync"));
      document.getElementById("ts_query").removeAttribute("enterkeyhint");
      fireHtmx(document.body, "htmx:historyRestore");

      // Verify a second chip tap would still replace the first.
      document.querySelectorAll(".filters-form").forEach((form) => {
        expect(form.getAttribute("hx-sync")).to.equal("closest #entity-section:replace");
      });
      expect(document.getElementById("ts_query").getAttribute("enterkeyhint")).to.equal("search");
    });

    it("resets the sheet when the back-forward cache restores the page", () => {
      // Open the sheet and restore the page.
      openSheet();
      window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }));

      // Verify the sheet released everything.
      expect(isSheetOpen()).to.equal(false);
      expect(document.body.style.overflow).to.equal("");
    });

    it("ignores the first page show of a slow page", () => {
      // Open the sheet before the load finishes.
      openSheet();
      window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: false }));

      // Verify the sheet stays open.
      expect(isSheetOpen()).to.equal(true);
    });

    it("releases the sheet and every phone write when the query turns false", () => {
      // Open the sheet with a pending change, then rotate past the breakpoint.
      document.getElementById("open-filters").focus();
      openSheet();
      confirmRequest(getForm());
      phoneQuery.setMatches(false);

      // Verify the lock, roles and attributes are gone.
      expect(isSheetOpen()).to.equal(false);
      expect(document.body.style.overflow).to.equal("");
      expect(getDrawer().hasAttribute("role")).to.equal(false);
      expect(document.querySelector("[hx-sync]")).to.equal(null);
      expect(document.getElementById("ts_query").hasAttribute("enterkeyhint")).to.equal(false);
      expect(getForm().hasAttribute("aria-busy")).to.equal(false);
      expect(document.activeElement).to.equal(document.getElementById("open-filters"));

      // Verify the pending choices reached the results.
      expect(htmx.triggerCalls.map(([form]) => form)).to.deep.equal([getForm()]);

      // Verify the guard went with it.
      expect(confirmRequest(getForm())).to.equal(true);
    });

    it("refreshes only the sheet's form when Community changes", async () => {
      // Stub the section the refresh reads.
      const requests = [];
      globalThis.fetch = async (url) => {
        requests.push(String(url));
        return new Response(`
          <form id="events-form-mobile">
            <input type="checkbox" name="kind[]" value="virtual" checked />
            <collapsible-filter name="community"></collapsible-filter>
            <div data-dependent>New group filter</div>
          </form>
        `);
      };

      // Change the community inside the sheet.
      openSheet();
      const community = getForm().querySelector("collapsible-filter");
      community.querySelector("input").checked = true;
      community.dispatchEvent(new CustomEvent("filter-change", { bubbles: true, composed: true }));
      expect(getForm().getAttribute("aria-busy")).to.equal("true");
      await waitUntil(() => !getForm().hasAttribute("aria-busy"));

      // Verify one read-only request with the form's values.
      expect(requests).to.have.length(1);
      expect(requests[0]).to.include("/explore/events-section?");
      expect(decodeURIComponent(requests[0])).to.include("community[]=one");

      // Verify the filters around Community changed, and Community itself did not.
      expect(getForm().querySelector("[data-dependent]").textContent).to.equal("New group filter");
      expect(getForm().querySelector("collapsible-filter")).to.equal(community);
      expect(getForm().querySelector('input[value="virtual"]').checked).to.equal(true);

      // Verify the sheet stays open, on the option, with no results request.
      expect(isSheetOpen()).to.equal(true);
      expect(document.activeElement).to.equal(community.querySelector("input"));
      expect(getForm().hasAttribute("aria-busy")).to.equal(false);
      expect(confirmRequest(getForm())).to.equal(false);
    });

    it("refreshes again when a choice lands during a refresh", async () => {
      // Hold the responses back, and record the query of each request.
      const requests = [];
      const responses = [];
      globalThis.fetch = (url, { signal }) =>
        new Promise((resolve, reject) => {
          signal.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")));
          requests.push(decodeURIComponent(String(url)));
          responses.push(resolve);
        });

      // Change Community, then tick a type while the refresh runs.
      openSheet();
      const community = getForm().querySelector("collapsible-filter");
      community.dispatchEvent(new CustomEvent("filter-change", { bubbles: true, composed: true }));
      await waitUntil(() => requests.length === 1);
      getForm().querySelector('input[value="virtual"]').checked = true;
      confirmRequest(getForm());
      await waitUntil(() => requests.length === 2);

      // Answer the newest request.
      responses[1](
        new Response(`
          <form id="events-form-mobile">
            <input type="checkbox" name="kind[]" value="virtual" checked />
            <collapsible-filter name="community"></collapsible-filter>
          </form>
        `),
      );
      await waitUntil(() => !getForm().hasAttribute("aria-busy"));

      // Verify the refresh that lands carries the late choice.
      expect(requests[0]).not.to.include("kind[]=virtual");
      expect(requests[1]).to.include("kind[]=virtual");
      expect(getForm().querySelector('input[value="virtual"]').checked).to.equal(true);
    });

    it("drops a refresh that a newer one replaced", async () => {
      // Hold the first response back.
      const responses = [];
      globalThis.fetch = (url, { signal }) =>
        new Promise((resolve, reject) => {
          signal.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")));
          responses.push(resolve);
        });

      // Change Community twice.
      openSheet();
      const community = getForm().querySelector("collapsible-filter");
      const fire = () =>
        community.dispatchEvent(new CustomEvent("filter-change", { bubbles: true, composed: true }));
      fire();
      fire();
      await waitUntil(() => responses.length === 2);

      // Answer only the newest request.
      responses[1](
        new Response(`
          <form id="events-form-mobile">
            <collapsible-filter name="community"></collapsible-filter>
            <div data-dependent>Newest</div>
          </form>
        `),
      );
      await waitUntil(() => !getForm().hasAttribute("aria-busy"));

      // Verify the newest wins and the aborted one raised no alert.
      expect(getForm().querySelector("[data-dependent]").textContent).to.equal("Newest");
      expect(swal.calls).to.have.length(0);
    });

    it("alerts on a failed refresh and keeps the choices", async () => {
      // Fail the refresh.
      globalThis.fetch = async () => new Response("boom", { status: 500 });
      openSheet();
      const community = getForm().querySelector("collapsible-filter");
      community.dispatchEvent(new CustomEvent("filter-change", { bubbles: true, composed: true }));
      await waitUntil(() => !getForm().hasAttribute("aria-busy"));

      // Verify the alert, and that nothing was replaced.
      expect(swal.calls).to.have.length(1);
      expect(getForm().querySelector("[data-dependent]").textContent).to.equal("Old group filter");
      expect(getForm().hasAttribute("aria-busy")).to.equal(false);
      expect(isSheetOpen()).to.equal(true);
    });

    it("keeps the applied filters in a history snapshot after a refresh", async () => {
      // Refresh the form for a community, twice.
      const appliedFilters = [...getForm().childNodes].filter((node) => node.nodeType === Node.ELEMENT_NODE);
      stubRefresh("Refreshed group filter");
      openSheet();
      await refreshCommunity();
      stubRefresh("Newer group filter");
      await refreshCommunity();
      expect(getDependentFilter()).to.equal("Newer group filter");

      // Apply the choices, and let the snapshot run before the swap.
      document.querySelector("[data-apply-filters]").click();
      expect(getDependentFilter()).to.equal("Newer group filter");
      fireHtmx(document.body, "htmx:beforeHistorySave");

      // Verify the snapshot holds the first form, in its order.
      const filters = [...getForm().childNodes].filter((node) => node.nodeType === Node.ELEMENT_NODE);
      expect(filters).to.deep.equal(appliedFilters);
      expect(isSheetOpen()).to.equal(false);
    });

    it("keeps the refreshed filters on screen after a failed apply", async () => {
      // Refresh the form, then fail the apply.
      stubRefresh("Refreshed group filter");
      openSheet();
      await refreshCommunity();
      document.querySelector("[data-apply-filters]").click();
      fireHtmx(getForm(), "htmx:responseError");

      // Verify the choices stay, in the sheet and after closing it.
      expect(getDependentFilter()).to.equal("Refreshed group filter");
      document.getElementById("close-filters").click();
      expect(getDependentFilter()).to.equal("Refreshed group filter");

      // Verify an unrelated request still snapshots the applied filters.
      fireHtmx(document.body, "htmx:beforeHistorySave");
      expect(getDependentFilter()).to.equal("Old group filter");

      // Verify paging, which keeps the form, gets the pending choices back after the clone.
      await Promise.resolve();
      expect(getDependentFilter()).to.equal("Refreshed group filter");

      // Verify the next snapshot still holds the applied filters.
      fireHtmx(document.body, "htmx:beforeHistorySave");
      expect(getDependentFilter()).to.equal("Old group filter");
    });

    it("restores the applied filters after a rotation sends the refreshed ones", async () => {
      // Refresh the form, then rotate past the phone width.
      stubRefresh("Refreshed group filter");
      openSheet();
      await refreshCommunity();
      phoneQuery.setMatches(false);

      // Verify the choices went out, and a later snapshot needs no listener.
      expect(htmx.triggerCalls.at(-1)[0]).to.equal(getForm());
      expect(getDependentFilter()).to.equal("Old group filter");
    });

    it("removes a filter through its real control and focuses the next chip", () => {
      // Tap the first chip, whose control is the hidden desktop checkbox.
      const form = document.getElementById("events-form");
      const control = form.querySelector('input[value="virtual"]');
      const chip = document.querySelector('[data-applied-filter-value="virtual"]');
      chip.click();

      // Verify the control changed and the chip cannot toggle it back.
      expect(control.checked).to.equal(false);
      chip.click();
      expect(control.checked).to.equal(false);

      // Verify the history snapshot taken before the swap keeps a working chip.
      expect(chip.hasAttribute("disabled")).to.equal(false);

      // Settle a swap that dropped the chip.
      renderExplore();
      document.querySelector('[data-applied-filter-value="virtual"]').remove();
      fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");

      // Verify focus moved to the next chip and the change was announced.
      expect(document.activeElement).to.equal(document.querySelector("[data-applied-filter]"));
      expect(document.getElementById("explore-filter-status").textContent).to.equal(
        "Removed filter Virtual. 1 - 10 of 12 results",
      );
    });

    it("removes a multi-select filter through its chip button", () => {
      // Count taps on the component's own remove button.
      const removeButton = document.querySelector('[aria-label="Remove Alpha group"]');
      let removed = 0;
      removeButton.addEventListener("click", () => {
        removed += 1;
      });

      // Tap the applied chip.
      document.querySelector('[data-applied-filter="group"]').click();

      // Verify the component removed it.
      expect(removed).to.equal(1);
    });

    for (const type of ["htmx:responseError", "htmx:sendError"]) {
      it(`recovers a chip removal that ends in ${type}`, () => {
        // Remove a filter and fail its request.
        const form = document.getElementById("events-form");
        const control = form.querySelector('input[value="virtual"]');
        const chip = document.querySelector('[data-applied-filter-value="virtual"]');
        chip.click();
        fireHtmx(form, type);

        // Verify the alert, and the control back in step with the chip.
        expect(swal.calls).to.have.length(1);
        expect(control.checked).to.equal(true);

        // Verify the next swap announces nothing and moves no focus.
        chip.focus();
        fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");
        expect(document.getElementById("explore-filter-status").textContent).to.equal("");
        expect(document.activeElement).to.equal(chip);

        // Verify the chip works again.
        chip.click();
        expect(control.checked).to.equal(false);
      });
    }

    it("puts every filter of the form back after a failed removal", () => {
      // Remove the group, as the component does, and take a dependent filter with it.
      const form = document.getElementById("events-form");
      const filter = form.querySelector("multi-select-filter");
      const hybrid = form.querySelector('input[value="hybrid"]');
      const removeButton = filter.querySelector("button");
      filter.selected = ["alpha"];
      removeButton.addEventListener("click", () => {
        filter.selected = [];
        hybrid.checked = false;
      });
      document.querySelector('[data-applied-filter="group"]').click();
      expect(filter.selected).to.deep.equal([]);

      // Fail the request.
      fireHtmx(form, "htmx:responseError");

      // Verify the form holds the applied state again.
      expect(filter.selected).to.deep.equal(["alpha"]);
      expect(hybrid.checked).to.equal(true);
    });

    it("goes back to the applied state when a second chip's request fails", () => {
      // Remove two filters, the second replacing the first request.
      const form = document.getElementById("events-form");
      document.querySelector('[data-applied-filter-value="virtual"]').click();
      document.querySelector('[data-applied-filter-value="hybrid"]').click();

      // Fail the request that is left.
      fireHtmx(form, "htmx:responseError");

      // Verify one alert, and both filters back.
      expect(swal.calls).to.have.length(1);
      expect(form.querySelectorAll("input:checked")).to.have.length(2);
    });

    it("keeps a chip removal pending through a failure elsewhere in the section", () => {
      // Remove a filter, then fail a paging request.
      const control = document.getElementById("events-form").querySelector('input[value="virtual"]');
      const chip = document.querySelector('[data-applied-filter-value="virtual"]');
      chip.click();
      fireHtmx(document.getElementById("cards-list"), "htmx:responseError");

      // Verify the removal stands, and a repeat tap still cannot undo it.
      expect(swal.calls).to.have.length(0);
      expect(control.checked).to.equal(false);
      chip.click();
      expect(control.checked).to.equal(false);
    });

    it("alerts once when a chip removal fails under the open sheet", () => {
      // Remove a filter, open the sheet, then fail the request.
      const form = document.getElementById("events-form");
      document.querySelector('[data-applied-filter-value="virtual"]').click();
      openSheet();
      fireHtmx(form, "htmx:responseError");

      // Verify the sheet's own report is the only one.
      expect(swal.calls).to.have.length(1);
      expect(form.querySelector('input[value="virtual"]').checked).to.equal(true);
    });

    for (const [name, finish] of [
      ["its swap settles", () => swapSection()],
      ["a history restore replaces the page", () => fireHtmx(document.body, "htmx:historyRestore")],
      ["the query turns false", () => phoneQuery.setMatches(false)],
    ]) {
      it(`stops listening for a chip failure once ${name}`, () => {
        // Remove a filter and end the wait.
        const control = document.getElementById("events-form").querySelector('input[value="virtual"]');
        document.querySelector('[data-applied-filter-value="virtual"]').click();
        finish();
        control.checked = false;

        // Verify a later failure neither alerts nor touches the form.
        fireHtmx(document.getElementById("events-form"), "htmx:responseError");
        expect(swal.calls).to.have.length(0);
        expect(control.checked).to.equal(false);
      });
    }

    it("drops the count's focus hook when the query turns false", () => {
      // Remove the only chip, which leaves focus on the count.
      const chips = document.querySelectorAll("[data-applied-filter]");
      chips[1].remove();
      chips[2].remove();
      chips[0].click();
      renderExplore();
      document.querySelectorAll("[data-applied-filter]").forEach((chip) => chip.remove());
      fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");
      expect(document.getElementById("results").getAttribute("tabindex")).to.equal("-1");

      // Rotate past the phone width.
      phoneQuery.setMatches(false);

      // Verify the desktop tree is back.
      expect(document.getElementById("results").hasAttribute("tabindex")).to.equal(false);
    });

    it("fits the chips on one line and shows the rest from the toggle", () => {
      // Verify the chip that does not fit leaves its space to a shorter one after it.
      const toggle = getAppliedFiltersToggle();
      expect(getShownChips()).to.deep.equal(["Virtual", "Alpha group"]);
      expect(toggle.hidden).to.equal(false);
      expect(toggle.textContent.trim()).to.equal("+1 more");
      expect(toggle.getAttribute("aria-expanded")).to.equal("false");

      // Expand and collapse the card from the keyboard's focus.
      toggle.focus();
      toggle.click();
      expect(getShownChips()).to.have.length(3);
      expect(toggle.textContent.trim()).to.equal("Show less");
      expect(toggle.getAttribute("aria-expanded")).to.equal("true");
      toggle.click();
      expect(getShownChips()).to.deep.equal(["Virtual", "Alpha group"]);
      expect(toggle.getAttribute("aria-expanded")).to.equal("false");
      expect(document.activeElement).to.equal(toggle);
    });

    it("refits the chips when the viewport resizes", () => {
      // Widen the row past every chip.
      getAppliedFiltersToggle().parentElement.style.width = "400px";
      window.dispatchEvent(new Event("resize"));

      // Verify every chip shows, with no toggle.
      expect(getShownChips()).to.have.length(3);
      expect(getAppliedFiltersToggle().hidden).to.equal(true);
    });

    it("spares a pixel so a chip the rounded row width fits never wraps", () => {
      // Leave the row a fraction of a pixel short of Virtual, Hybrid and the toggle.
      getAppliedFiltersToggle().parentElement.style.width = "299.6px";
      document.querySelector('[data-applied-filter-value="hybrid"]').style.width = "94px";
      document.querySelector('[data-applied-filter-value="alpha"]').style.width = "80px";
      window.dispatchEvent(new Event("resize"));

      // Verify Hybrid leaves its place to the shorter chip after it.
      expect(getShownChips()).to.deep.equal(["Virtual", "Alpha group"]);
      expect(getAppliedFiltersToggle().textContent.trim()).to.equal("+1 more");
    });

    it("shows a chip wider than the row, truncated, before the toggle", () => {
      // Settle a swap whose first chip alone overflows the row.
      renderExplore();
      document.querySelector('[data-applied-filter-value="virtual"]').style.width = "400px";
      document.querySelector('[data-applied-filter-value="hybrid"]').style.width = "400px";
      document.querySelector('[data-applied-filter-value="alpha"]').remove();
      fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");

      // Verify the first chip stays in view, and the toggle counts the other.
      expect(getShownChips()).to.deep.equal(["Virtual"]);
      expect(getAppliedFiltersToggle().textContent.trim()).to.equal("+1 more");
    });

    it("keeps the card expanded across a swap", () => {
      // Expand the card, then settle a swap.
      getAppliedFiltersToggle().click();
      swapSection();

      // Verify the new card shows every chip.
      expect(getShownChips()).to.have.length(3);
      expect(getAppliedFiltersToggle().getAttribute("aria-expanded")).to.equal("true");
    });

    it("focuses the toggle when the chip after a removed one is hidden", () => {
      // Remove the first chip.
      document.querySelector('[data-applied-filter-value="virtual"]').click();

      // Settle a swap whose next chip no longer fits.
      renderExplore();
      document.querySelector('[data-applied-filter-value="virtual"]').remove();
      document.querySelector('[data-applied-filter-value="hybrid"]').style.width = "400px";
      fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");

      // Verify focus lands on the toggle that shows it.
      expect(getShownChips()).to.deep.equal(["Alpha group"]);
      expect(document.activeElement).to.equal(getAppliedFiltersToggle());
    });

    it("shows every chip again when the query turns false", () => {
      // Rotate past the phone width.
      phoneQuery.setMatches(false);

      // Verify the card is back as served.
      expect(getShownChips()).to.have.length(3);
      expect(getAppliedFiltersToggle().hidden).to.equal(true);
    });

    it("focuses the Filters button and announces Reset once its swap settles", async () => {
      // Reset from the card.
      document.querySelector("[data-applied-filters] .reset-filters").click();
      await waitUntil(() => htmx.triggerCalls.length > 0);

      // Settle a swap with no card.
      renderExplore();
      document.querySelector("[data-applied-filters]").remove();
      fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");

      // Verify focus and the announcement.
      expect(document.activeElement).to.equal(document.getElementById("open-filters"));
      expect(document.getElementById("explore-filter-status").textContent).to.equal(
        "Filters reset. 1 - 10 of 12 results",
      );
    });

    it("focuses the count once the last chip is gone", () => {
      // Remove the only chip left.
      const chips = document.querySelectorAll("[data-applied-filter]");
      chips[1].remove();
      chips[2].remove();
      chips[0].click();

      // Settle a swap with no chips.
      renderExplore();
      document.querySelectorAll("[data-applied-filter]").forEach((chip) => chip.remove());
      fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");

      // Verify focus lands on the count.
      expect(document.activeElement).to.equal(document.getElementById("results"));
    });

    it("focuses the pressed switch button once the other side settles", () => {
      // Press Groups.
      getSwitchButton("Groups").click();

      // Settle the swap, which replaces both buttons.
      renderExplore("Groups");
      fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");

      // Verify focus lands on the new pressed button, and on the way back too.
      expect(document.activeElement.textContent).to.equal("Groups");
      expect(document.activeElement.isConnected).to.equal(true);
      getSwitchButton("Events").click();
      renderExplore("Events");
      fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");
      expect(document.activeElement.textContent).to.equal("Events");
    });

    it("places no focus for a switch press whose request failed", () => {
      // Press Groups, whose request fails and leaves Events showing.
      getSwitchButton("Groups").click();

      // A later swap of the same side must not pull focus to the switch.
      renderExplore("Events");
      fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");
      expect(document.activeElement.tagName).to.equal("BODY");

      // The entry is gone, so a further swap has nothing to place either.
      renderExplore("Groups");
      fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");
      expect(document.activeElement.tagName).to.equal("BODY");
    });

    ["htmx:responseError", "htmx:sendError"].forEach((type) => {
      it(`reports a switch press that ends in ${type} once`, () => {
        // Press Groups and fail its request.
        const groups = getSwitchButton("Groups");
        groups.focus();
        groups.click();
        fireHtmx(groups, type);

        // Verify the alert shows and the press stays where it was.
        expect(swal.calls).to.have.length(1);
        expect(document.activeElement).to.equal(groups);
        expect(getSwitchButton("Events").getAttribute("aria-pressed")).to.equal("true");

        // Verify the listeners went with the press.
        fireHtmx(groups, type);
        expect(swal.calls).to.have.length(1);

        // Verify a later swap of that side places nothing.
        renderExplore("Groups");
        fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");
        expect(document.activeElement.tagName).to.equal("BODY");
      });
    });

    it("reports a retried switch press again", () => {
      // Fail the same press twice.
      const groups = getSwitchButton("Groups");
      groups.click();
      fireHtmx(groups, "htmx:responseError");
      groups.click();
      fireHtmx(groups, "htmx:responseError");

      // Verify each failure was reported.
      expect(swal.calls).to.have.length(2);
    });

    it("waits through errors of other requests during a switch press", () => {
      // Press Groups, and fail a paging request meanwhile.
      const groups = getSwitchButton("Groups");
      groups.click();
      fireHtmx(document.getElementById("cards-list"), "htmx:responseError");
      expect(swal.calls).to.have.length(0);

      // Verify the press still reports its own failure.
      fireHtmx(groups, "htmx:responseError");
      expect(swal.calls).to.have.length(1);
    });

    it("stays silent for an aborted switch press and lets it go", () => {
      // Press Groups and abort its request.
      const groups = getSwitchButton("Groups");
      groups.click();
      fireHtmx(groups, "htmx:sendAbort");
      expect(swal.calls).to.have.length(0);

      // Verify nothing is held for a late error.
      fireHtmx(groups, "htmx:responseError");
      expect(swal.calls).to.have.length(0);
    });

    it("stops waiting for a switch press once its swap settles", () => {
      // Press Groups and settle the swap.
      getSwitchButton("Groups").click();
      renderExplore("Groups");
      fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");

      // Verify a later failure of the switch reports nothing.
      fireHtmx(getSwitchButton("Events"), "htmx:responseError");
      expect(swal.calls).to.have.length(0);
    });

    it("stops waiting for a switch press when the query turns false", () => {
      // Press Groups, then rotate past phone widths.
      const groups = getSwitchButton("Groups");
      groups.click();
      phoneQuery.setMatches(false);

      // Verify its failure reports nothing.
      fireHtmx(groups, "htmx:responseError");
      expect(swal.calls).to.have.length(0);
    });

    it("stops waiting for a switch press on a history restore", () => {
      // Press Groups, then go Back.
      const groups = getSwitchButton("Groups");
      groups.click();
      fireHtmx(document.body, "htmx:historyRestore");

      // Verify its failure reports nothing.
      fireHtmx(groups, "htmx:responseError");
      expect(swal.calls).to.have.length(0);
    });

    it("leaves a failed switch press under an open sheet to the sheet", () => {
      // Open the sheet, then fail a press reached around it.
      openSheet();
      const groups = getSwitchButton("Groups");
      groups.click();
      fireHtmx(groups, "htmx:responseError");

      // Verify the failure reports once.
      expect(swal.calls).to.have.length(1);
    });

    it("places no focus for the side already pressed", () => {
      // Press the side already showing, which sends nothing.
      getSwitchButton("Events").click();

      // Verify a later swap leaves focus alone.
      renderExplore("Events");
      fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");
      expect(document.activeElement.tagName).to.equal("BODY");
    });

    it("forgets a switch press when the query turns false", () => {
      // Press Groups, then rotate out and back before the swap settles.
      getSwitchButton("Groups").click();
      phoneQuery.setMatches(false);
      phoneQuery.setMatches(true);

      // Verify the swap places nothing.
      renderExplore("Groups");
      fireHtmx(document.getElementById("entity-section"), "htmx:afterSettle");
      expect(document.activeElement.tagName).to.equal("BODY");
    });

    it("scrolls paging swaps below the results bar", async () => {
      // Count scrolls on the swap target.
      const cards = document.getElementById("cards-list");
      let scrolls = 0;
      cards.scrollIntoView = () => {
        scrolls += 1;
      };

      // Settle a paging swap and wait for htmx's own scroll to run.
      fireHtmx(cards, "htmx:afterSettle");
      await nextFrame();

      // Verify the results were brought back into view.
      expect(scrolls).to.equal(1);
    });
  });

  describe("getPhoneListUrl", () => {
    it("drops the calendar's view and month", () => {
      // Build the list URL of a calendar view.
      const url = getPhoneListUrl(
        "https://example.test/explore?entity=events&view_mode=calendar&date_from=2030-01-01&date_to=2030-01-31&kind[]=virtual",
        true,
      );

      // Verify only the calendar's values went.
      const params = new URL(url).searchParams;
      expect(params.has("view_mode")).to.equal(false);
      expect(params.has("date_from")).to.equal(false);
      expect(params.has("date_to")).to.equal(false);
      expect(params.get("entity")).to.equal("events");
      expect(params.get("kind[]")).to.equal("virtual");
    });

    it("keeps the date range of a map view", () => {
      // Build the list URL of a map view.
      const params = new URL(
        getPhoneListUrl("https://example.test/explore?view_mode=map&date_from=2030-01-01", false),
      ).searchParams;

      // Verify the dates stay.
      expect(params.has("view_mode")).to.equal(false);
      expect(params.get("date_from")).to.equal("2030-01-01");
    });
  });
});
