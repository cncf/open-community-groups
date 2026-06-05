/**
 * Finds an element by id from a document-like root or an element subtree.
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
 * Checks whether an element has already been marked ready for a behavior.
 * @param {Element|null|undefined} element Element with a dataset.
 * @param {string} key Dataset key.
 * @returns {boolean} True when the ready flag is set.
 */
export const isDatasetReady = (element, key) => element?.dataset?.[key] === "true";

/**
 * Marks an element ready for a behavior when it has not been marked yet.
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
 * Shows or hides an element with the shared hidden utility class.
 * @param {Element|null|undefined} element Element to update.
 * @param {boolean} hidden Whether the element should be hidden.
 * @returns {void}
 */
export const setElementHidden = (element, hidden) => {
  element?.classList?.toggle("hidden", hidden);
};

/**
 * Checks whether an element has the shared hidden utility class.
 * @param {Element|null|undefined} element Element to inspect.
 * @returns {boolean} True when the element is hidden.
 */
export const isElementHidden = (element) => element?.classList?.contains("hidden") === true;

/**
 * Toggles an element's shared hidden utility class.
 * @param {Element|null|undefined} element Element to update.
 * @returns {void}
 */
export const toggleElementHidden = (element) => {
  setElementHidden(element, !isElementHidden(element));
};

/**
 * Ensures an element has an id and returns it.
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
 * Focuses an element by id when present.
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
 * Finds the closest matching element from an event target-like value.
 * @param {EventTarget|null|undefined} target Event target to inspect.
 * @param {string} selector Selector to match.
 * @returns {Element|null} Matching element when present.
 */
export const closestElement = (target, selector) =>
  target instanceof Element ? target.closest(selector) : null;

/**
 * Finds the closest matching element when it belongs to the provided root.
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
 * Checks whether an event happened outside an element.
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
 * Binds a document click listener that only runs for clicks outside an element.
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
 * Initializes current content when the document is ready.
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
 * Initializes current content once and repeats initialization after HTMX loads.
 * @param {(root: Document|Element) => void} callback Initialization callback.
 * @returns {void}
 */
export const initializeOnReadyAndHtmxLoad = (callback) => {
  initializeOnReady(() => callback(document));

  document.addEventListener("htmx:load", (event) => {
    const root = event.target instanceof Element ? event.target : document;
    callback(root);
  });
};

/**
 * Initializes the matching root and any matching descendants.
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
 * Loads an external script once and resolves when the script is available.
 * @param {string} src Script URL.
 * @param {object} options Loader options.
 * @param {() => boolean} options.isLoaded Existing global/library check.
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

    return new Promise((resolve, reject) => {
      existingScript.addEventListener(
        "load",
        () => {
          existingScript.dataset.ocgScriptLoaded = "true";
          resolve();
        },
        { once: true },
      );
      existingScript.addEventListener("error", () => reject(new Error(`Failed to load script: ${src}`)), {
        once: true,
      });
    });
  }

  return new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = src;
    script.onload = () => {
      script.dataset.ocgScriptLoaded = "true";
      resolve();
    };
    script.onerror = () => reject(new Error(`Failed to load script: ${src}`));
    document.head.appendChild(script);
  });
};
