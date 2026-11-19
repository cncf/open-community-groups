import { expect } from "@open-wc/testing";

import {
  clearRestoredLoadingState,
  initializeNavigationState,
  isNavigationSwap,
} from "/static/js/common/navigation-state.js";
import {
  resetDom,
  trackAddedEventListeners,
} from "/tests/unit/test-utils/dom.js";

describe("navigation state", () => {
  let listeners;
  let originalSwal;
  let swalCloseCount;

  beforeEach(() => {
    resetDom();
    listeners = trackAddedEventListeners();
    originalSwal = globalThis.Swal;
    swalCloseCount = 0;
    globalThis.Swal = {
      close: () => {
        swalCloseCount += 1;
      },
    };
  });

  afterEach(() => {
    listeners.restore();
    globalThis.Swal = originalSwal;
    resetDom();
  });

  it("recognizes full-page and group-dashboard navigation swaps", () => {
    // Build the targets used by shared dashboard navigation.
    const content = document.createElement("div");
    content.id = "dashboard-content";
    const layout = document.createElement("div");
    layout.id = "dashboard-layout";
    const partial = document.createElement("div");

    // Only page and group-dashboard layout replacements are navigation.
    expect(isNavigationSwap({ detail: { target: document.body } })).to.equal(
      true,
    );
    expect(isNavigationSwap({ detail: { target: content } })).to.equal(false);
    expect(isNavigationSwap({ detail: { target: layout } })).to.equal(true);
    expect(isNavigationSwap({ detail: { target: partial } })).to.equal(false);
  });

  it("dismisses dialogs and action menus before dashboard navigation", () => {
    // Build open overlays and the dashboard target they belong to.
    document.body.innerHTML = `
      <div id="dashboard-layout"></div>
      <details data-actions-menu open><summary>Actions</summary></details>
      <div role="dialog" aria-modal="true" aria-hidden="false"></div>
    `;
    document.body.dataset.modalOpenCount = "1";
    document.body.style.overflow = "hidden";
    initializeNavigationState();

    // Start a group-dashboard layout swap.
    document.dispatchEvent(
      new CustomEvent("htmx:beforeSwap", {
        detail: { target: document.getElementById("dashboard-layout") },
      }),
    );

    // Navigation closes every transient overlay and restores page scrolling.
    expect(swalCloseCount).to.equal(1);
    expect(document.querySelector("[data-actions-menu]").open).to.equal(false);
    expect(
      document.querySelector('[role="dialog"]').classList.contains("hidden"),
    ).to.equal(true);
    expect(document.body.style.overflow).to.equal("");
  });

  it("keeps the alert open for a marked layout refresher", () => {
    // Build a layout holding a refresher, a menu and a modal, beside an alert popup.
    document.body.innerHTML = `
      <div id="dashboard-layout">
        <div data-keeps-alerts hidden></div>
        <details data-actions-menu open><summary>Actions</summary></details>
        <div id="layout-modal" role="dialog" aria-modal="true" aria-hidden="false"></div>
      </div>
      <div id="alert-popup" role="dialog" aria-modal="true" aria-hidden="false"></div>
    `;
    initializeNavigationState();

    // Start the layout swap requested by the refresher.
    const layout = document.getElementById("dashboard-layout");
    layout.dispatchEvent(
      new CustomEvent("htmx:beforeSwap", {
        bubbles: true,
        detail: {
          requestConfig: { elt: document.querySelector("[data-keeps-alerts]") },
          target: layout,
        },
      }),
    );

    // The action alert stays while the replaced menus and modals still close.
    expect(swalCloseCount).to.equal(0);
    expect(document.getElementById("alert-popup").getAttribute("aria-hidden")).to.equal("false");
    expect(document.querySelector("[data-actions-menu]").open).to.equal(false);
    expect(document.getElementById("layout-modal").getAttribute("aria-hidden")).to.equal("true");
  });

  it("leaves overlays open for a dashboard-content refresh", () => {
    // Build an open menu beside the table and content refresh target.
    document.body.innerHTML = `
      <div id="dashboard-content"></div>
      <details data-actions-menu open><summary>Actions</summary></details>
    `;
    initializeNavigationState();

    // Refresh dashboard content without navigating away from the dashboard.
    document.dispatchEvent(
      new CustomEvent("htmx:beforeSwap", {
        detail: { target: document.getElementById("dashboard-content") },
      }),
    );

    // Content refreshes do not dismiss feedback for the completed action.
    expect(swalCloseCount).to.equal(0);
    expect(document.querySelector("[data-actions-menu]").open).to.equal(true);
  });

  [
    ["page", () => document.body],
    ["dashboard layout", () => document.getElementById("dashboard-layout")],
  ].forEach(([name, getTarget]) => {
    describe(`for a ${name} swap`, () => {
      beforeEach(() => {
        // Build an open menu, an open modal and a locked page beside the dashboard layout.
        document.body.innerHTML = `
          <div id="dashboard-layout"></div>
          <details data-actions-menu open><summary>Actions</summary></details>
          <div role="dialog" aria-modal="true" aria-hidden="false"></div>
        `;
        document.body.dataset.modalOpenCount = "1";
        document.body.style.overflow = "hidden";
        initializeNavigationState();
      });

      // Dispatch a navigation beforeSwap with the given outcome from the swap target.
      const dispatchBeforeSwap = (detail) => {
        const target = getTarget();
        target.dispatchEvent(
          new CustomEvent("htmx:beforeSwap", {
            bubbles: true,
            detail: { target, ...detail },
          }),
        );
      };

      it("keeps the alert, menus, dialogs and scroll lock when the navigation fails", () => {
        // Start the swap of a failed request, which HTMX will not perform.
        dispatchBeforeSwap({ isError: true, shouldSwap: false });

        // The page the failure leaves in place keeps its overlays.
        expect(swalCloseCount).to.equal(0);
        expect(document.querySelector("[data-actions-menu]").open).to.equal(true);
        expect(document.querySelector('[role="dialog"]').getAttribute("aria-hidden")).to.equal("false");
        expect(document.body.dataset.modalOpenCount).to.equal("1");
        expect(document.body.style.overflow).to.equal("hidden");
      });

      [
        ["a marked not found page", { isError: false, shouldSwap: true }],
        ["a no content refresh", { isError: false, shouldSwap: false }],
      ].forEach(([outcome, detail]) => {
        it(`dismisses the overlays before ${outcome}`, () => {
          // Start the swap of a request that did not fail.
          dispatchBeforeSwap(detail);

          // Navigation cleanup runs as for any other navigation.
          expect(swalCloseCount).to.equal(1);
          expect(document.querySelector("[data-actions-menu]").open).to.equal(false);
          expect(document.querySelector('[role="dialog"]').classList.contains("hidden")).to.equal(true);
          expect(document.body.style.overflow).to.equal("");
        });
      });
    });
  });

  it("reloads the page once when a history cache miss fails to load", () => {
    // Register navigation state with an observable reload.
    let reloads = 0;
    initializeNavigationState({
      reloadPage: () => {
        reloads += 1;
      },
    });

    // Fail the refetch of a page missing from the HTMX history cache.
    document.body.dispatchEvent(new CustomEvent("htmx:historyCacheMissLoadError", { bubbles: true }));

    // The page is loaded again from the server, once.
    expect(reloads).to.equal(1);
  });

  [
    ["reloads the page once when a history cache miss refetch has a network error", "error", 1],
    ["does not reload the page when a history cache miss refetch loads", "load", 0],
  ].forEach(([name, outcome, expectedReloads]) => {
    it(name, () => {
      // Register navigation state with an observable reload.
      let reloads = 0;
      initializeNavigationState({
        reloadPage: () => {
          reloads += 1;
        },
      });

      // Start the refetch of a page missing from the HTMX history cache.
      const xhr = new EventTarget();
      document.body.dispatchEvent(
        new CustomEvent("htmx:historyCacheMiss", { bubbles: true, detail: { path: "/", xhr } }),
      );

      // Finish the refetch, then repeat the outcome to prove the listener runs once.
      xhr.dispatchEvent(new Event(outcome));
      xhr.dispatchEvent(new Event(outcome));

      // Only a network error loads the page again from the server, once.
      expect(reloads).to.equal(expectedReloads);
    });
  });

  it("does not reload the page after a history restore", () => {
    // Register navigation state with an observable reload.
    let reloads = 0;
    initializeNavigationState({
      reloadPage: () => {
        reloads += 1;
      },
    });

    // Restore a page from HTMX history.
    document.body.dispatchEvent(new CustomEvent("htmx:historyRestore", { bubbles: true }));

    // A restored page needs no reload.
    expect(reloads).to.equal(0);
  });

  it("clears loading classes retained by a history snapshot", () => {
    // Build a restored fragment with request classes on its root and child.
    const root = document.createElement("section");
    root.classList.add("htmx-request");
    root.innerHTML = '<button class="htmx-request">Save</button>';

    // Clear the stale state from the complete restored fragment.
    clearRestoredLoadingState(root);

    // The root and every descendant return to their idle state.
    expect(root.classList.contains("htmx-request")).to.equal(false);
    expect(
      root.querySelector("button").classList.contains("htmx-request"),
    ).to.equal(false);
  });

  it("clears restored loading and overlays after HTMX history navigation", () => {
    // Build stale state captured while a request and menu were open.
    document.body.innerHTML = `
      <div class="htmx-request"></div>
      <details data-actions-menu open><summary>Actions</summary></details>
    `;
    initializeNavigationState();

    // Restore an HTMX history snapshot.
    document.dispatchEvent(new CustomEvent("htmx:historyRestore"));

    // Snapshot-only state is removed before the restored page is used.
    expect(swalCloseCount).to.equal(1);
    expect(document.querySelector(".htmx-request")).to.equal(null);
    expect(document.querySelector("[data-actions-menu]").open).to.equal(false);
  });
});
