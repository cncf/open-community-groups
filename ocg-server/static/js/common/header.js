/**
 * Initializes header dropdown and nav loading behavior with HTMX awareness.
 */
let documentHandlersBound = false;
let lifecycleListenersBound = false;
let pendingHeaderNavLink = null;
let pendingHeaderNavLinkTimer = null;

const headerNavLinkSelector = "[data-header-nav-link]";
const headerNavLinkPendingDelayMs = 120;

/**
 * Finds the header nav link that triggered an event.
 * @param {Event} event - Click or HTMX lifecycle event.
 * @returns {Element|null} Matching header nav link, if any.
 */
const getHeaderNavLinkFromEvent = (event) => {
  const source = event?.detail?.elt || event?.target;
  if (!(source instanceof Element)) {
    return null;
  }

  if (source.matches(headerNavLinkSelector)) {
    return source;
  }

  return source.closest(headerNavLinkSelector);
};

/**
 * Clears the pending loading state from the desktop header nav link.
 */
const clearHeaderNavLoading = () => {
  if (pendingHeaderNavLinkTimer) {
    window.clearTimeout(pendingHeaderNavLinkTimer);
    pendingHeaderNavLinkTimer = null;
  }

  if (!pendingHeaderNavLink) {
    return;
  }

  pendingHeaderNavLink.classList.remove("header-nav-link-pending");
  pendingHeaderNavLink.removeAttribute("aria-busy");
  pendingHeaderNavLink = null;
};

/**
 * Clears pending loading state from dropdown links with manual spinners.
 */
const clearHeaderDropdownLoading = () => {
  document.querySelectorAll(".header-dropdown-link-pending").forEach((link) => {
    link.classList.remove("header-dropdown-link-pending");
    link.removeAttribute("aria-busy");
  });
};

/**
 * Clears all header loading indicators.
 */
const clearHeaderLoading = () => {
  clearHeaderNavLoading();
  clearHeaderDropdownLoading();
};

/**
 * Restores header interactions after browser or HTMX history navigation.
 */
const restoreHeaderState = () => {
  clearHeaderLoading();
  initUserDropdown();
};

/**
 * Clears the loading state for the matching HTMX header nav request.
 * @param {Event} event - HTMX lifecycle event.
 */
const clearHeaderNavLoadingFromHtmx = (event) => {
  const link = getHeaderNavLinkFromEvent(event);
  if (!link || link !== pendingHeaderNavLink) {
    return;
  }

  clearHeaderNavLoading();
};

/**
 * Queues a delayed loading state for a header nav link.
 * @param {Element} link - Header nav link.
 */
const queueHeaderNavLoading = (link) => {
  if (pendingHeaderNavLink === link) {
    return;
  }

  clearHeaderNavLoading();
  pendingHeaderNavLink = link;

  pendingHeaderNavLinkTimer = window.setTimeout(() => {
    if (pendingHeaderNavLink !== link) {
      return;
    }

    link.classList.add("header-nav-link-pending");
    link.setAttribute("aria-busy", "true");
    pendingHeaderNavLinkTimer = null;
  }, headerNavLinkPendingDelayMs);
};

/**
 * Shows a delayed loading state for header nav link clicks.
 * @param {MouseEvent} event - Click event.
 */
const startHeaderNavLoadingFromClick = (event) => {
  if (
    event.defaultPrevented ||
    event.button !== 0 ||
    event.metaKey ||
    event.ctrlKey ||
    event.shiftKey ||
    event.altKey
  ) {
    return;
  }

  const link = getHeaderNavLinkFromEvent(event);
  if (!link) {
    return;
  }

  queueHeaderNavLoading(link);
};

/**
 * Shows a delayed loading state on boosted header nav links.
 * @param {Event} event - HTMX beforeRequest event.
 */
const startHeaderNavLoadingFromHtmx = (event) => {
  const link = getHeaderNavLinkFromEvent(event);
  if (!link) {
    return;
  }

  queueHeaderNavLoading(link);
};

// Ensures global handlers close the dropdown on outside click or Escape.
const ensureDocumentHandlers = () => {
  if (documentHandlersBound) {
    return;
  }

  const handleDocumentClick = (event) => {
    const button = document.getElementById("user-dropdown-button");
    const dropdown = document.getElementById("user-dropdown");

    if (!button || !dropdown) {
      return;
    }

    const clickedButton = button.contains(event.target);
    const clickedDropdown = dropdown.contains(event.target);

    if (!clickedButton && !clickedDropdown) {
      // Hide if the click did not originate inside the dropdown or trigger.
      dropdown.classList.add("hidden");
    }
  };

  const handleKeydown = (event) => {
    if (event.key !== "Escape") {
      return;
    }

    const button = document.getElementById("user-dropdown-button");
    const dropdown = document.getElementById("user-dropdown");

    if (!button || !dropdown || dropdown.classList.contains("hidden")) {
      return;
    }

    dropdown.classList.add("hidden");
    button.focus();
  };

  document.addEventListener("click", handleDocumentClick);
  document.addEventListener("click", startHeaderNavLoadingFromClick);
  document.addEventListener("keydown", handleKeydown);

  documentHandlersBound = true;
};

/**
 * Determines if a swap should reset scroll for dashboard pages.
 * @param {Event} event - HTMX afterSwap event.
 * @returns {boolean} True when the swap targets dashboard content.
 */
const shouldResetDashboardScroll = (event) => {
  if (!event) {
    return false;
  }

  const swapTarget = event.detail?.target || event.target;
  if (!swapTarget) {
    return false;
  }

  const path = window.location?.pathname || "";
  if (!path.startsWith("/dashboard/")) {
    return false;
  }

  return swapTarget === document.body || swapTarget.id === "dashboard-content";
};

/**
 * Scrolls to the top after dashboard swaps.
 * @param {Event} event - HTMX afterSwap event.
 */
const scrollToTopOnDashboardSwap = (event) => {
  if (!shouldResetDashboardScroll(event) || typeof window.scrollTo !== "function") {
    return;
  }

  window.scrollTo({ top: 0, behavior: "auto" });
};

// Subscribes to HTMX lifecycle hooks once for history and swap events.
const bindLifecycleListeners = () => {
  if (lifecycleListenersBound) {
    return;
  }

  document.addEventListener("htmx:historyRestore", restoreHeaderState);
  document.addEventListener("htmx:beforeRequest", startHeaderNavLoadingFromHtmx);
  document.addEventListener("htmx:afterRequest", clearHeaderNavLoadingFromHtmx);
  document.addEventListener("htmx:afterSwap", initUserDropdown);
  document.addEventListener("htmx:afterSwap", scrollToTopOnDashboardSwap);
  window.addEventListener("pageshow", restoreHeaderState);

  lifecycleListenersBound = true;
};

// Toggles dropdown visibility when the avatar button is clicked.
const toggleDropdownVisibility = () => {
  const dropdown = document.getElementById("user-dropdown");
  if (!dropdown) {
    return;
  }

  dropdown.classList.toggle("hidden");
};

// Public initializer for the user dropdown interactions.
export const initUserDropdown = () => {
  ensureDocumentHandlers();
  bindLifecycleListeners();

  const button = document.getElementById("user-dropdown-button");
  const dropdown = document.getElementById("user-dropdown");

  if (!button || !dropdown || button.__ocgDropdownInitialized) {
    return;
  }

  button.addEventListener("click", toggleDropdownVisibility);
  button.__ocgDropdownInitialized = true;

  if (!dropdown.__ocgCloseOnLinkBound) {
    dropdown.addEventListener(
      "click",
      (event) => {
        const link = event.target.closest("a");
        if (!link) {
          return;
        }
        // Close immediately unless the link shows a loading spinner.
        if (link.querySelector(".hx-spinner")) {
          if (link.getAttribute("hx-boost") === "false") {
            link.classList.add("header-dropdown-link-pending");
            link.setAttribute("aria-busy", "true");
          }
          return;
        }
        dropdown.classList.add("hidden");
      },
      true,
    );
    dropdown.__ocgCloseOnLinkBound = true;
  }
};

initUserDropdown();
