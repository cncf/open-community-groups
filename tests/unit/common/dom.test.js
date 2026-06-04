import { expect } from "@open-wc/testing";

import {
  initializeMatchingRoots,
  initializeOnReady,
  initializeOnReadyAndHtmxLoad,
  loadScriptOnce,
  getElementById,
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
