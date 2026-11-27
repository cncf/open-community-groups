import { expect } from "@open-wc/testing";

import { VENDOR_BUNDLES } from "/__ocg__/vendor-bundles.js";
import {
  initializeGroupDashboardTabModules,
  resolveGroupDashboardModuleGroup,
} from "/static/js/dashboard/group/tab-modules.js";
import { createDeferred, waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

/** Loads the vendored HTMX script once into the test document. */
const loadBundledHtmx = async () => {
  if (!window.htmx) {
    await new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.addEventListener("load", resolve, { once: true });
      script.addEventListener("error", reject, { once: true });
      script.src = `/ocg-server${VENDOR_BUNDLES.htmx}`;
      document.head.append(script);
    });
  }
  return window.htmx;
};

/** Creates a controllable XMLHttpRequest mock for real-HTMX tests. */
const installMockXhr = () => {
  const OriginalXhr = window.XMLHttpRequest;
  const instances = [];

  class MockXhr {
    constructor() {
      this.headers = {};
      this.listeners = {};
      this.readyState = 0;
      this.status = 0;
      this.response = "";
      this.responseText = "";
      this.upload = { addEventListener() {} };
      instances.push(this);
    }

    open(method, url) {
      this.method = method;
      this.url = url;
    }

    overrideMimeType() {}

    setRequestHeader(name, value) {
      this.headers[name] = value;
    }

    getAllResponseHeaders() {
      return "content-type: text/html\r\n";
    }

    getResponseHeader(name) {
      return name.toLowerCase() === "content-type" ? "text/html" : null;
    }

    addEventListener(type, listener) {
      this.listeners[type] ||= [];
      this.listeners[type].push(listener);
    }

    send() {}

    complete(html = "<p>Swapped</p>") {
      this.readyState = 4;
      this.status = 200;
      this.response = html;
      this.responseText = html;
      this.onload?.();
      this.listeners.load?.forEach((listener) => listener());
    }
  }

  window.XMLHttpRequest = MockXhr;
  return {
    instances,
    restore() {
      window.XMLHttpRequest = OriginalXhr;
    },
  };
};

describe("group dashboard tab modules loader", () => {
  let layout;
  let target;
  let spinner;
  let cleanup;

  const stopBubblingToWindow = (event) => event.stopPropagation();

  beforeEach(() => {
    resetDom();
    document.body.innerHTML = `
      <div id="dashboard-layout" data-ocg-selected-group-id="group-1">
        <div id="dashboard-spinner"></div>
        <div id="dashboard-content"></div>
      </div>
    `;
    layout = document.getElementById("dashboard-layout");
    target = document.getElementById("dashboard-content");
    spinner = document.getElementById("dashboard-spinner");
    // Isolate synthetic events from the module's auto-initialized window listener.
    document.addEventListener("htmx:confirm", stopBubblingToWindow);
    cleanup = null;
  });

  afterEach(() => {
    document.removeEventListener("htmx:confirm", stopBubblingToWindow);
    cleanup?.();
    resetDom();
  });

  it("maps group dashboard tab queries and subpaths to their lazy module groups", () => {
    // Verify top-level tabs and default settings tab.
    expect(resolveGroupDashboardModuleGroup("/dashboard/group")).to.equal("settings");
    expect(resolveGroupDashboardModuleGroup("/dashboard/group?tab=settings")).to.equal("settings");
    expect(resolveGroupDashboardModuleGroup("/dashboard/group?tab=events&events_tab=past")).to.equal(
      "events-list",
    );
    expect(resolveGroupDashboardModuleGroup("/dashboard/group?tab=check-in")).to.equal("check-in");
    expect(resolveGroupDashboardModuleGroup("/dashboard/group?tab=artwork")).to.equal("badges-artwork");
    expect(resolveGroupDashboardModuleGroup("/dashboard/group?tab=awards")).to.equal("badges");
    expect(resolveGroupDashboardModuleGroup("/dashboard/group?tab=logs")).to.equal("audit-logs");
    expect(resolveGroupDashboardModuleGroup("/dashboard/group?tab=analytics")).to.equal(null);

    // Verify nested event, sponsor, survey, and inbox partial endpoints.
    expect(resolveGroupDashboardModuleGroup("/dashboard/group/events/add")).to.equal("event-add");
    expect(resolveGroupDashboardModuleGroup("/dashboard/group/events/evt-1/update")).to.equal("event-update");
    expect(resolveGroupDashboardModuleGroup("/dashboard/group/events/evt-1/attendees?sort=name")).to.equal(
      "attendees",
    );
    expect(resolveGroupDashboardModuleGroup("/dashboard/group/events/evt-1/submissions")).to.equal(
      "event-submissions",
    );
    expect(resolveGroupDashboardModuleGroup("/dashboard/group/events/evt-1/invitation-requests")).to.equal(
      "event-requests",
    );
    expect(resolveGroupDashboardModuleGroup("/dashboard/group/events/evt-1/waitlist")).to.equal(
      "event-requests",
    );
    expect(
      resolveGroupDashboardModuleGroup("/dashboard/group/events/evt-1/surveys/sur-1/responses"),
    ).to.equal("survey-responses");
    expect(resolveGroupDashboardModuleGroup("/dashboard/group/sponsors/add")).to.equal("sponsor-form");
    expect(resolveGroupDashboardModuleGroup("/dashboard/group/sponsors/sp-1/update")).to.equal(
      "sponsor-form",
    );

    // Verify non-group routes and invalid inputs return null.
    expect(resolveGroupDashboardModuleGroup("/dashboard/community?tab=groups")).to.equal(null);
    expect(resolveGroupDashboardModuleGroup("/dashboard/group/events/evt-1/analytics")).to.equal(null);
    expect(resolveGroupDashboardModuleGroup("")).to.equal(null);
  });

  it("defers htmx:confirm with spinner feedback until loaded, then passes through on repeat visits", async () => {
    // Configure a deferred loader to observe spinner state and when issueRequest runs.
    const deferred = createDeferred();
    const loadedCalls = [];
    const loaded = new Set();
    cleanup = initializeGroupDashboardTabModules(layout, {
      loaded,
      loadGroup: (groupKey) => {
        loadedCalls.push(groupKey);
        return deferred.promise;
      },
    });

    const button = document.createElement("button");
    layout.append(button);
    const issued = [];
    const firstEvent = new CustomEvent("htmx:confirm", {
      bubbles: true,
      cancelable: true,
      detail: {
        elt: button,
        issueRequest: (skipConfirmation) => issued.push(skipConfirmation),
        path: "/dashboard/group/events/add",
        target,
        verb: "get",
      },
    });

    // Dispatch the first navigation and verify it pauses and marks the preload indicator.
    button.dispatchEvent(firstEvent);
    expect(firstEvent.defaultPrevented).to.equal(true);
    expect(loadedCalls).to.deep.equal(["event-add"]);
    expect(issued).to.deep.equal([]);
    expect(spinner.hasAttribute("data-ocg-preloading")).to.equal(true);
    expect(spinner.classList.contains("htmx-request")).to.equal(false);

    deferred.resolve();
    await waitForMicrotask();
    await waitForMicrotask();

    expect(issued).to.deep.equal([true]);
    expect(loaded.has("event-add")).to.equal(true);
    expect(spinner.hasAttribute("data-ocg-preloading")).to.equal(false);

    // Dispatch a second navigation to the same group and verify it proceeds synchronously.
    const secondEvent = new CustomEvent("htmx:confirm", {
      bubbles: true,
      cancelable: true,
      detail: {
        elt: button,
        issueRequest: (skipConfirmation) => issued.push(skipConfirmation),
        path: "/dashboard/group/events/add",
        target,
        verb: "get",
      },
    });
    button.dispatchEvent(secondEvent);
    expect(secondEvent.defaultPrevented).to.equal(false);
    expect(loadedCalls).to.deep.equal(["event-add"]);
  });

  it("never bypasses a document-level htmx:confirm guard such as unsaved survey changes", async () => {
    // Wire a document-level guard (like event-surveys.js) ahead of the window-level preloader.
    document.removeEventListener("htmx:confirm", stopBubblingToWindow);
    const deferred = createDeferred();
    const loadedCalls = [];
    const loaded = new Set();
    const guardHandler = (event) => {
      event.preventDefault();
    };

    const windowTarget = document.createElement("div");
    windowTarget.append(layout);
    document.body.append(windowTarget);
    // Simulate document running before window in the bubble chain.
    layout.addEventListener("htmx:confirm", guardHandler);
    cleanup = initializeGroupDashboardTabModules(windowTarget, {
      loaded,
      loadGroup: (groupKey) => {
        loadedCalls.push(groupKey);
        return deferred.promise;
      },
    });

    const button = document.createElement("button");
    layout.append(button);
    const issued = [];
    const event = new CustomEvent("htmx:confirm", {
      bubbles: true,
      cancelable: true,
      detail: {
        elt: button,
        issueRequest: (skipConfirmation) => issued.push(skipConfirmation),
        path: "/dashboard/group?tab=sponsors",
        target: layout,
        verb: "get",
      },
    });

    try {
      button.dispatchEvent(event);
      deferred.resolve();
      await waitForMicrotask();
      await waitForMicrotask();

      // The module warmed in the background, but the guarded request was never issued.
      expect(loadedCalls).to.deep.equal(["sponsors-list"]);
      expect(loaded.has("sponsors-list")).to.equal(true);
      expect(issued).to.deep.equal([]);
    } finally {
      layout.removeEventListener("htmx:confirm", guardHandler);
      document.addEventListener("htmx:confirm", stopBubblingToWindow);
    }
  });

  it("ignores requests outside the group dashboard shell, non-GET requests, hx-confirm, and htmx.ajax promises", async () => {
    // Wire the loader with a spy.
    const loadedCalls = [];
    cleanup = initializeGroupDashboardTabModules(layout, {
      loaded: new Set(),
      loadGroup: (groupKey) => {
        loadedCalls.push(groupKey);
        return Promise.resolve();
      },
    });

    const postEvent = new CustomEvent("htmx:confirm", {
      bubbles: true,
      cancelable: true,
      detail: {
        elt: layout,
        issueRequest: () => {},
        path: "/dashboard/group/events/add",
        target,
        verb: "post",
      },
    });
    const confirmEvent = new CustomEvent("htmx:confirm", {
      bubbles: true,
      cancelable: true,
      detail: {
        elt: layout,
        issueRequest: () => {},
        path: "/dashboard/group/events/add",
        question: "Continue?",
        target,
        verb: "get",
      },
    });
    const ajaxEvent = new CustomEvent("htmx:confirm", {
      bubbles: true,
      cancelable: true,
      detail: {
        elt: layout,
        etc: { returnPromise: true },
        issueRequest: () => {},
        path: "/dashboard/group",
        target: document.body,
        verb: "get",
      },
    });

    layout.dispatchEvent(postEvent);
    layout.dispatchEvent(confirmEvent);
    layout.dispatchEvent(ajaxEvent);

    expect(postEvent.defaultPrevented).to.equal(false);
    expect(confirmEvent.defaultPrevented).to.equal(false);
    expect(ajaxEvent.defaultPrevented).to.equal(false);
    expect(loadedCalls).to.deep.equal(["settings"]);

    // Removing the group dashboard context disables interception after navigating away.
    layout.removeAttribute("data-ocg-selected-group-id");
    const leftDashboardEvent = new CustomEvent("htmx:confirm", {
      bubbles: true,
      cancelable: true,
      detail: {
        elt: layout,
        issueRequest: () => {},
        path: "/dashboard/group?tab=members",
        target,
        verb: "get",
      },
    });
    layout.dispatchEvent(leftDashboardEvent);
    expect(leftDashboardEvent.defaultPrevented).to.equal(false);
    expect(loadedCalls).to.deep.equal(["settings"]);
  });

  it("defers real hx-get clicks until preload resolves and respects document guards before and during preload", async () => {
    // Load real vendored HTMX and test document-guard-before-preloader ordering with real clicks.
    const htmxInstance = await loadBundledHtmx();
    const xhr = installMockXhr();
    document.removeEventListener("htmx:confirm", stopBubblingToWindow);

    let dirtySurvey = false;
    const documentGuard = (event) => {
      if (dirtySurvey) {
        event.preventDefault();
      }
    };
    document.addEventListener("htmx:confirm", documentGuard);

    const sponsorsDeferred = createDeferred();
    const membersDeferred = createDeferred();
    const loaded = new Set();
    cleanup = initializeGroupDashboardTabModules(document, {
      loaded,
      loadGroup: (groupKey) =>
        groupKey === "sponsors-list" ? sponsorsDeferred.promise : membersDeferred.promise,
    });
    // Stop bubbling to the auto-initialized window listener after the test preloader runs.
    document.addEventListener("htmx:confirm", stopBubblingToWindow);

    const sponsorsButton = document.createElement("button");
    sponsorsButton.setAttribute("hx-get", "/dashboard/group?tab=sponsors");
    sponsorsButton.setAttribute("hx-target", "#dashboard-content");
    const membersButton = document.createElement("button");
    membersButton.setAttribute("hx-get", "/dashboard/group?tab=members");
    membersButton.setAttribute("hx-target", "#dashboard-content");
    layout.append(sponsorsButton, membersButton);
    htmxInstance.process(layout);

    try {
      // Case 1: Clean survey, click Sponsors, then mark the survey dirty while preload is in flight.
      sponsorsButton.click();
      expect(xhr.instances).to.have.length(0);
      dirtySurvey = true;
      sponsorsDeferred.resolve();
      await waitForMicrotask();
      await waitForMicrotask();
      await waitForMicrotask();

      // Re-running confirmation caught the edit made during preload, so no XHR was sent.
      expect(xhr.instances).to.have.length(0);
      expect(loaded.has("sponsors-list")).to.equal(true);

      // Case 2: Clean survey again, click Members, resolve preload, and verify one XHR swaps the target.
      dirtySurvey = false;
      membersButton.click();
      expect(xhr.instances).to.have.length(0);
      membersDeferred.resolve();
      await waitForMicrotask();
      await waitForMicrotask();
      await waitForMicrotask();

      expect(xhr.instances).to.have.length(1);
      expect(xhr.instances[0].url).to.equal("/dashboard/group?tab=members");
      xhr.instances[0].complete("<div>Members loaded</div>");
      expect(target.textContent).to.equal("Members loaded");
    } finally {
      document.removeEventListener("htmx:confirm", documentGuard);
      xhr.restore();
    }
  });

  it("keeps real htmx.ajax promises pending until the XHR settles", async () => {
    // Load the real vendored HTMX and intercept XMLHttpRequest so no network call leaves the test.
    const htmxInstance = await loadBundledHtmx();
    const xhr = installMockXhr();
    const deferred = createDeferred();
    let ajaxSettled = false;

    cleanup = initializeGroupDashboardTabModules(layout, {
      loaded: new Set(),
      loadGroup: () => deferred.promise,
    });

    try {
      const ajaxPromise = htmxInstance
        .ajax("GET", "/dashboard/group", { source: layout, target })
        .then(() => {
          ajaxSettled = true;
        });
      await waitForMicrotask();

      // The real XHR is issued immediately and the promise stays pending while both XHR and preload run.
      expect(xhr.instances).to.have.length(1);
      expect(ajaxSettled).to.equal(false);

      xhr.instances[0].complete("<div>Loaded</div>");
      await ajaxPromise;
      expect(ajaxSettled).to.equal(true);
      expect(target.textContent).to.equal("Loaded");
    } finally {
      xhr.restore();
      deferred.resolve();
    }
  });

  it("cancels inner preloads on outer navigation without letting inner refreshes cancel outer clicks or clear HTMX spinner", async () => {
    // Scenario 1: An outer tab click (#dashboard-layout) cancels a pending inner preload (#dashboard-content).
    const innerDeferred = createDeferred();
    const outerDeferred = createDeferred();
    cleanup = initializeGroupDashboardTabModules(layout, {
      loaded: new Set(),
      loadGroup: (groupKey) =>
        groupKey === "event-add" ? innerDeferred.promise : outerDeferred.promise,
    });

    const issued = [];
    const dispatchNavigation = (path, navTarget, elt = layout) => {
      const event = new CustomEvent("htmx:confirm", {
        bubbles: true,
        cancelable: true,
        detail: {
          elt,
          issueRequest: () => issued.push(path),
          path,
          target: navTarget,
          verb: "get",
        },
      });
      layout.dispatchEvent(event);
    };

    dispatchNavigation("/dashboard/group/events/add", target);
    dispatchNavigation("/dashboard/group?tab=members", layout);

    outerDeferred.resolve();
    await waitForMicrotask();
    await waitForMicrotask();
    innerDeferred.resolve();
    await waitForMicrotask();
    await waitForMicrotask();

    expect(issued).to.deep.equal(["/dashboard/group?tab=members"]);

    // Scenario 2: An inner background refresh (#dashboard-content) must NOT cancel an outer tab click (#dashboard-layout).
    const membersRefreshDeferred = createDeferred();
    cleanup();
    cleanup = initializeGroupDashboardTabModules(layout, {
      loaded: new Set(["sponsors-list"]),
      loadGroup: () => membersRefreshDeferred.promise,
    });
    issued.length = 0;

    dispatchNavigation("/dashboard/group?tab=members", layout);
    // Simulate a background refresh targeting #dashboard-content while #dashboard-layout is preloading.
    dispatchNavigation("/dashboard/group/sponsors", target);
    // Simulate HTMX marking the spinner active for another request.
    spinner.classList.add("htmx-request");

    membersRefreshDeferred.resolve();
    await waitForMicrotask();
    await waitForMicrotask();

    expect(issued).to.deep.equal(["/dashboard/group?tab=members"]);
    // Completing preload clears only data-ocg-preloading, never HTMX's htmx-request class.
    expect(spinner.hasAttribute("data-ocg-preloading")).to.equal(false);
    expect(spinner.classList.contains("htmx-request")).to.equal(true);

    // Scenario 3: A navigation whose trigger element disconnects before resolution is dropped.
    const triggerDeferred = createDeferred();
    cleanup();
    cleanup = initializeGroupDashboardTabModules(layout, {
      loaded: new Set(),
      loadGroup: () => triggerDeferred.promise,
    });
    issued.length = 0;
    const transientButton = document.createElement("button");
    layout.append(transientButton);
    dispatchNavigation("/dashboard/group?tab=sponsors", layout, transientButton);
    transientButton.remove();

    triggerDeferred.resolve();
    await waitForMicrotask();
    await waitForMicrotask();

    expect(issued).to.deep.equal([]);
  });

  it("continues the HTMX request once if preloading fails without looping", async () => {
    // Suppress expected error logging while simulating a transient preload error.
    const originalConsoleError = console.error;
    console.error = () => {};

    try {
      const loaded = new Set();
      let loadCalls = 0;
      cleanup = initializeGroupDashboardTabModules(layout, {
        loaded,
        loadGroup: () => {
          loadCalls += 1;
          return Promise.reject(new Error("Network error"));
        },
      });

      const issued = [];
      const event = new CustomEvent("htmx:confirm", {
        bubbles: true,
        cancelable: true,
        detail: {
          elt: layout,
          issueRequest: (skipConfirmation) => issued.push(skipConfirmation),
          path: "/dashboard/group?tab=members",
          target,
          verb: "get",
        },
      });
      layout.dispatchEvent(event);
      await waitForMicrotask();
      await waitForMicrotask();
      await waitForMicrotask();

      expect(loadCalls).to.equal(1);
      expect(issued).to.deep.equal([true]);
      expect(loaded.has("members")).to.equal(false);
      expect(spinner.hasAttribute("data-ocg-preloading")).to.equal(false);
    } finally {
      console.error = originalConsoleError;
    }
  });
});
