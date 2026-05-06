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
    await selectDashboardAndKeepTab("/dashboard/select/community-1");

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
    await selectDashboardAndSwapBody("/dashboard/select/group-1", "/dashboard/groups/group-1");

    expect(fetchMock.calls).to.have.length(1);
    const [url, options] = fetchMock.calls[0];
    expect(url).to.equal("/dashboard/select/group-1");
    expect(options.credentials).to.equal("same-origin");
    expect(options.headers.get("X-OCG-Fetch")).to.equal("true");
    expect(options.method).to.equal("PUT");

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

    expect(pushStateMock.calls).to.deep.equal([[{}, "", "/dashboard/groups/group-1"]]);
  });

  it("throws when htmx is unavailable", async () => {
    delete window.htmx;

    let thrownError = null;

    try {
      await selectDashboardAndKeepTab("/dashboard/select/group-1");
    } catch (error) {
      thrownError = error;
    }

    expect(thrownError?.message).to.equal("HTMX is required for dashboard selection.");
  });

  it("stops when persisting the selection fails", async () => {
    fetchMock.setImpl(async () => ({ ok: false, status: 500 }));

    let thrownError = null;

    try {
      await selectDashboardAndSwapBody("/dashboard/select/group-1", "/dashboard/groups/group-1");
    } catch (error) {
      thrownError = error;
    }

    expect(thrownError?.message).to.equal("Select dashboard entity failed: 500");
    expect(htmx.ajaxCalls).to.deep.equal([]);
    expect(pushStateMock.calls).to.deep.equal([]);
  });
});
