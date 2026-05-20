import { expect } from "@open-wc/testing";

import {
  selectDashboardAndKeepTab,
  selectDashboardAndSwapBody,
} from "/static/js/common/dashboard-selection.js";
import { mockHtmx } from "/tests/unit/test-utils/globals.js";
import { mockFetch, mockPushState } from "/tests/unit/test-utils/network.js";

describe("dashboard selection", () => {
  let htmx;
  let fetchMock;
  let pushStateMock;

  beforeEach(() => {
    htmx = mockHtmx();
    fetchMock = mockFetch();
    pushStateMock = mockPushState();
  });

  afterEach(() => {
    htmx.restore();
    fetchMock.restore();
    pushStateMock.restore();
  });

  it("persists dashboard selection with htmx and keeps the current tab", async () => {
    // Select a dashboard and preserve the current tab query.
    await selectDashboardAndKeepTab("/dashboard/select/community-1");

    // HTMX receives the selection request with the dashboard swap target.
    expect(htmx.ajaxCalls).to.deep.equal([
      [
        "PUT",
        "/dashboard/select/community-1",
        {
          target: "body",
          indicator: "#dashboard-spinner",
        },
      ],
    ]);
  });

  it("persists the selection, swaps the dashboard body, and updates history", async () => {
    // Select a dashboard, swap body content, and update browser state.
    await selectDashboardAndSwapBody(
      "/dashboard/select/group-1",
      "/dashboard/groups/group-1",
    );

    // The selection request is persisted with the expected fetch options.
    expect(fetchMock.calls).to.have.length(1);
    const [url, options] = fetchMock.calls[0];
    expect(url).to.equal("/dashboard/select/group-1");
    expect(options.credentials).to.equal("same-origin");
    expect(options.headers.get("X-OCG-Fetch")).to.equal("true");
    expect(options.method).to.equal("PUT");

    // The dashboard body is swapped from the selected dashboard URL.
    expect(htmx.ajaxCalls).to.deep.equal([
      [
        "GET",
        "/dashboard/groups/group-1",
        {
          target: "body",
          indicator: "#dashboard-spinner",
        },
      ],
    ]);

    // Browser history points to the selected dashboard after the swap.
    expect(pushStateMock.calls).to.deep.equal([
      [{}, "", "/dashboard/groups/group-1"],
    ]);
  });

  it("throws when htmx is unavailable", async () => {
    // Remove HTMX before selecting a dashboard.
    delete window.htmx;

    // Capture the missing-HTMX error.
    let thrownError = null;

    // Attempt selection without HTMX available.
    try {
      await selectDashboardAndKeepTab("/dashboard/select/group-1");
    } catch (error) {
      thrownError = error;
    }

    // The selection helper reports that HTMX is required.
    expect(thrownError?.message).to.equal(
      "HTMX is required for dashboard selection.",
    );
  });

  it("stops when persisting the selection fails", async () => {
    // Make the selection persistence request fail.
    fetchMock.setImpl(async () => ({ ok: false, status: 500 }));

    // Capture the failed persistence error.
    let thrownError = null;

    // Attempt to select and swap a dashboard after persistence fails.
    try {
      await selectDashboardAndSwapBody(
        "/dashboard/select/group-1",
        "/dashboard/groups/group-1",
      );
    } catch (error) {
      thrownError = error;
    }

    // Failed persistence stops the body swap and history update.
    expect(thrownError?.message).to.equal(
      "Select dashboard entity failed: 500",
    );
    expect(htmx.ajaxCalls).to.deep.equal([]);
    expect(pushStateMock.calls).to.deep.equal([]);
  });
});
