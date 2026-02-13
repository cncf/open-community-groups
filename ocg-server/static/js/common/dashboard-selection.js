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
 * Persists dashboard selection and handles navigation for HTMX/fetch clients.
 * HTMX follows backend response headers and fetch redirects to dashboard tab URL.
 *
 * @param {string} selectUrl Endpoint URL used to persist the selected entity
 * @param {string} redirectPath Dashboard page path to navigate to for fetch fallback
 * @returns {Promise<void>}
 */
export const selectDashboardAndKeepTab = async (selectUrl, redirectPath) => {
  if (typeof window === "undefined") {
    return;
  }

  if (window.htmx && typeof window.htmx.ajax === "function") {
    let statusCode = 0;
    await window.htmx.ajax("PUT", selectUrl, {
      target: "body",
      indicator: "#dashboard-spinner",
      handler: (_, responseInfo) => {
        statusCode = responseInfo.xhr.status;
      },
    });
    if (statusCode < 200 || statusCode >= 300) {
      throw new Error(`Dashboard selection failed with status ${statusCode}`);
    }
    return;
  }

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
  const destination = `${redirectPath}${currentDashboardTabQuery()}`;
  window.location.assign(destination);
};
