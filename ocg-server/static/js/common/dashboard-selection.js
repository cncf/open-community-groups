/**
 * Returns the active dashboard tab query string.
 * @returns {string}
 */
export const currentDashboardTabQuery = () => {
  if (typeof window === "undefined") {
    return "";
  }

  const params = new URLSearchParams(window.location.search);
  const tab = params.get("tab");
  if (!tab) {
    return "";
  }

  const queryParams = new URLSearchParams();
  queryParams.set("tab", tab);
  return `?${queryParams.toString()}`;
};

/**
 * Persists dashboard selection and refreshes dashboard content while preserving
 * the current tab.
 *
 * @param {string} selectUrl Endpoint URL used to persist the selected entity
 * @param {string} redirectPath Dashboard page path to navigate to
 * @returns {Promise<void>}
 */
export const selectDashboardAndKeepTab = async (selectUrl, redirectPath) => {
  if (typeof window === "undefined") {
    return;
  }

  const destination = `${redirectPath}${currentDashboardTabQuery()}`;

  if (typeof window.fetch !== "function") {
    return;
  }

  const response = await window.fetch(selectUrl, {
    method: "PUT",
    credentials: "same-origin",
  });
  if (!response.ok) {
    throw new Error(`Dashboard selection failed with status ${response.status}`);
  }

  if (window.htmx && typeof window.htmx.ajax === "function") {
    await window.htmx.ajax("GET", destination, {
      target: "body",
      indicator: "#dashboard-spinner",
    });
    return;
  }

  window.location.assign(destination);
};
