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
