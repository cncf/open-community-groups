/**
 * Finds an element by id from a document-like root or an element subtree.
 * @param {Document|Element} root Query root.
 * @param {string} id Element id.
 * @returns {HTMLElement|null} Matching element when present.
 */
export const queryElementById = (root, id) => {
  if (typeof root?.getElementById === "function") {
    return root.getElementById(id);
  }

  return root?.querySelector?.(`#${id}`) || null;
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
    return new Promise((resolve, reject) => {
      existingScript.addEventListener("load", () => resolve(), { once: true });
      existingScript.addEventListener("error", () => reject(new Error(`Failed to load script: ${src}`)), {
        once: true,
      });
    });
  }

  return new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = src;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error(`Failed to load script: ${src}`));
    document.head.appendChild(script);
  });
};
