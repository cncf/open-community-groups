/**
 * Checks if the current path is a dashboard route.
 * @returns {boolean} True when on a dashboard page.
 */
export const isDashboardPath = () => {
  const path = window?.location?.pathname || "";
  return path.startsWith("/dashboard");
};

/**
 * Scrolls to the top of the dashboard so alerts stay visible.
 * @returns {void}
 */
export const scrollToDashboardTop = () => {
  if (!isDashboardPath() || typeof window?.scrollTo !== "function") {
    return;
  }

  window.scrollTo({ top: 0, behavior: "auto" });
};
