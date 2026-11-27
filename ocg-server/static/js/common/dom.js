// Number of element id prefixes generated for components without an id.
let generatedElementIdPrefixCount = 0;

// Maps dynamically created or awaited <script>/<link> elements to their active load promise.
const pendingAssetLoads = new WeakMap();

// Tracks vendor stylesheets that failed after their companion script already loaded, so retries
// reload the stylesheet even though the global script check now returns true.
const partialStylesheetFailures = new Set();

/**
 * Builds a stable element id from a prefix and suffix.
 * @param {string} prefix Element id prefix.
 * @param {string} suffix Element id suffix.
 * @returns {string} Combined element id.
 */
export const buildElementId = (prefix, suffix) => `${prefix}-${suffix}`;

/**
 * Supports Document.getElementById and element-scoped lookup by id.
 * @param {Document|Element} root Query root.
 * @param {string} id Element id.
 * @returns {Element|null} Matching element when present.
 */
export const getElementById = (root, id) => {
  if (typeof root?.getElementById === "function") {
    return root.getElementById(id);
  }

  if (root instanceof Element && root.id === id) {
    return root;
  }

  const escapedId = String(id).replace(/["\\]/g, "\\$&");
  return root?.querySelector?.(`[id="${escapedId}"]`) || null;
};

/**
 * Checks whether this element was already initialized.
 * @param {Element|null|undefined} element Element with a dataset.
 * @param {string} key Dataset key.
 * @returns {boolean} True when the ready flag is set.
 */
export const isDatasetReady = (element, key) => element?.dataset?.[key] === "true";

/**
 * Marks an element once so repeated HTMX loads do not double-bind behavior.
 * @param {Element|null|undefined} element Element with a dataset.
 * @param {string} key Dataset key.
 * @returns {boolean} True when the element was newly marked.
 */
export const markDatasetReady = (element, key) => {
  if (!element || isDatasetReady(element, key)) {
    return false;
  }

  element.dataset[key] = "true";
  return true;
};

/**
 * Adds or removes the hidden class on optional UI elements.
 * @param {Element|null|undefined} element Element to update.
 * @param {boolean} hidden Whether the element should be hidden.
 * @returns {void}
 */
export const setElementHidden = (element, hidden) => {
  element?.classList?.toggle("hidden", hidden);
};

/**
 * Checks whether the hidden class is present.
 * @param {Element|null|undefined} element Element to inspect.
 * @returns {boolean} True when the element is hidden.
 */
export const isElementHidden = (element) => element?.classList?.contains("hidden") === true;

/**
 * Checks whether an element is fully visible in the viewport.
 * @param {HTMLElement} element Element to check.
 * @returns {boolean} True when the element is fully visible.
 */
export const isElementInView = (element) => {
  if (!element || typeof element.getBoundingClientRect !== "function") {
    return true;
  }

  const rect = element.getBoundingClientRect();
  const viewHeight = window.innerHeight || document.documentElement.clientHeight;
  const viewWidth = window.innerWidth || document.documentElement.clientWidth;

  return rect.top >= 0 && rect.left >= 0 && rect.bottom <= viewHeight && rect.right <= viewWidth;
};

/**
 * Toggles the hidden class on optional UI elements.
 * @param {Element|null|undefined} element Element to update.
 * @returns {void}
 */
export const toggleElementHidden = (element) => {
  setElementHidden(element, !isElementHidden(element));
};

/**
 * Ensures action controls have a stable id before another behavior references them.
 * @param {Element|null|undefined} element Element that needs an id.
 * @param {string} fallbackId Id to assign when the element has none.
 * @returns {string} Existing or assigned id.
 */
export const ensureElementId = (element, fallbackId) => {
  if (!element) {
    return "";
  }

  if (!element.id) {
    element.id = fallbackId;
  }

  return element.id;
};

/**
 * Builds a unique element id prefix for a component instance without an id,
 * such as `multi-select-tags-1`, so several instances can share a page.
 * @param {string} componentName Component name used as the first id part.
 * @param {*} name Field name identifying the instance.
 * @param {string} fallbackName Name used when the field name has no safe characters.
 * @returns {string} Unique element id prefix.
 */
export const generateElementIdPrefix = (componentName, name, fallbackName) => {
  generatedElementIdPrefixCount += 1;
  return `${componentName}-${sanitizeIdPart(name) || fallbackName}-${generatedElementIdPrefixCount}`;
};

/**
 * Turns a raw value into a safe element id fragment.
 * @param {*} value Raw value.
 * @returns {string} Id fragment.
 */
export const sanitizeIdPart = (value) =>
  String(value || "")
    .replace(/[^A-Za-z0-9_-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");

/**
 * Focuses an optional element and supports text selection for input-like nodes.
 * @param {Document|Element} root Query root.
 * @param {string} id Element id.
 * @param {object} [options={}] Focus options.
 * @param {boolean} [options.select=false] Whether to select the element text.
 * @returns {Element|null} Focused element when present.
 */
export const focusElementById = (root, id, { select = false } = {}) => {
  const element = getElementById(root, id);
  element?.focus?.();
  if (select) {
    element?.select?.();
  }
  return element;
};

/**
 * Safely runs closest() on values that might not be Elements.
 * @param {EventTarget|null|undefined} target Event target to inspect.
 * @param {string} selector Selector to match.
 * @returns {Element|null} Matching element when present.
 */
export const closestElement = (target, selector) =>
  target instanceof Element ? target.closest(selector) : null;

/**
 * Keeps delegated event matches scoped to the HTMX/document root being scanned.
 * @param {EventTarget|null|undefined} target Event target to inspect.
 * @param {string} selector Selector to match.
 * @param {Document|Element} root Root that must contain the match.
 * @returns {Element|null} Matching element when present in root.
 */
export const closestElementWithinRoot = (target, selector, root = document) => {
  const element = closestElement(target, selector);
  if (!element) {
    return null;
  }

  return root === document || root.contains(element) ? element : null;
};

/**
 * Checks the full event path before falling back to event.target.
 * @param {Event} event Event to inspect.
 * @param {Element|null|undefined} element Element that owns the interaction.
 * @returns {boolean} True when the event target is outside the element.
 */
export const isOutsideElementEvent = (event, element) => {
  if (!(element instanceof Element)) {
    return false;
  }

  const path = event?.composedPath?.();
  if (Array.isArray(path) && path.length > 0) {
    return !path.includes(element);
  }

  return event?.target instanceof Node ? !element.contains(event.target) : true;
};

/**
 * Calls a handler when the document is clicked outside an element.
 * @param {Element} element Element that owns the interaction.
 * @param {(event: MouseEvent) => void} onOutsideClick Outside click callback.
 * @returns {() => void} Cleanup callback that removes the listener.
 */
export const bindOutsideClickListener = (element, onOutsideClick) => {
  const handleClick = (event) => {
    if (isOutsideElementEvent(event, element)) {
      onOutsideClick(event);
    }
  };

  document.addEventListener("click", handleClick);
  return () => document.removeEventListener("click", handleClick);
};

/**
 * Runs immediately after DOMContentLoaded, or waits for it when still loading.
 * @param {() => void} callback Initialization callback.
 * @returns {void}
 */
export const initializeOnReady = (callback) => {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", callback, { once: true });
  } else {
    callback();
  }
};

/**
 * Covers the initial document, HTMX fragments, and restored history snapshots.
 * @param {(root: Document|Element, context?: object) => void} callback Initialization callback.
 * @returns {void}
 */
export const initializeOnReadyAndHtmxLoad = (callback) => {
  initializeOnReady(() => callback(document));

  document.addEventListener("htmx:load", (event) => {
    const root = event.target instanceof Element ? event.target : document;
    callback(root);
  });

  document.addEventListener("htmx:historyRestore", (event) => {
    const root = event.target instanceof Element ? event.target : document;
    callback(root, { historyRestore: true });
  });
};

/**
 * Handles both a matching fragment root and matching descendants inside it.
 * @param {Document|Element} root Root element to scan from.
 * @param {string} selector Selector for declarative roots.
 * @param {(element: Element) => void} initializer Root initializer.
 * @returns {void}
 */
export const initializeMatchingRoots = (root = document, selector, initializer) => {
  if (root instanceof Element && root.matches(selector)) {
    initializer(root);
  }

  root.querySelectorAll?.(selector).forEach((element) => {
    initializer(element);
  });
};

/**
 * Returns whether a vendor script and its companion stylesheet are both ready
 * without needing another async load.
 * @param {object} config Asset check configuration.
 * @param {() => boolean} config.isScriptLoaded Predicate checking the vendor global.
 * @param {string} config.stylesheetHref Companion stylesheet URL.
 * @returns {boolean} True when both script and stylesheet are ready.
 */
export const isVendorAssetsReady = ({ isScriptLoaded, stylesheetHref }) => {
  if (!isScriptLoaded() || partialStylesheetFailures.has(stylesheetHref)) {
    return false;
  }

  const existingLink = document.querySelector(`link[rel="stylesheet"][href="${stylesheetHref}"]`);
  return !existingLink || isStylesheetLinkLoaded(existingLink);
};

/**
 * Loads a script once, or waits for an existing tag with the same src.
 * @param {string} src Script URL.
 * @param {object} [options={}] Loader options.
 * @param {() => boolean} [options.isLoaded] Existing global/library check.
 * @returns {Promise<void>} Promise resolved when the script is loaded.
 */
export const loadScriptOnce = (src, { isLoaded = () => false } = {}) => {
  if (isLoaded()) {
    return Promise.resolve();
  }

  const existingScript = document.querySelector(`script[src="${src}"]`);
  if (existingScript) {
    if (existingScript.dataset.ocgScriptLoaded === "true" || existingScript.dataset.loaded === "1") {
      return Promise.resolve();
    }

    return waitForAssetElement(existingScript, {
      errorMessage: `Failed to load script: ${src}`,
      loadedAttr: "ocgScriptLoaded",
      removeOnError: false,
    });
  }

  const script = document.createElement("script");
  script.src = src;
  const loadPromise = waitForAssetElement(script, {
    errorMessage: `Failed to load script: ${src}`,
    loadedAttr: "ocgScriptLoaded",
    removeOnError: true,
  });
  document.head.appendChild(script);
  return loadPromise;
};

/**
 * Loads a stylesheet once before the application stylesheet so vendor CSS keeps
 * its cascade position, or waits for an existing link with the same href.
 * @param {string} href Stylesheet URL.
 * @param {object} [options={}] Loader options.
 * @param {() => boolean} [options.isLoaded] Existing stylesheet check.
 * @returns {Promise<void>} Promise resolved when the stylesheet is loaded.
 */
export const loadStylesheetOnce = (href, { isLoaded = () => false } = {}) => {
  if (isLoaded()) {
    return Promise.resolve();
  }

  const existingLink = document.querySelector(`link[rel="stylesheet"][href="${href}"]`);
  if (existingLink) {
    if (isStylesheetLinkLoaded(existingLink)) {
      return Promise.resolve();
    }

    return waitForAssetElement(existingLink, {
      errorMessage: `Failed to load stylesheet: ${href}`,
      loadedAttr: "ocgStylesheetLoaded",
      removeOnError: false,
    });
  }

  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = href;
  const loadPromise = waitForAssetElement(link, {
    errorMessage: `Failed to load stylesheet: ${href}`,
    loadedAttr: "ocgStylesheetLoaded",
    removeOnError: true,
  });

  const appStylesheet = document.head.querySelector('link[rel="stylesheet"][href^="/static/css/styles"]');
  if (appStylesheet) {
    document.head.insertBefore(link, appStylesheet);
  } else {
    document.head.appendChild(link);
  }
  return loadPromise;
};

/**
 * Loads a paired vendor script and stylesheet in parallel once, recovering if
 * the stylesheet failed while the script succeeded.
 * @param {object} config Vendor asset configuration.
 * @param {() => boolean} config.isScriptLoaded Predicate checking the vendor global.
 * @param {string} config.scriptSrc Script URL.
 * @param {string} config.stylesheetHref Stylesheet URL.
 * @returns {Promise<void>} Resolves once both assets are ready.
 */
export const loadVendorAssetsOnce = async ({ isScriptLoaded, scriptSrc, stylesheetHref }) => {
  if (isVendorAssetsReady({ isScriptLoaded, stylesheetHref })) {
    return;
  }

  const [stylesheetResult, scriptResult] = await Promise.allSettled([
    loadStylesheetOnce(stylesheetHref),
    loadScriptOnce(scriptSrc, { isLoaded: isScriptLoaded }),
  ]);

  if (stylesheetResult.status === "fulfilled") {
    partialStylesheetFailures.delete(stylesheetHref);
  } else if (isScriptLoaded()) {
    partialStylesheetFailures.add(stylesheetHref);
  }

  if (stylesheetResult.status === "rejected") {
    throw stylesheetResult.reason;
  }
  if (scriptResult.status === "rejected") {
    throw scriptResult.reason;
  }
};

/**
 * Returns whether a stylesheet link element has already finished loading.
 * @param {HTMLLinkElement} link Stylesheet link element.
 * @returns {boolean} True when the stylesheet is loaded.
 */
const isStylesheetLinkLoaded = (link) => link.dataset.ocgStylesheetLoaded === "true" || link.sheet !== null;

/**
 * Waits once for an asset element to finish loading, sharing one in-flight promise
 * across concurrent callers and detaching both handlers on settlement.
 * @param {HTMLScriptElement|HTMLLinkElement} element Asset element to observe.
 * @param {object} config Settlement behavior.
 * @param {string} config.errorMessage Rejection message on error.
 * @param {string} config.loadedAttr Dataset key set to `"true"` on load.
 * @param {boolean} config.removeOnError Whether to remove the element on error.
 * @returns {Promise<void>} Shared settlement promise.
 */
const waitForAssetElement = (element, { errorMessage, loadedAttr, removeOnError }) => {
  const existingPromise = pendingAssetLoads.get(element);
  if (existingPromise) {
    return existingPromise;
  }

  const promise = new Promise((resolve, reject) => {
    const handleLoad = () => {
      cleanup();
      element.dataset[loadedAttr] = "true";
      resolve();
    };
    const handleError = () => {
      cleanup();
      if (removeOnError) {
        element.remove();
      }
      reject(new Error(errorMessage));
    };

    // Newly created elements use IDL properties so callers/tests can invoke `.onload()` directly;
    // existing elements use addEventListener so pre-existing handlers are never overwritten.
    const cleanup = () => {
      if (removeOnError) {
        element.onload = null;
        element.onerror = null;
      } else {
        element.removeEventListener("load", handleLoad);
        element.removeEventListener("error", handleError);
      }
      pendingAssetLoads.delete(element);
    };

    if (removeOnError) {
      element.onload = handleLoad;
      element.onerror = handleError;
    } else {
      element.addEventListener("load", handleLoad);
      element.addEventListener("error", handleError);
    }
  });

  pendingAssetLoads.set(element, promise);
  return promise;
};
