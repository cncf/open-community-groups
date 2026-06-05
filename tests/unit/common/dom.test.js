import { expect } from "@open-wc/testing";

import {
  bindOutsideClickListener,
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
  markDatasetReady,
  setElementHidden,
  toggleElementHidden,
} from "/static/js/common/dom.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom, trackAddedEventListeners } from "/tests/unit/test-utils/dom.js";

describe("common dom", () => {
  const exampleScriptSrc = "data:text/javascript,window.__ocgDomTestScriptLoaded%3Dtrue";

  beforeEach(() => {
    resetDom();
    document.head.querySelectorAll(`script[src="${exampleScriptSrc}"]`).forEach((script) => script.remove());
  });

  afterEach(() => {
    resetDom();
    document.head.querySelectorAll(`script[src="${exampleScriptSrc}"]`).forEach((script) => script.remove());
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

  it("initializes current content and htmx-loaded fragments", () => {
    // Track the roots passed to the lifecycle initializer.
    const listenerTracker = trackAddedEventListeners();
    const initializedRoots = [];

    try {
      // Initialize once for the current document.
      initializeOnReadyAndHtmxLoad((root) => {
        initializedRoots.push(root);
      });

      // Dispatch the lifecycle event used by swapped content.
      const fragment = document.createElement("section");
      document.body.append(fragment);
      fragment.dispatchEvent(new CustomEvent("htmx:load", { bubbles: true }));

      // Verify current and swapped roots are initialized.
      expect(initializedRoots).to.deep.equal([document, fragment]);
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
});
