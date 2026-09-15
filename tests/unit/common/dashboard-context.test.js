import { expect } from "@open-wc/testing";

import {
  addLoadedDashboardContextHeaders,
  consumePendingDashboardContextRefreshAlert,
  getDashboardContextReloadUrl,
  initializeDashboardContextState,
  isDashboardContextReloadRequested,
  isStaleDashboardContextResponse,
  reloadIfDashboardContextStale,
  resetDashboardContextReloadState,
  SELECTED_COMMUNITY_ID_HEADER,
  SELECTED_GROUP_ID_HEADER,
  setDashboardContextReloadHandler,
  STALE_DASHBOARD_CONTEXT_HEADER,
} from "/static/js/common/dashboard-context.js";

const COMMUNITY_ID = "11111111-1111-4111-8111-111111111111";
const GROUP_ID = "22222222-2222-4222-8222-222222222222";

// Render the dashboard layout marker the loaded page exposes.
const setLoadedDashboardContext = ({ communityId, groupId } = {}) => {
  const groupAttribute = groupId ? ` data-ocg-selected-group-id="${groupId}"` : "";
  document.body.innerHTML = `<div id="dashboard-layout" data-ocg-selected-community-id="${communityId}"${groupAttribute}></div>`;
};

describe("dashboard context", () => {
  afterEach(() => {
    document.body.innerHTML = "";
    resetDashboardContextReloadState();
  });

  it("adds community and group headers from the group dashboard layout", () => {
    // Render a group dashboard page marker.
    setLoadedDashboardContext({ communityId: COMMUNITY_ID, groupId: GROUP_ID });
    const headers = new Headers();

    // Attach the loaded context to outgoing headers.
    addLoadedDashboardContextHeaders(headers);

    // Both identifiers are declared.
    expect(headers.get(SELECTED_COMMUNITY_ID_HEADER)).to.equal(COMMUNITY_ID);
    expect(headers.get(SELECTED_GROUP_ID_HEADER)).to.equal(GROUP_ID);
  });

  it("adds only the community header from the community dashboard layout", () => {
    // Render a community dashboard page marker with plain HTMX headers.
    setLoadedDashboardContext({ communityId: COMMUNITY_ID });
    const headers = { Existing: "value" };

    // Attach the loaded context to outgoing headers.
    addLoadedDashboardContextHeaders(headers);

    // Existing headers stay intact and no group header is added.
    expect(headers).to.deep.equal({
      Existing: "value",
      [SELECTED_COMMUNITY_ID_HEADER]: COMMUNITY_ID,
    });
  });

  it("adds no context headers outside dashboard pages", () => {
    // Render a layout without dashboard context markers.
    document.body.innerHTML = '<div id="dashboard-layout"></div>';
    const headers = new Headers();

    // Attach the loaded context to outgoing headers.
    addLoadedDashboardContextHeaders(headers);

    // No dashboard headers are declared.
    expect(headers.has(SELECTED_COMMUNITY_ID_HEADER)).to.equal(false);
    expect(headers.has(SELECTED_GROUP_ID_HEADER)).to.equal(false);
  });

  it("reloads to the dashboard root without the previous tab", () => {
    // A tab from the previous context may be forbidden in the new one.
    expect(getDashboardContextReloadUrl({ pathname: "/dashboard/group", search: "?tab=badges" })).to.equal(
      "/dashboard/group",
    );
  });

  it("detects the stale dashboard context response header", () => {
    expect(
      isStaleDashboardContextResponse(new Headers({ [STALE_DASHBOARD_CONTEXT_HEADER]: "true" })),
    ).to.equal(true);
    expect(
      isStaleDashboardContextResponse({
        getResponseHeader: (name) => (name === STALE_DASHBOARD_CONTEXT_HEADER ? "true" : null),
      }),
    ).to.equal(true);
    expect(isStaleDashboardContextResponse(new Headers())).to.equal(false);
    expect(isStaleDashboardContextResponse(null)).to.equal(false);
  });

  it("reloads once and queues the one-shot alert for a stale response", () => {
    // Capture reload requests instead of navigating.
    let reloads = 0;
    setDashboardContextReloadHandler(() => {
      reloads += 1;
    });
    const staleHeaders = new Headers({ [STALE_DASHBOARD_CONTEXT_HEADER]: "true" });

    // Handle the stale response and a later one while the reload is pending.
    const firstHandled = reloadIfDashboardContextStale(staleHeaders);
    const secondHandled = reloadIfDashboardContextStale(new Headers());

    // A single reload is requested and the alert is queued once.
    expect(firstHandled).to.equal(true);
    expect(secondHandled).to.equal(true);
    expect(isDashboardContextReloadRequested()).to.equal(true);
    expect(reloads).to.equal(1);
    expect(consumePendingDashboardContextRefreshAlert()).to.equal(true);
    expect(consumePendingDashboardContextRefreshAlert()).to.equal(false);
  });

  it("releases the pending reload guard when the page is restored from the back/forward cache", () => {
    // Request a reload, then simulate the browser restoring the cached page.
    setDashboardContextReloadHandler(() => {});
    reloadIfDashboardContextStale(new Headers({ [STALE_DASHBOARD_CONTEXT_HEADER]: "true" }));
    const target = new EventTarget();
    initializeDashboardContextState(target);

    // A regular pageshow keeps the guard, a persisted one clears it.
    target.dispatchEvent(Object.assign(new Event("pageshow"), { persisted: false }));
    expect(isDashboardContextReloadRequested()).to.equal(true);
    target.dispatchEvent(Object.assign(new Event("pageshow"), { persisted: true }));
    expect(isDashboardContextReloadRequested()).to.equal(false);
  });

  it("ignores responses without the stale dashboard context header", () => {
    // Capture reload requests instead of navigating.
    let reloads = 0;
    setDashboardContextReloadHandler(() => {
      reloads += 1;
    });

    // Handle a regular response.
    const handled = reloadIfDashboardContextStale(new Headers({ "Content-Type": "text/html" }));

    // Nothing is reloaded or queued.
    expect(handled).to.equal(false);
    expect(isDashboardContextReloadRequested()).to.equal(false);
    expect(reloads).to.equal(0);
    expect(consumePendingDashboardContextRefreshAlert()).to.equal(false);
  });
});
