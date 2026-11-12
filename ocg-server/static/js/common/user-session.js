const USER_MENU_BUTTON_SELECTOR = "#user-dropdown-button";
// Wrapper that loads the user menu on pages rendered without the visitor's session.
const USER_MENU_LOADER_SELECTOR = '[hx-get="/section/user-menu"]';

/** Menu loaders whose request has finished, whatever its outcome. */
const settledLoaders = new WeakSet();

/**
 * Resolves whether the visitor is logged in, as the header user menu reports it.
 * Public pages are rendered without the session and load that menu on open, so
 * the answer waits for a load that has not finished yet. A restored history
 * snapshot carries the old menu inside a new loader, and waits as well.
 * @param {Document|Element} [root=document] Root holding the header.
 * @returns {Promise<boolean|null>} Login state, or null when the menu cannot tell.
 */
export const resolveUserLoggedIn = async (root = document) => {
  const loader = root.querySelector(USER_MENU_LOADER_SELECTOR);
  if (loader && !settledLoaders.has(loader)) {
    await waitForLoader(loader);
  }

  const button = root.querySelector(USER_MENU_BUTTON_SELECTOR);

  return button ? button.dataset.loggedIn === "true" : null;
};

/**
 * Records a menu loader once its own request finishes.
 * @param {Event} event HTMX afterRequest event.
 * @returns {void}
 */
const handleAfterRequest = (event) => {
  if (event.target instanceof Element && event.target.matches(USER_MENU_LOADER_SELECTOR)) {
    settledLoaders.add(event.target);
  }
};

/**
 * Waits for a menu loader's own request to finish, ignoring requests that
 * bubble up from the menu it holds.
 * @param {Element} loader User menu loader.
 * @returns {Promise<void>} Resolves once the request has finished.
 */
const waitForLoader = (loader) =>
  new Promise((resolve) => {
    const handleLoaderAfterRequest = (event) => {
      if (event.target !== loader) {
        return;
      }

      loader.removeEventListener("htmx:afterRequest", handleLoaderAfterRequest);
      resolve();
    };

    loader.addEventListener("htmx:afterRequest", handleLoaderAfterRequest);
  });

document.addEventListener("htmx:afterRequest", handleAfterRequest);
