/**
 * Initializes header dropdown behavior with HTMX awareness.
 */
let documentHandlersBound = false;
let lifecycleListenersBound = false;

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

  document.addEventListener("htmx:historyRestore", initUserDropdown);
  document.addEventListener("htmx:afterSwap", initUserDropdown);
  document.addEventListener("htmx:afterSwap", scrollToTopOnDashboardSwap);
  window.addEventListener("pageshow", () => initUserDropdown());

  lifecycleListenersBound = true;
};

// Toggles dropdown visibility when the avatar button is clicked.
const toggleDropdownVisibility = (event) => {
  const dropdown = document.getElementById("user-dropdown");
  if (!dropdown) {
    return;
  }

  event.stopPropagation();
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
