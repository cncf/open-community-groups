// Check if the provided script is already loaded.
export const isScriptLoaded = (src) => {
  return Array.from(document.querySelectorAll("script"))
    .map((scr) => scr.src)
    .includes(src);
};

// Show loading spinner.
export const showLoadingSpinner = (id) => {
  const content = document.getElementById(id || "explore-content");
  content.classList.add("is-loading");
};

// Hide loading spinner.
export const hideLoadingSpinner = (id) => {
  const content = document.getElementById(id || "explore-content");
  content.classList.remove("is-loading");
};

// Show or hide the mobile navigation bar.
export const toggleMobileNavbarVisibility = () => {
  const navbarMobile = document.getElementById("navbar-mobile");
  navbarMobile.classList.toggle("hidden");
  const navbarBackdrop = document.getElementById("navbar-backdrop");
  navbarBackdrop.classList.toggle("hidden");
};

// Show or hide the provided modal.
export const toggleModalVisibility = (modalId) => {
  const modal = document.getElementById(modalId);
  if (modal.classList.contains("hidden")) {
    modal.classList.remove("hidden");
  } else {
    modal.classList.add("hidden");
  }
};
