import { expect } from "@open-wc/testing";

import {
  cancelDelayedPopover,
  getExploreItemUrl,
  loadWidgetScripts,
  renderPopoverCardShell,
  scheduleDelayedPopover,
} from "/static/js/alliance/explore/widgets.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("alliance explore widgets", () => {
  beforeEach(() => {
    resetDom();
  });

  it("builds explore item urls per entity and guards missing event slugs", () => {
    // Event urls prefer the pretty group slug and require both slugs.
    expect(
      getExploreItemUrl("events", {
        alliance_name: "spain",
        group_slug: "malaga-js",
        group_slug_pretty: "malaga-javascript",
        slug: "open-source-day",
      }),
    ).to.equal("/spain/group/malaga-javascript/event/open-source-day");
    expect(
      getExploreItemUrl("events", {
        alliance_name: "spain",
        group_slug: "malaga-js",
        slug: "open-source-day",
      }),
    ).to.equal("/spain/group/malaga-js/event/open-source-day");
    expect(getExploreItemUrl("events", { alliance_name: "spain", slug: "no-group" })).to.equal(undefined);

    // Group urls prefer the pretty slug; unsupported entities resolve nothing.
    expect(
      getExploreItemUrl("groups", {
        alliance_name: "spain",
        slug: "malaga-js",
        slug_pretty: "malaga-javascript",
      }),
    ).to.equal("/spain/group/malaga-javascript");
    expect(getExploreItemUrl("users", { alliance_name: "spain" })).to.equal(undefined);
  });

  it("wraps popover content in the shared card shell", () => {
    expect(renderPopoverCardShell("<article>Event</article>")).to.equal(
      '<div class="explore-popover-card-shell"><article>Event</article></div>',
    );
  });

  it("schedules delayed popovers and cancels pending ones", async () => {
    // Track popover opens triggered through the shared hover timers.
    const timers = new WeakMap();
    const hoveredElement = document.createElement("div");
    let opens = 0;

    // Re-entering before the delay keeps only the latest scheduled open.
    scheduleDelayedPopover(timers, hoveredElement, () => {
      opens += 1;
    });
    scheduleDelayedPopover(timers, hoveredElement, () => {
      opens += 1;
    });

    // Leaving the element cancels the pending popover entirely.
    cancelDelayedPopover(timers, hoveredElement);
    await new Promise((resolve) => setTimeout(resolve, 350));
    expect(opens).to.equal(0);
    expect(timers.has(hoveredElement)).to.equal(false);
  });

  it("shows the main loading overlay and runs setup when scripts load", async () => {
    // Mount the overlay controlled by the widget bootstrap.
    document.body.innerHTML = '<div id="main-loading-widget" class="hidden"></div>';
    const overlay = document.getElementById("main-loading-widget");
    let ready = 0;

    // The overlay is shown while scripts load and setup runs on success.
    loadWidgetScripts({
      mainLoadingId: "main-loading-widget",
      loadScripts: () => Promise.resolve(),
      onReady: () => {
        ready += 1;
      },
    });
    expect(overlay.classList.contains("hidden")).to.equal(false);
    await waitForMicrotask();
    expect(ready).to.equal(1);
  });

  it("hides the main loading overlay again when script loading fails", async () => {
    // Mount the overlay controlled by the widget bootstrap.
    document.body.innerHTML = '<div id="main-loading-widget" class="hidden"></div>';
    const overlay = document.getElementById("main-loading-widget");
    let ready = 0;

    // Failed script loads hide the overlay instead of leaving a stuck spinner.
    loadWidgetScripts({
      mainLoadingId: "main-loading-widget",
      loadScripts: () => Promise.reject(new Error("load failed")),
      onReady: () => {
        ready += 1;
      },
    });
    expect(overlay.classList.contains("hidden")).to.equal(false);
    await waitForMicrotask();
    expect(ready).to.equal(0);
    expect(overlay.classList.contains("hidden")).to.equal(true);
  });
});
