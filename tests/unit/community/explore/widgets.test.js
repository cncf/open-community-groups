import { expect } from "@open-wc/testing";

import {
  bindExploreCardTooltip,
  bindExploreCardTrigger,
  CARD_CACHE_MAX_ENTRIES,
  CARD_CACHE_TTL_MS,
  CARD_STATUS,
  createCardController,
  createExploreCardLoader,
  getExploreCardUrl,
  getExploreItemUrl,
  isPlainLeftClick,
  loadWidgetScripts,
  POPOVER_CLOSE_DELAY_MS,
  POPOVER_OPEN_DELAY_MS,
  renderExploreCard,
  renderPopoverCardShell,
  syncExploreCardTooltip,
  updateTruncationNotice,
} from "/static/js/community/explore/widgets.js";
import { createDeferred, waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";
import { createManualTimers } from "/tests/unit/test-utils/timers.js";

const EVENT = {
  community_name: "spain",
  event_id: "event 1/2",
  group_slug: "malaga-js",
  name: "Open <Source> Day",
  slug: "open-source-day",
};
const GROUP = { community_name: "spain", group_id: "group-1", name: "Málaga JS", slug: "malaga-js" };
const READY_CARD = { html: "<article>Card</article>", status: "ready" };

describe("community explore widgets", () => {
  beforeEach(() => {
    resetDom();
  });

  it("builds explore item urls per entity and guards missing event slugs", () => {
    // Event urls prefer the pretty group slug and require both slugs.
    expect(
      getExploreItemUrl("events", {
        community_name: "spain",
        group_slug: "malaga-js",
        group_slug_pretty: "malaga-javascript",
        slug: "open-source-day",
      }),
    ).to.equal("/spain/group/malaga-javascript/event/open-source-day");
    expect(
      getExploreItemUrl("events", {
        community_name: "spain",
        group_slug: "malaga-js",
        slug: "open-source-day",
      }),
    ).to.equal("/spain/group/malaga-js/event/open-source-day");
    expect(getExploreItemUrl("events", { community_name: "spain", slug: "no-group" })).to.equal(undefined);

    // Group urls prefer the pretty slug; unsupported entities resolve nothing.
    expect(
      getExploreItemUrl("groups", {
        community_name: "spain",
        slug: "malaga-js",
        slug_pretty: "malaga-javascript",
      }),
    ).to.equal("/spain/group/malaga-javascript");
    expect(getExploreItemUrl("users", { community_name: "spain" })).to.equal(undefined);
  });

  it("wraps popover content in the shared card shell", () => {
    expect(renderPopoverCardShell("<article>Event</article>")).to.equal(
      '<div class="explore-popover-card-shell"><article>Event</article></div>',
    );
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

  it("builds card urls per entity and view", () => {
    // Event cards carry the view mode and encode the event id.
    expect(getExploreCardUrl("events", EVENT, "calendar")).to.equal(
      "/explore/events/event%201%2F2/card?view_mode=calendar",
    );
    expect(getExploreCardUrl("events", { event_id: "e-1" }, "map")).to.equal(
      "/explore/events/e-1/card?view_mode=map",
    );

    // Group cards ignore the view; unsupported entities resolve nothing.
    expect(getExploreCardUrl("groups", GROUP, "map")).to.equal("/explore/groups/group-1/card");
    expect(getExploreCardUrl("users", GROUP, "map")).to.equal(undefined);
  });

  it("updates the truncation notice counts and visibility", () => {
    // Mount the notice rendered by the map and calendar views.
    document.body.innerHTML = `
      <p data-explore-truncation-notice class="hidden">
        Showing <span data-truncation-shown></span> of <span data-truncation-total></span>
      </p>
    `;
    const notice = document.querySelector("[data-explore-truncation-notice]");

    // Truncated results show the drawn and matching counts.
    updateTruncationNotice(notice, { shown: 1000, total: 1284, truncated: true });
    expect(notice.classList.contains("hidden")).to.equal(false);
    expect(notice.querySelector("[data-truncation-shown]").textContent).to.equal("1000");
    expect(notice.querySelector("[data-truncation-total]").textContent).to.equal("1284");

    // Complete results hide the notice again.
    updateTruncationNotice(notice, { shown: 3, total: 3, truncated: false });
    expect(notice.classList.contains("hidden")).to.equal(true);
    expect(notice.querySelector("[data-truncation-shown]").textContent).to.equal("3");

    // A missing notice element is ignored.
    expect(() => updateTruncationNotice(null, { shown: 1, total: 2, truncated: true })).not.to.throw();
  });

  describe("card rendering", () => {
    it("renders ready cards with the server html", () => {
      expect(
        renderExploreCard({ html: "<article>Card</article>", status: CARD_STATUS.ready }, "Name"),
      ).to.equal('<div class="explore-popover-card-shell"><article>Card</article></div>');
    });

    it("renders the loading state with the escaped item name", () => {
      // Render the loading state, also used when no result is available yet.
      const container = document.createElement("div");
      container.innerHTML = renderExploreCard({ status: CARD_STATUS.loading }, EVENT.name);
      const status = container.querySelector("[data-explore-card-status]");

      // The name is escaped text and the loading detail is shown.
      expect(status.dataset.exploreCardStatus).to.equal("loading");
      expect(status.querySelector("p").textContent).to.equal("Open <Source> Day");
      expect(container.innerHTML).to.include("Open &lt;Source&gt; Day");
      expect(container.textContent).to.include("Loading details…");
      expect(renderExploreCard(null, EVENT.name)).to.equal(
        renderExploreCard({ status: CARD_STATUS.loading }, EVENT.name),
      );
    });

    it("renders the fallback card with the escaped item name", () => {
      // Render an unavailable card whose name contains markup.
      const container = document.createElement("div");
      container.innerHTML = renderExploreCard({ status: CARD_STATUS.unavailable }, '<img src=x onerror="x">');
      const status = container.querySelector("[data-explore-card-status]");

      // The fallback keeps the name as text and explains the missing details.
      expect(status.dataset.exploreCardStatus).to.equal("unavailable");
      expect(container.querySelector("img")).to.equal(null);
      expect(status.querySelector("p").textContent).to.equal('<img src=x onerror="x">');
      expect(container.textContent).to.include("Details are not available right now.");
    });
  });

  describe("card loader", () => {
    let clock;
    let fetchMock;
    let swal;

    const cardResponse = (status, html = "") => ({
      ok: status >= 200 && status < 300,
      status,
      text: async () => html,
    });

    beforeEach(() => {
      clock = { now: 1000 };
      fetchMock = mockFetch({ impl: async () => cardResponse(200, "<article>Card</article>") });
      swal = mockSwal();
    });

    afterEach(() => {
      fetchMock.restore();
      swal.restore();
    });

    const createLoader = (entity = "groups", view = "map") =>
      createExploreCardLoader(entity, view, { now: () => clock.now });

    it("shares in-flight requests and requests html cards", async () => {
      // Hold the card response while two loads of the same item start.
      const response = createDeferred();
      fetchMock.setImpl(() => response.promise);
      const loader = createLoader("events", "calendar");
      const firstLoad = loader.load(EVENT);
      const secondLoad = loader.load({ ...EVENT });

      // Both loads share one html request and nothing is ready yet.
      expect(firstLoad).to.equal(secondLoad);
      expect(fetchMock.calls).to.have.length(1);
      expect(fetchMock.calls[0][0]).to.equal("/explore/events/event%201%2F2/card?view_mode=calendar");
      expect(fetchMock.calls[0][1].headers.get("Accept")).to.equal("text/html");
      expect(loader.peek(EVENT)).to.equal(null);

      // Both loads resolve with the ready card.
      response.resolve(cardResponse(200, "<article>Event</article>"));
      const results = await Promise.all([firstLoad, secondLoad]);
      expect(results[0]).to.deep.equal({ html: "<article>Event</article>", status: "ready" });
      expect(results[1]).to.equal(results[0]);
      expect(loader.peek(EVENT)).to.equal(results[0]);
    });

    it("caches ready cards until the ttl expires", async () => {
      // Load a card once.
      const loader = createLoader();
      const first = await loader.load(GROUP);

      // Loads before the ttl reuse the cached card.
      clock.now += CARD_CACHE_TTL_MS - 1;
      expect(await loader.load(GROUP)).to.equal(first);
      expect(loader.peek(GROUP)).to.equal(first);
      expect(fetchMock.calls).to.have.length(1);

      // Loads at the ttl request the card again.
      clock.now += 1;
      expect(loader.peek(GROUP)).to.equal(null);
      await loader.load(GROUP);
      expect(fetchMock.calls).to.have.length(2);
    });

    it("caches not found cards as unavailable until the ttl expires", async () => {
      // Load a card that no longer exists.
      fetchMock.setImpl(async () => cardResponse(404));
      const loader = createLoader();
      expect(await loader.load(GROUP)).to.deep.equal({ status: "unavailable" });

      // The unavailable result is reused until it expires.
      clock.now += CARD_CACHE_TTL_MS - 1;
      expect(await loader.load(GROUP)).to.deep.equal({ status: "unavailable" });
      expect(loader.peek(GROUP)).to.deep.equal({ status: "unavailable" });
      expect(fetchMock.calls).to.have.length(1);
      clock.now += 1;
      await loader.load(GROUP);
      expect(fetchMock.calls).to.have.length(2);
    });

    it("evicts the oldest card beyond the cache limit", async () => {
      // Fill the cache past its limit with distinct items.
      const loader = createLoader();
      await Promise.all(
        Array.from({ length: CARD_CACHE_MAX_ENTRIES + 1 }, (_, index) =>
          loader.load({ group_id: `group-${index}` }),
        ),
      );
      expect(fetchMock.calls).to.have.length(CARD_CACHE_MAX_ENTRIES + 1);

      // The second oldest card is still cached.
      await loader.load({ group_id: "group-1" });
      expect(fetchMock.calls).to.have.length(CARD_CACHE_MAX_ENTRIES + 1);

      // The oldest card was evicted and is requested again.
      expect(loader.peek({ group_id: "group-0" })).to.equal(null);
      await loader.load({ group_id: "group-0" });
      expect(fetchMock.calls).to.have.length(CARD_CACHE_MAX_ENTRIES + 2);
      expect(fetchMock.calls.at(-1)[0]).to.equal("/explore/groups/group-0/card");
    });

    it("retries after network errors, server errors, and unreadable bodies without rejecting", async () => {
      const loader = createLoader();

      // A network error resolves as unavailable and is not cached.
      fetchMock.setImpl(async () => {
        throw new TypeError("Failed to fetch");
      });
      expect(await loader.load(GROUP)).to.deep.equal({ status: "unavailable" });
      expect(loader.peek(GROUP)).to.equal(null);

      // A server error resolves as unavailable and is not cached.
      fetchMock.setImpl(async () => cardResponse(500));
      expect(await loader.load(GROUP)).to.deep.equal({ status: "unavailable" });
      expect(loader.peek(GROUP)).to.equal(null);

      // An unreadable body resolves as unavailable and is not cached.
      fetchMock.setImpl(async () => ({
        ok: true,
        status: 200,
        text: async () => {
          throw new Error("body stream failed");
        },
      }));
      expect(await loader.load(GROUP)).to.deep.equal({ status: "unavailable" });
      expect(loader.peek(GROUP)).to.equal(null);

      // The next load retries and caches the ready card without alerts.
      fetchMock.setImpl(async () => cardResponse(200, "<article>Group</article>"));
      expect(await loader.load(GROUP)).to.deep.equal({ html: "<article>Group</article>", status: "ready" });
      expect(fetchMock.calls).to.have.length(4);
      expect(swal.calls).to.have.length(0);
    });
  });

  describe("card controller", () => {
    let closes;
    let loader;
    let renders;
    let timers;

    // Card loader stub whose loads resolve only when the test settles them.
    const createLoaderStub = () => {
      const stub = {
        cached: null,
        loads: [],
        load(item) {
          const deferred = createDeferred();
          stub.loads.push({ item, ...deferred });
          return deferred.promise;
        },
        peek: () => stub.cached,
      };
      return stub;
    };

    const createController = () =>
      createCardController({
        close: () => {
          closes += 1;
        },
        item: GROUP,
        loader,
        render: (result) => renders.push(result),
        timers,
      });

    const READY = { html: "<article>Card</article>", status: "ready" };

    beforeEach(() => {
      closes = 0;
      loader = createLoaderStub();
      renders = [];
      timers = createManualTimers();
    });

    it("starts loading on activation and waits for the open delay before rendering", async () => {
      // Activate the card and resolve it right away.
      const controller = createController();
      controller.activate("hover");
      expect(loader.loads).to.have.length(1);
      expect(loader.loads[0].item).to.equal(GROUP);
      loader.loads[0].resolve(READY);
      await waitForMicrotask();

      // Further activations neither reload nor render early.
      controller.activate("focus");
      timers.advance(POPOVER_OPEN_DELAY_MS - 1);
      expect(loader.loads).to.have.length(1);
      expect(renders).to.deep.equal([]);
      expect(controller.isActive()).to.equal(true);
      expect(controller.isOpen()).to.equal(false);

      // The early result renders once the delay ends.
      timers.advance(1);
      expect(renders).to.deep.equal([READY]);
      expect(controller.isOpen()).to.equal(true);
    });

    it("renders cached cards at the open delay without waiting for the load", () => {
      // Activate an item whose card is already cached.
      loader.cached = READY;
      const controller = createController();
      controller.activate("hover");

      // The cached card renders at the delay, never before.
      timers.advance(POPOVER_OPEN_DELAY_MS - 1);
      expect(renders).to.deep.equal([]);
      timers.advance(1);
      expect(renders).to.deep.equal([READY]);
    });

    it("shows the loading state for slow cards and then the loaded card", async () => {
      // Open the card before its request completes.
      const controller = createController();
      controller.activate("hover");
      timers.advance(POPOVER_OPEN_DELAY_MS);
      expect(renders).to.deep.equal([{ status: "loading" }]);

      // The loaded card replaces the loading state.
      loader.loads[0].resolve({ status: "unavailable" });
      await waitForMicrotask();
      expect(renders).to.deep.equal([{ status: "loading" }, { status: "unavailable" }]);
    });

    it("does not open cards whose load completes after the trigger is left", async () => {
      // Leave the trigger before the open delay.
      const controller = createController();
      controller.activate("hover");
      controller.deactivate("hover");
      expect(controller.isActive()).to.equal(false);
      expect(timers.pendingCount).to.equal(0);

      // A late result and timers never render the card.
      loader.loads[0].resolve(READY);
      await waitForMicrotask();
      timers.advance(POPOVER_OPEN_DELAY_MS);
      expect(renders).to.deep.equal([]);
      expect(closes).to.equal(0);
    });

    it("does not reopen cards dismissed with Escape when their load completes", async () => {
      // Open the loading card and dismiss it.
      const controller = createController();
      controller.activate("focus");
      timers.advance(POPOVER_OPEN_DELAY_MS);
      controller.dismiss();
      expect(closes).to.equal(1);
      expect(controller.isOpen()).to.equal(false);

      // The late result does not render the dismissed card.
      loader.loads[0].resolve(READY);
      await waitForMicrotask();
      timers.advance(POPOVER_OPEN_DELAY_MS);
      expect(renders).to.deep.equal([{ status: "loading" }]);

      // A new activation starts a fresh load and opens again.
      controller.activate("hover");
      expect(loader.loads).to.have.length(2);
      timers.advance(POPOVER_OPEN_DELAY_MS);
      expect(controller.isOpen()).to.equal(true);
    });

    it("keeps the card open while the trigger stays focused after the pointer leaves", () => {
      // Open the card with both focus and hover.
      const controller = createController();
      controller.activate("focus");
      controller.activate("hover");
      timers.advance(POPOVER_OPEN_DELAY_MS);

      // Leaving with the pointer keeps the focused card open.
      controller.deactivate("hover");
      timers.advance(POPOVER_CLOSE_DELAY_MS * 2);
      expect(controller.isOpen()).to.equal(true);
      expect(closes).to.equal(0);

      // Blurring the trigger closes it after the grace delay.
      controller.deactivate("focus");
      timers.advance(POPOVER_CLOSE_DELAY_MS - 1);
      expect(closes).to.equal(0);
      timers.advance(1);
      expect(closes).to.equal(1);
      expect(controller.isOpen()).to.equal(false);
    });

    it("keeps the card open while the pointer moves onto the tooltip", () => {
      // Open the card by hovering the trigger.
      const controller = createController();
      controller.activate("hover");
      timers.advance(POPOVER_OPEN_DELAY_MS);

      // Crossing to the tooltip within the grace delay keeps it open.
      controller.deactivate("hover");
      timers.advance(POPOVER_CLOSE_DELAY_MS - 1);
      controller.activate("tooltip");
      timers.advance(POPOVER_CLOSE_DELAY_MS * 2);
      expect(controller.isOpen()).to.equal(true);
      expect(loader.loads).to.have.length(1);

      // Leaving the tooltip closes the card after the grace delay.
      controller.deactivate("tooltip");
      timers.advance(POPOVER_CLOSE_DELAY_MS);
      expect(closes).to.equal(1);
    });

    it("retries a failed card when another source activates it while open", async () => {
      // Open the card with focus and fail its load.
      const controller = createController();
      controller.activate("focus");
      timers.advance(POPOVER_OPEN_DELAY_MS);
      loader.loads[0].resolve({ status: "unavailable" });
      await waitForMicrotask();
      expect(renders).to.deep.equal([{ status: "loading" }, { status: "unavailable" }]);

      // Hovering the focused trigger requests the card again.
      controller.activate("hover");
      expect(loader.loads).to.have.length(2);
      loader.loads[1].resolve(READY);
      await waitForMicrotask();
      expect(renders.at(-1)).to.deep.equal(READY);

      // A ready card is not requested again on later activations.
      controller.deactivate("hover");
      controller.activate("hover");
      expect(loader.loads).to.have.length(2);
    });

    it("does not retry cached unavailable cards while open", async () => {
      // Open the card and resolve it as a cached not-found result.
      const controller = createController();
      controller.activate("focus");
      timers.advance(POPOVER_OPEN_DELAY_MS);
      loader.cached = { status: "unavailable" };
      loader.loads[0].resolve({ status: "unavailable" });
      await waitForMicrotask();

      // Hovering the focused trigger keeps the cached fallback.
      controller.activate("hover");
      expect(loader.loads).to.have.length(1);
      expect(controller.isOpen()).to.equal(true);
    });

    it("cancels pending work and ignores activations after destroy", async () => {
      // Destroy a card while it waits to open.
      const controller = createController();
      controller.activate("hover");
      controller.destroy();
      expect(timers.pendingCount).to.equal(0);

      // Late results and activations have no effect.
      loader.loads[0].resolve(READY);
      await waitForMicrotask();
      controller.activate("hover");
      timers.advance(POPOVER_OPEN_DELAY_MS);
      expect(loader.loads).to.have.length(1);
      expect(renders).to.deep.equal([]);
      expect(controller.isActive()).to.equal(false);
    });
  });

  describe("card bindings", () => {
    let closes;
    let controller;
    let timers;
    let tooltip;
    let trigger;

    beforeEach(() => {
      document.body.innerHTML = `
        <a href="/spain/group/malaga-js" id="trigger">Málaga JS</a>
        <div id="tooltip" role="tooltip"><a>Card link</a></div>
      `;
      trigger = document.getElementById("trigger");
      tooltip = document.getElementById("tooltip");
      closes = 0;
      timers = createManualTimers();
      controller = createCardController({
        close: () => {
          closes += 1;
        },
        item: GROUP,
        loader: { load: () => new Promise(() => {}), peek: () => null },
        render: () => {},
        timers,
      });
    });

    it("opens cards on trigger hover and focus and dismisses them with Escape", () => {
      // Bind the trigger and open its card with the pointer.
      const release = bindExploreCardTrigger(trigger, controller);
      trigger.dispatchEvent(new MouseEvent("mouseenter"));
      timers.advance(POPOVER_OPEN_DELAY_MS);
      expect(controller.isOpen()).to.equal(true);

      // Leaving with the pointer closes it after the grace delay.
      trigger.dispatchEvent(new MouseEvent("mouseleave"));
      timers.advance(POPOVER_CLOSE_DELAY_MS);
      expect(controller.isOpen()).to.equal(false);

      // Focus opens it again and Escape dismisses it without bubbling.
      let bubbledEscapes = 0;
      document.body.addEventListener("keydown", () => {
        bubbledEscapes += 1;
      });
      trigger.focus();
      timers.advance(POPOVER_OPEN_DELAY_MS);
      expect(controller.isOpen()).to.equal(true);
      trigger.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));
      expect(controller.isOpen()).to.equal(false);
      expect(bubbledEscapes).to.equal(0);

      // Escape on an inactive card keeps bubbling to other handlers.
      trigger.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));
      expect(bubbledEscapes).to.equal(1);

      // Releasing the trigger removes its listeners.
      trigger.blur();
      release();
      trigger.dispatchEvent(new MouseEvent("mouseenter"));
      expect(controller.isActive()).to.equal(false);
    });

    it("keeps hovered tooltips open and forwards tooltip clicks to the trigger", () => {
      // Open the card and move the pointer onto the tooltip.
      bindExploreCardTrigger(trigger, controller);
      const release = bindExploreCardTooltip(tooltip, trigger, controller);
      trigger.dispatchEvent(new MouseEvent("mouseenter"));
      timers.advance(POPOVER_OPEN_DELAY_MS);
      trigger.dispatchEvent(new MouseEvent("mouseleave"));
      tooltip.dispatchEvent(new MouseEvent("mouseenter"));
      timers.advance(POPOVER_CLOSE_DELAY_MS * 2);
      expect(controller.isOpen()).to.equal(true);

      // Clicking the tooltip clicks the trigger instead of the card content.
      const triggerClicks = [];
      trigger.addEventListener("click", (event) => {
        triggerClicks.push(event);
        event.preventDefault();
      });
      const click = new MouseEvent("click", { bubbles: true, cancelable: true });
      tooltip.querySelector("a").dispatchEvent(click);
      expect(click.defaultPrevented).to.equal(true);
      expect(triggerClicks).to.have.length(1);

      // Leaving the tooltip closes the card.
      tooltip.dispatchEvent(new MouseEvent("mouseleave"));
      timers.advance(POPOVER_CLOSE_DELAY_MS);
      expect(closes).to.equal(1);

      // Releasing the tooltip removes its listeners.
      release();
      tooltip.querySelector("a").dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      expect(triggerClicks).to.have.length(1);
    });

    it("opens the trigger link in a new tab for new-tab clicks on the tooltip", () => {
      // Bind the tooltip and capture trigger clicks and opened tabs.
      const originalOpen = window.open;
      const openedTabs = [];
      window.open = (...args) => {
        openedTabs.push(args);
        return null;
      };
      const triggerClicks = [];
      trigger.addEventListener("click", (event) => {
        triggerClicks.push(event);
        event.preventDefault();
      });
      bindExploreCardTooltip(tooltip, trigger, controller);

      try {
        // Modifier clicks open the trigger link in a new tab.
        [{ ctrlKey: true }, { metaKey: true }, { shiftKey: true }].forEach((init) => {
          const click = new MouseEvent("click", { bubbles: true, button: 0, cancelable: true, ...init });
          tooltip.querySelector("a").dispatchEvent(click);
          expect(click.defaultPrevented).to.equal(true);
        });

        // A middle click opens it too; other auxiliary buttons are ignored.
        tooltip.dispatchEvent(new MouseEvent("auxclick", { bubbles: true, button: 1, cancelable: true }));
        tooltip.dispatchEvent(new MouseEvent("auxclick", { bubbles: true, button: 2, cancelable: true }));

        // Alt clicks open nothing.
        tooltip.dispatchEvent(new MouseEvent("click", { altKey: true, bubbles: true, cancelable: true }));

        // Only plain clicks reach the trigger.
        const triggerUrl = trigger.href;
        expect(openedTabs).to.deep.equal([
          [triggerUrl, "_blank", "noopener"],
          [triggerUrl, "_blank", "noopener"],
          [triggerUrl, "_blank", "noopener"],
          [triggerUrl, "_blank", "noopener"],
        ]);
        expect(triggerClicks).to.have.length(0);
      } finally {
        // Restore the mocked window.open.
        window.open = originalOpen;
      }
    });
  });

  describe("card tooltip sync", () => {
    it("describes the trigger with a non-interactive tooltip", () => {
      // Render a ready card with a link inside the tooltip.
      document.body.innerHTML = `
        <a href="/spain/group/malaga-js" id="trigger">Málaga JS</a>
        <div id="tooltip"><a href="/spain/group/malaga-js">Card link</a></div>
      `;
      const trigger = document.getElementById("trigger");
      const tooltip = document.getElementById("tooltip");
      syncExploreCardTooltip({ result: READY_CARD, tooltip, tooltipId: "card-1", trigger });

      // The tooltip describes the trigger without focusable links.
      expect(tooltip.id).to.equal("card-1");
      expect(tooltip.getAttribute("role")).to.equal("tooltip");
      expect(tooltip.getAttribute("aria-busy")).to.equal("false");
      expect(tooltip.querySelector("a[href]")).to.equal(null);
      expect(trigger.getAttribute("aria-describedby")).to.equal("card-1");

      // Loading cards are marked busy.
      syncExploreCardTooltip({ result: { status: CARD_STATUS.loading }, tooltip, tooltipId: "card-1", trigger });
      expect(tooltip.getAttribute("aria-busy")).to.equal("true");
    });
  });

  it("detects unmodified primary button clicks", () => {
    expect(isPlainLeftClick(new MouseEvent("click", { button: 0 }))).to.equal(true);
    [{ altKey: true }, { ctrlKey: true }, { metaKey: true }, { shiftKey: true }, { button: 1 }].forEach((init) => {
      expect(isPlainLeftClick(new MouseEvent("click", { button: 0, ...init }))).to.equal(false);
    });
    expect(isPlainLeftClick(undefined)).to.equal(false);
  });
});
