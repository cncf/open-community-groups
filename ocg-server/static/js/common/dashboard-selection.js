/**
 * Persists dashboard selection using HTMX.
 *
 * @param {string} selectUrl Endpoint URL used to persist the selected entity
 * @returns {Promise<void>}
 */
export const selectDashboardAndKeepTab = async (selectUrl) => {
  if (!window.htmx || typeof window.htmx.ajax !== "function") {
    throw new Error("HTMX is required for dashboard selection.");
  }

  await window.htmx.ajax("PUT", selectUrl, {
    target: "body",
    indicator: "#dashboard-spinner",
  });
};
