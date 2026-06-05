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
