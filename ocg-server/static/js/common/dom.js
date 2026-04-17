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
