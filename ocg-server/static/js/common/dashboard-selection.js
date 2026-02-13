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

/**
 * Persists dashboard selection and swaps to the target dashboard page.
 *
 * This helper uses fetch for selection to avoid HTMX trigger side effects
 * from the select endpoint before loading the destination page.
 *
 * @param {string} selectUrl Endpoint URL used to persist the selected entity
 * @param {string} dashboardUrl Dashboard URL to swap into the body
 * @returns {Promise<void>}
 */
export const selectDashboardAndSwapBody = async (selectUrl, dashboardUrl) => {
  if (!window.htmx || typeof window.htmx.ajax !== "function") {
    throw new Error("HTMX is required for dashboard selection.");
  }

  const response = await fetch(selectUrl, {
    method: "PUT",
    credentials: "same-origin",
  });
  if (!response.ok) {
    throw new Error(`Select dashboard entity failed: ${response.status}`);
  }

  // Load dashboard content with HTMX to avoid a full browser navigation.
  await window.htmx.ajax("GET", dashboardUrl, {
    target: "body",
    indicator: "#dashboard-spinner",
  });
};
