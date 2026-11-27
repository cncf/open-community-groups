import { expect } from "@open-wc/testing";

import {
  bindOutsideClickListener,
  buildElementId,
  closestElement,
  closestElementWithinRoot,
  ensureElementId,
  focusElementById,
  getElementById,
  initializeMatchingRoots,
  initializeOnReady,
  initializeOnReadyAndHtmxLoad,
  isDatasetReady,
  isElementHidden,
  isOutsideElementEvent,
  loadScriptOnce,
  loadStylesheetOnce,
  markDatasetReady,
  setElementHidden,
  toggleElementHidden,
} from "/static/js/common/dom.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom, trackAddedEventListeners } from "/tests/unit/test-utils/dom.js";

describe("common dom", () => {
  const exampleScriptSrc = "data:text/javascript,window.__ocgDomTestScriptLoaded%3Dtrue";
  const exampleStylesheetHref = "data:text/css,.ocg-dom-test{}";

  beforeEach(() => {
    resetDom();
    document.head.querySelectorAll(`script[src="${exampleScriptSrc}"]`).forEach((script) => script.remove());
    document.head
      .querySelectorAll(`link[rel="stylesheet"][href="${exampleStylesheetHref}"], link[rel="stylesheet"][href^="/static/css/styles"]`)
      .forEach((link) => link.remove());
  });

  afterEach(() => {
    resetDom();
    document.head.querySelectorAll(`script[src="${exampleScriptSrc}"]`).forEach((script) => script.remove());
    document.head
      .querySelectorAll(`link[rel="stylesheet"][href="${exampleStylesheetHref}"], link[rel="stylesheet"][href^="/static/css/styles"]`)
      .forEach((link) => link.remove());
  });

  it("builds stable element ids", () => {
    // Verify a representative namespace and control suffix use the shared separator.
    expect(buildElementId("community-selector", "search-input")).to.equal("community-selector-search-input");
  });

  it("queries ids from document and element roots", () => {
    // Build the DOM fixture with a nested button.
    document.body.innerHTML = `
      <section id="root">
        <button id="save-button">Save</button>
      </section>
    `;

    // Read the root element used for subtree queries.
    const root = document.getElementById("root");

    // The helper finds ids from document, element, and direct matching roots.
    expect(getElementById(document, "save-button")?.textContent).to.equal("Save");
    expect(getElementById(root, "save-button")?.textContent).to.equal("Save");
    expect(getElementById(root, "root")).to.equal(root);
    expect(getElementById(root, "missing")).to.equal(null);
  });

  it("queries special-character ids from element roots", () => {
    // Build the DOM fixture with ids that are not valid raw CSS id selectors.
    document.body.innerHTML = `
      <section id="root">
        <button id="ticket:price.window">Ticket price</button>
      </section>
    `;

    // Read the root element used for special-character subtree queries.
    const root = document.getElementById("root");

    // The helper finds ids without relying on raw #id selector syntax.
    expect(getElementById(root, "ticket:price.window")?.textContent).to.equal("Ticket price");
  });

  it("initializes current, htmx-loaded, and htmx-restored content", () => {
    // Track the roots passed to the lifecycle initializer.
    const listenerTracker = trackAddedEventListeners();
    const initializedRoots = [];
    const initializedContexts = [];

    try {
      // Initialize once for the current document.
      initializeOnReadyAndHtmxLoad((root, context = {}) => {
        initializedRoots.push(root);
        initializedContexts.push(context);
      });

      // Dispatch the lifecycle event used by swapped content.
      const fragment = document.createElement("section");
      document.body.append(fragment);
      fragment.dispatchEvent(new CustomEvent("htmx:load", { bubbles: true }));
      document.dispatchEvent(new CustomEvent("htmx:historyRestore"));

      // Verify current, swapped, and restored roots are initialized.
      expect(initializedRoots).to.deep.equal([document, fragment, document]);
      expect(initializedContexts).to.deep.equal([{}, {}, { historyRestore: true }]);
    } finally {
      listenerTracker.restore();
    }
  });

  it("initializes once when the document is ready", () => {
    // Track the ready initializer callback.
    let initialized = false;

    // Initialize immediately because the test document is already ready.
    initializeOnReady(() => {
      initialized = true;
    });

    // Verify the ready initializer ran.
    expect(initialized).to.equal(true);
  });

  it("initializes matching root elements and descendants", () => {
    // Build nested declarative roots.
    document.body.innerHTML = `
      <section id="root" data-page-root>
        <div data-page-root id="child"></div>
      </section>
    `;
    const initializedIds = [];

    // Initialize the matching root and matching descendants.
    initializeMatchingRoots(document.getElementById("root"), "[data-page-root]", (element) => {
      initializedIds.push(element.id);
    });

    // Verify both matching roots were initialized.
    expect(initializedIds).to.deep.equal(["root", "child"]);
  });

  it("marks dataset readiness once", () => {
    // Build the element that owns a behavior-ready flag.
    const element = document.createElement("section");

    // The helper marks the element only the first time.
    expect(isDatasetReady(element, "behaviorReady")).to.equal(false);
    expect(markDatasetReady(element, "behaviorReady")).to.equal(true);
    expect(isDatasetReady(element, "behaviorReady")).to.equal(true);
    expect(markDatasetReady(element, "behaviorReady")).to.equal(false);

    // Missing elements are treated as not markable.
    expect(markDatasetReady(null, "behaviorReady")).to.equal(false);
  });

  it("sets element hidden state", () => {
    // Build the element that owns the shared hidden class.
    const element = document.createElement("section");

    // The helper applies and removes the hidden state.
    setElementHidden(element, true);
    expect(element.classList.contains("hidden")).to.equal(true);
    setElementHidden(element, false);
    expect(element.classList.contains("hidden")).to.equal(false);

    // Missing elements are ignored.
    expect(() => setElementHidden(null, true)).not.to.throw();
  });

  it("reads element hidden state", () => {
    // Build the element that owns the shared hidden class.
    const element = document.createElement("section");

    // The helper reports the current hidden state.
    expect(isElementHidden(element)).to.equal(false);
    element.classList.add("hidden");
    expect(isElementHidden(element)).to.equal(true);

    // Missing elements are treated as visible.
    expect(isElementHidden(null)).to.equal(false);
  });

  it("toggles element hidden state", () => {
    // Build the element that owns the shared hidden class.
    const element = document.createElement("section");

    // The helper flips the current hidden state.
    toggleElementHidden(element);
    expect(isElementHidden(element)).to.equal(true);
    toggleElementHidden(element);
    expect(isElementHidden(element)).to.equal(false);

    // Missing elements are ignored.
    expect(() => toggleElementHidden(null)).not.to.throw();
  });

  it("ensures element ids", () => {
    // Build the element that needs a stable id for imperative behavior.
    const element = document.createElement("button");

    // The helper assigns a fallback id only when the element has none.
    expect(ensureElementId(element, "fallback-button")).to.equal("fallback-button");
    expect(element.id).to.equal("fallback-button");
    expect(ensureElementId(element, "other-button")).to.equal("fallback-button");

    // Missing elements return an empty id.
    expect(ensureElementId(null, "missing-button")).to.equal("");
  });

  it("focuses elements by id", () => {
    // Build the focusable element.
    document.body.innerHTML = '<input id="name-input" value="Open Community Groups">';
    const input = getElementById(document, "name-input");

    // The helper focuses and optionally selects text.
    expect(focusElementById(document, "name-input")).to.equal(input);
    expect(document.activeElement).to.equal(input);
    focusElementById(document, "name-input", { select: true });
    expect(input.selectionStart).to.equal(0);
    expect(input.selectionEnd).to.equal(input.value.length);

    // Missing elements are ignored.
    expect(focusElementById(document, "missing-input")).to.equal(null);
  });

  it("finds closest elements from event targets", () => {
    // Build nested elements for closest lookups.
    document.body.innerHTML = `
      <section id="root">
        <button id="action-button" data-action>
          <span id="action-label">Open</span>
        </button>
      </section>
      <section id="other-root"></section>
    `;

    // Resolve the lookup targets.
    const label = document.getElementById("action-label");
    const root = document.getElementById("root");
    const otherRoot = document.getElementById("other-root");

    // The helper finds matches and respects scoped roots.
    expect(closestElement(label, "[data-action]")?.id).to.equal("action-button");
    expect(closestElement(label.firstChild, "[data-action]")).to.equal(null);
    expect(closestElementWithinRoot(label, "[data-action]", root)?.id).to.equal("action-button");
    expect(closestElementWithinRoot(label, "[data-action]", otherRoot)).to.equal(null);
  });

  it("detects and binds outside element clicks", () => {
    // Build the DOM fixture with inside and outside click targets.
    document.body.innerHTML = `
      <section id="root">
        <button id="inside-button">Inside</button>
      </section>
      <button id="outside-button">Outside</button>
    `;
    const root = getElementById(document, "root");
    const insideButton = getElementById(document, "inside-button");
    const outsideButton = getElementById(document, "outside-button");
    let insideResult = null;
    let outsideResult = null;
    let outsideClickCount = 0;

    // Inspect real click events to verify inside and outside detection.
    const recordInsideClick = (event) => {
      insideResult = isOutsideElementEvent(event, root);
    };
    document.addEventListener("click", recordInsideClick, { once: true });
    insideButton.click();
    const recordOutsideClick = (event) => {
      outsideResult = isOutsideElementEvent(event, root);
    };
    document.addEventListener("click", recordOutsideClick, { once: true });
    outsideButton.click();

    // Bind the outside click callback and verify cleanup removes it.
    const cleanup = bindOutsideClickListener(root, () => {
      outsideClickCount += 1;
    });
    insideButton.click();
    outsideButton.click();
    cleanup();
    outsideButton.click();

    expect(insideResult).to.equal(false);
    expect(outsideResult).to.equal(true);
    expect(outsideClickCount).to.equal(1);
  });

  it("resolves immediately when the script is already loaded", async () => {
    // Track whether the loader checks the provided library predicate.
    let checked = false;

    // Resolve the loader through the already-loaded path.
    await loadScriptOnce(exampleScriptSrc, {
      isLoaded: () => {
        checked = true;
        return true;
      },
    });

    // Already-loaded scripts do not append a new script element.
    expect(checked).to.equal(true);
    expect(document.querySelector(`script[src="${exampleScriptSrc}"]`)).to.equal(null);
  });

  it("deduplicates an existing script element", async () => {
    // Build the DOM fixture with an existing script tag.
    const script = document.createElement("script");
    script.src = exampleScriptSrc;
    document.head.append(script);

    // Load the same script URL and finish the existing script load.
    const loadPromise = loadScriptOnce(exampleScriptSrc);
    script.dispatchEvent(new Event("load"));

    await loadPromise;
    await waitForMicrotask();

    // The loader reuses the existing script element.
    expect(document.querySelectorAll(`script[src="${exampleScriptSrc}"]`)).to.have.length(1);
  });

  it("resolves immediately when an existing script was already loaded", async () => {
    // Build the DOM fixture with a script that finished loading earlier.
    const script = document.createElement("script");
    script.src = exampleScriptSrc;
    script.dataset.ocgScriptLoaded = "true";
    document.head.append(script);

    // Load the same script URL after it has already finished loading.
    await loadScriptOnce(exampleScriptSrc);

    // The loader reuses the already-loaded script element.
    expect(document.querySelectorAll(`script[src="${exampleScriptSrc}"]`)).to.have.length(1);
  });

  it("appends a missing script element", async () => {
    // Load a script URL that is not present in the document yet.
    const loadPromise = loadScriptOnce(exampleScriptSrc);
    const script = document.querySelector(`script[src="${exampleScriptSrc}"]`);

    // Finish the appended script load.
    expect(script).to.not.equal(null);
    script.dispatchEvent(new Event("load"));

    // The loader resolves after the appended script fires load.
    await loadPromise;
  });

  it("removes a failed script element so a retry can append it again", async () => {
    // Trigger an error on the first script load attempt.
    const firstAttempt = loadScriptOnce(exampleScriptSrc);
    const firstScript = document.querySelector(`script[src="${exampleScriptSrc}"]`);
    expect(firstScript).to.not.equal(null);
    firstScript.onerror();

    let failedError = null;
    try {
      await firstAttempt;
    } catch (error) {
      failedError = error;
    }

    // Verify the failed element was removed and a retry succeeds.
    expect(failedError).to.be.an("error");
    expect(document.querySelector(`script[src="${exampleScriptSrc}"]`)).to.equal(null);

    const retryAttempt = loadScriptOnce(exampleScriptSrc);
    const retryScript = document.querySelector(`script[src="${exampleScriptSrc}"]`);
    expect(retryScript).to.not.equal(null);
    retryScript.onload();
    await retryAttempt;
  });

  it("inserts a lazy stylesheet before the app stylesheet and deduplicates repeated loads", async () => {
    // Place a hashed app stylesheet in head to verify cascade order.
    const appStylesheet = document.createElement("link");
    appStylesheet.rel = "stylesheet";
    appStylesheet.href = "/static/css/styles.12345678.css";
    document.head.append(appStylesheet);

    // Start two concurrent stylesheet loads for the same href.
    const firstLoad = loadStylesheetOnce(exampleStylesheetHref);
    const secondLoad = loadStylesheetOnce(exampleStylesheetHref);
    const links = document.head.querySelectorAll(`link[rel="stylesheet"][href="${exampleStylesheetHref}"]`);
    expect(links).to.have.length(1);
    expect(links[0].nextElementSibling).to.equal(appStylesheet);

    // Complete the load and verify subsequent calls resolve immediately.
    links[0].dispatchEvent(new Event("load"));
    await Promise.all([firstLoad, secondLoad]);
    await loadStylesheetOnce(exampleStylesheetHref);
    expect(
      document.head.querySelectorAll(`link[rel="stylesheet"][href="${exampleStylesheetHref}"]`),
    ).to.have.length(1);
  });

  it("removes a failed stylesheet element so a retry can insert it again", async () => {
    // Trigger an error on the first stylesheet load attempt.
    const firstAttempt = loadStylesheetOnce(exampleStylesheetHref);
    const firstLink = document.head.querySelector(`link[rel="stylesheet"][href="${exampleStylesheetHref}"]`);
    expect(firstLink).to.not.equal(null);
    firstLink.onerror();

    let failedError = null;
    try {
      await firstAttempt;
    } catch (error) {
      failedError = error;
    }

    // Verify the failed link was removed and a retry succeeds.
    expect(failedError).to.be.an("error");
    expect(document.head.querySelector(`link[rel="stylesheet"][href="${exampleStylesheetHref}"]`)).to.equal(
      null,
    );

    const retryAttempt = loadStylesheetOnce(exampleStylesheetHref);
    const retryLink = document.head.querySelector(`link[rel="stylesheet"][href="${exampleStylesheetHref}"]`);
    expect(retryLink).to.not.equal(null);
    retryLink.onload();
    await retryAttempt;
  });

  it("preserves existing onload handlers when awaiting an existing script or stylesheet tag", async () => {
    // Attach existing tags with caller-owned onload handlers.
    let existingScriptOnloadCount = 0;
    const script = document.createElement("script");
    script.src = exampleScriptSrc;
    script.onload = () => {
      existingScriptOnloadCount += 1;
    };
    document.head.append(script);

    let existingLinkOnloadCount = 0;
    const link = document.createElement("link");
    link.rel = "stylesheet";
    link.href = exampleStylesheetHref;
    link.onload = () => {
      existingLinkOnloadCount += 1;
    };
    document.head.append(link);

    // Wait on the existing tags and dispatch load events.
    const scriptPromise = loadScriptOnce(exampleScriptSrc);
    const linkPromise = loadStylesheetOnce(exampleStylesheetHref);
    script.dispatchEvent(new Event("load"));
    link.dispatchEvent(new Event("load"));
    await Promise.all([scriptPromise, linkPromise]);

    // Existing handlers remain intact and ran when load fired.
    expect(existingScriptOnloadCount).to.equal(1);
    expect(existingLinkOnloadCount).to.equal(1);
    expect(typeof script.onload).to.equal("function");
    expect(typeof link.onload).to.equal("function");
  });
});
