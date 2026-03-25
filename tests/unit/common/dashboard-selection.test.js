import { expect } from "@open-wc/testing";

import {
  selectDashboardAndKeepTab,
  selectDashboardAndSwapBody,
} from "/static/js/common/dashboard-selection.js";

describe("dashboard selection", () => {
  const originalFetch = globalThis.fetch;
  const originalHtmx = window.htmx;
  const originalPushState = window.history.pushState.bind(window.history);

  let ajaxCalls;
  let fetchCalls;
  let pushedUrls;

  beforeEach(() => {
    ajaxCalls = [];
    fetchCalls = [];
    pushedUrls = [];

    window.htmx = {
      ajax: async (...args) => {
        ajaxCalls.push(args);
      },
    };

    globalThis.fetch = async (...args) => {
      fetchCalls.push(args);
      return { ok: true, status: 200 };
    };

    window.history.pushState = (...args) => {
      pushedUrls.push(args);
    };
  });

  afterEach(() => {
    window.htmx = originalHtmx;
    globalThis.fetch = originalFetch;
    window.history.pushState = originalPushState;
  });

  it("persists dashboard selection with htmx and keeps the current tab", async () => {
    await selectDashboardAndKeepTab("/dashboard/select/community-1");

    expect(ajaxCalls).to.deep.equal([
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

    expect(fetchCalls).to.deep.equal([
      [
        "/dashboard/select/group-1",
        {
          method: "PUT",
          credentials: "same-origin",
        },
      ],
    ]);

    expect(ajaxCalls).to.deep.equal([
      [
        "GET",
        "/dashboard/groups/group-1",
        {
          target: "body",
          indicator: "#dashboard-spinner",
        },
      ],
    ]);

    expect(pushedUrls).to.deep.equal([[{}, "", "/dashboard/groups/group-1"]]);
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
    globalThis.fetch = async (...args) => {
      fetchCalls.push(args);
      return { ok: false, status: 500 };
    };

    let thrownError = null;

    try {
      await selectDashboardAndSwapBody("/dashboard/select/group-1", "/dashboard/groups/group-1");
    } catch (error) {
      thrownError = error;
    }

    expect(thrownError?.message).to.equal("Select dashboard entity failed: 500");
    expect(ajaxCalls).to.deep.equal([]);
    expect(pushedUrls).to.deep.equal([]);
  });
});
