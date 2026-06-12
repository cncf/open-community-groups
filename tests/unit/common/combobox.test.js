import { expect } from "@open-wc/testing";

import { ComboboxController } from "/static/js/common/combobox.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("common combobox", () => {
  let host;
  let controller;

  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    controller?.hostDisconnected();
    controller = null;
    host = null;
  });

  // Create a connected host element with the minimal reactive controller surface.
  const createController = (options = {}) => {
    host = document.createElement("div");
    host.requestUpdateCalls = 0;
    host.requestUpdate = () => {
      host.requestUpdateCalls += 1;
    };
    host.addController = () => {};
    document.body.append(host);

    controller = new ComboboxController(host, {
      getItemCount: () => 3,
      onSelect: () => {},
      ...options,
    });
    controller.hostConnected();
    return controller;
  };

  // Dispatch a cancelable keydown event on the host element.
  const pressKey = (key) => {
    const event = new KeyboardEvent("keydown", { key, cancelable: true, bubbles: true });
    host.dispatchEvent(event);
    return event;
  };

  it("opens, closes and toggles while honoring the host guards", () => {
    // Track lifecycle hooks invoked by open and close transitions.
    let opened = 0;
    let closed = 0;
    let blocked = false;
    let openable = true;
    createController({
      isInteractionBlocked: () => blocked,
      canOpen: () => openable,
      onOpen: () => {
        opened += 1;
      },
      onClose: () => {
        closed += 1;
      },
    });

    // Blocked hosts ignore open and toggle requests.
    blocked = true;
    controller.toggle();
    expect(controller.isOpen).to.equal(false);

    // The canOpen guard keeps the dropdown closed.
    blocked = false;
    openable = false;
    controller.open();
    expect(controller.isOpen).to.equal(false);

    // The dropdown opens, resets the highlight and runs the open hook.
    openable = true;
    controller.activeIndex = 2;
    controller.toggle();
    expect(controller.isOpen).to.equal(true);
    expect(controller.activeIndex).to.equal(null);
    expect(opened).to.equal(1);

    // Toggling again closes the dropdown and runs the close hook.
    controller.toggle();
    expect(controller.isOpen).to.equal(false);
    expect(closed).to.equal(1);
    expect(host.requestUpdateCalls).to.be.greaterThan(0);
  });

  it("clears the query on toggle only for single-select style hosts", () => {
    // Single-select style hosts reset the query on open and close.
    createController({ resetQueryOnToggle: true });
    controller.setQuery("plat");
    controller.open();
    expect(controller.query).to.equal("");
    controller.setQuery("cloud");
    controller.close();
    expect(controller.query).to.equal("");
    controller.hostDisconnected();

    // Multi-select style hosts keep the query across open and close.
    createController({});
    controller.setQuery("design");
    controller.open();
    expect(controller.query).to.equal("design");
    controller.close();
    expect(controller.query).to.equal("design");
  });

  it("supports keyboard navigation, selection and escape", () => {
    // Track options selected through Enter.
    const selections = [];
    let itemCount = 3;
    createController({
      getItemCount: () => itemCount,
      onSelect: (index) => {
        selections.push(index);
      },
    });

    // Closed dropdowns ignore keyboard navigation.
    pressKey("ArrowDown");
    expect(controller.activeIndex).to.equal(null);

    // Arrow keys move the highlight with wraparound.
    controller.open();
    pressKey("ArrowDown");
    expect(controller.activeIndex).to.equal(0);
    pressKey("ArrowUp");
    expect(controller.activeIndex).to.equal(2);
    pressKey("ArrowDown");
    expect(controller.activeIndex).to.equal(0);

    // Enter selects the highlighted option.
    pressKey("Enter");
    expect(selections).to.deep.equal([0]);

    // Empty result lists ignore navigation and selection keys.
    itemCount = 0;
    const ignoredEvent = pressKey("ArrowDown");
    expect(ignoredEvent.defaultPrevented).to.equal(false);

    // Escape closes the dropdown even with no results.
    pressKey("Escape");
    expect(controller.isOpen).to.equal(false);
    expect(controller.activeIndex).to.equal(null);
  });

  it("ignores keyboard events when blocked or already handled", () => {
    // Track selections while the host toggles its blocked state.
    const selections = [];
    let blocked = false;
    createController({
      isInteractionBlocked: () => blocked,
      onSelect: (index) => {
        selections.push(index);
      },
    });
    controller.open();
    controller.activeIndex = 1;

    // Blocked hosts ignore selection keys.
    blocked = true;
    pressKey("Enter");
    expect(selections).to.deep.equal([]);

    // Events already handled elsewhere are not processed again.
    blocked = false;
    const handledEvent = new KeyboardEvent("keydown", {
      key: "Enter",
      cancelable: true,
      bubbles: true,
    });
    handledEvent.preventDefault();
    host.dispatchEvent(handledEvent);
    expect(selections).to.deep.equal([]);
  });

  it("closes when clicking outside the host element", () => {
    // Mount an unrelated element to click outside the host.
    createController({});
    const outside = document.createElement("button");
    document.body.append(outside);
    controller.open();

    // Clicks inside the host keep the dropdown open.
    host.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(controller.isOpen).to.equal(true);

    // Clicks outside the host close the dropdown.
    outside.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(controller.isOpen).to.equal(false);
  });

  it("debounces search updates and cancels them on close", async () => {
    // Track scheduled search updates.
    let updates = 0;
    createController({});

    // Replacing a pending update keeps only the latest callback.
    controller.scheduleSearchUpdate(() => {
      updates += 1;
    }, 5);
    controller.scheduleSearchUpdate(() => {
      updates += 1;
    }, 5);
    await new Promise((resolve) => setTimeout(resolve, 15));
    expect(updates).to.equal(1);

    // Closing the dropdown cancels any pending search update.
    controller.scheduleSearchUpdate(() => {
      updates += 1;
    }, 5);
    controller.close();
    await new Promise((resolve) => setTimeout(resolve, 15));
    expect(updates).to.equal(1);
  });

  it("removes listeners when the host disconnects", async () => {
    // Open the dropdown so the outside-click listener is attached.
    createController({});
    controller.open();
    controller.hostDisconnected();

    // Disconnected hosts ignore keyboard events and outside clicks.
    controller.isOpen = true;
    pressKey("ArrowDown");
    expect(controller.activeIndex).to.equal(null);
    document.body.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    await waitForMicrotask();
    expect(controller.isOpen).to.equal(true);
  });
});
