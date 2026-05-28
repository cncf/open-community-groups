import {
  addLoadedCommitShaHeader,
  isDeploymentReloadRequested,
  reloadIfDeploymentChanged,
} from "/static/js/common/deployment-version.js";

/**
 * Fetches a resource and follows server-provided browser redirects.
 *
 * @param {RequestInfo|URL} input Request target
 * @param {RequestInit} init Fetch options
 * @returns {Promise<Response>}
 */
export const ocgFetch = async (input, init = {}) => {
  const headers = new Headers(init.headers || {});
  if (isSameOriginRequest(input)) {
    headers.set("X-OCG-Fetch", "true");
    addLoadedCommitShaHeader(headers);
  }

  const response = await fetch(input, {
    ...init,
    headers,
  });
  if (reloadIfDeploymentChanged(response.headers)) {
    if (isDeploymentReloadRequested()) {
      return waitForDeploymentReload();
    }
    return response;
  }

  const redirectUrl = response.headers?.get?.("X-OCG-Redirect");
  if (redirectUrl) {
    window.location.assign(redirectUrl);
    throw new Error("Browser redirect requested by server.");
  }

  return response;
};

/**
 * Returns whether the request target resolves to the current browser origin.
 *
 * @param {RequestInfo|URL} input Request target
 * @returns {boolean}
 */
const isSameOriginRequest = (input) => {
  const url = typeof input === "string" ? input : input instanceof URL ? input.href : input?.url;
  if (!url) {
    return false;
  }

  try {
    return new URL(url, window.location.href).origin === window.location.origin;
  } catch {
    return false;
  }
};

/**
 * Keeps caller catch/finally handlers from rendering stale UI during reload.
 * @returns {Promise<void>} Promise that stays pending until navigation replaces the page.
 */
const waitForDeploymentReload = () => new Promise(() => {});
