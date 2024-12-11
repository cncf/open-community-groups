// Check if script is already loaded.
export const checkIfScriptIsLoaded = (src) => {
  return Array.from(document.querySelectorAll("script"))
    .map((scr) => scr.src)
    .includes(src);
};

// Hide loading spinner.
export const hideSpinner = () => {
  const content = document.getElementById("explore-content");
  content.classList.remove("is-loading");
};

// Overwrite primary color in CSS.
export const overWritePrimaryColor = (color) => {
  const r = document.querySelector(":root");
  r.style.setProperty("--ocg-primary", color);
};

// Show loading spinner.
export const showSpinner = () => {
  const content = document.getElementById("explore-content");
  content.classList.add("is-loading");
};

// Show or hide mobile navigation bar.
export const toggleNavbarMobile = () => {
  const navbarMobile = document.getElementById("navbar-mobile");
  navbarMobile.classList.toggle("hidden");
  const navbarBackdrop = document.getElementById("navbar-backdrop");
  navbarBackdrop.classList.toggle("hidden");
};

// Show or hide provided modal.
export const updateModalStatus = (modalId) => {
  const modal = document.getElementById(modalId);
  if (modal.classList.contains("hidden")) {
    modal.classList.remove("hidden");
  } else {
    modal.classList.add("hidden");
  }
};
