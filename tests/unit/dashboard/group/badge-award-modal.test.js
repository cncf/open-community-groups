import { expect, waitUntil } from "@open-wc/testing";

import "/static/js/dashboard/group/badge-award-modal.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

const badge = {
  badge_id: "00000000-0000-0000-0000-000000000001",
  description: "Recognizes participation",
  image_file_name: "badge.png",
  name: "Participant",
};

const flush = async (element) => {
  await Promise.resolve();
  await Promise.resolve();
  await element.updateComplete;
};

describe("badge-award-modal", () => {
  useMountedElementsCleanup("badge-award-modal");
  let originalFetch;

  beforeEach(() => {
    originalFetch = window.fetch;
  });

  afterEach(() => {
    window.fetch = originalFetch;
  });

  it("models loading, ready, selection, submitting, and success states", async () => {
    const calls = [];
    window.fetch = async (url, options = {}) => {
      calls.push({ url: String(url), options });
      if (options.method === "POST") {
        return new Response(JSON.stringify({ queued_count: 1, skipped_count: 0 }), {
          status: 201,
          headers: { "Content-Type": "application/json" },
        });
      }
      return new Response(JSON.stringify({ badges: [badge], total: 1 }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    };
    const element = await mountLitComponent("badge-award-modal");
    const trigger = document.createElement("button");
    document.body.append(trigger);

    element.open({
      eventId: "00000000-0000-0000-0000-000000000002",
      trigger,
      userIds: ["00000000-0000-0000-0000-000000000003"],
    });
    expect(element._state).to.equal("loading");
    await waitUntil(() => element._state === "ready", "badge options should load");
    await element.updateComplete;

    expect(element._state).to.equal("ready");
    expect(element.querySelector("dialog[aria-labelledby]")).to.not.equal(null);
    const badgeList = element.querySelector('[role="radiogroup"]');
    const badgeControl = element.querySelector('input[name="award-badge"]');
    const badgeOption = badgeControl.closest("label");
    const badgeOptionSurface = badgeControl.nextElementSibling;
    expect(badgeList.classList.contains("p-1")).to.equal(true);
    expect(badgeList.classList.contains("scroll-p-1")).to.equal(true);
    expect(badgeControl.classList.contains("peer")).to.equal(true);
    expect(badgeOptionSurface.classList.contains("peer-checked:ring-2")).to.equal(true);
    expect(badgeOptionSurface.classList.contains("peer-focus-visible:ring-2")).to.equal(true);
    expect(badgeOption.querySelectorAll(".pointer-events-none")).to.have.length(2);
    badgeControl.click();
    await element.updateComplete;
    expect(element._selectedBadgeId).to.equal(badge.badge_id);

    const firstAward = element._award();
    const duplicateAward = element._award();
    expect(element._state).to.equal("submitting");
    await Promise.all([firstAward, duplicateAward]);
    await element.updateComplete;

    expect(element._state).to.equal("success");
    expect(element.textContent).to.include("1 new credential queued for issuance");
    expect(document.activeElement).to.equal(element.querySelector("[data-badge-award-close]"));
    expect(calls.filter((call) => call.options.method === "POST")).to.have.length(1);
    const body = JSON.parse(calls.find((call) => call.options.method === "POST").options.body);
    expect(body).to.deep.equal({
      badge_id: badge.badge_id,
      event_id: "00000000-0000-0000-0000-000000000002",
      user_ids: ["00000000-0000-0000-0000-000000000003"],
    });
    trigger.remove();
  });

  it("renders empty and recoverable error states while preserving selection", async () => {
    let mode = "empty";
    window.fetch = async (_url, options = {}) => {
      if (options.method === "POST") {
        return new Response("Try again", { status: 500 });
      }
      return new Response(JSON.stringify({ badges: mode === "empty" ? [] : [badge], total: 1 }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    };
    const element = await mountLitComponent("badge-award-modal");
    element.open({ eventId: "event", trigger: document.body, userIds: ["user"] });
    await waitUntil(() => element._state === "empty", "the empty badge state should render");
    await element.updateComplete;

    expect(element._state).to.equal("empty");
    expect(element.textContent).to.include("No badges matched");

    mode = "ready";
    await element._loadBadges();
    await element.updateComplete;
    element._selectedBadgeId = badge.badge_id;
    await element._award();
    await element.updateComplete;

    expect(element._state).to.equal("error");
    expect(element._selectedBadgeId).to.equal(badge.badge_id);
    expect(element.textContent).to.include("Try again");
  });

  it("clears stale selection and disables award controls while new options load", async () => {
    let holdSearch = false;
    let resolveSearch;
    let postCount = 0;
    window.fetch = async (_url, options = {}) => {
      if (options.method === "POST") {
        postCount += 1;
        return new Response(null, { status: 204 });
      }
      if (holdSearch) {
        return new Promise((resolve) => {
          resolveSearch = resolve;
        });
      }
      return new Response(JSON.stringify({ badges: [badge], total: 1 }), {
        headers: { "Content-Type": "application/json" },
      });
    };
    const element = await mountLitComponent("badge-award-modal");
    element.open({ eventId: "event", trigger: document.body, userIds: ["user"] });
    await waitUntil(() => element._state === "ready", "badge options should load");
    element._selectedBadgeId = badge.badge_id;
    holdSearch = true;

    const pendingSearch = element._loadBadges();
    await element.updateComplete;
    await element._award();

    expect(element._state).to.equal("loading");
    expect(element._selectedBadgeId).to.equal("");
    expect(element.querySelector('[type="search"]').disabled).to.equal(true);
    expect(element.querySelectorAll('input[name="award-scope"]')).to.have.length(0);
    expect(element.querySelector(".btn-primary").disabled).to.equal(true);
    expect(postCount).to.equal(0);

    resolveSearch(
      new Response(JSON.stringify({ badges: [badge], total: 1 }), {
        headers: { "Content-Type": "application/json" },
      }),
    );
    await pendingSearch;
  });

  it("ignores an award response from a previous opening", async () => {
    let pendingAward;
    window.fetch = async (_url, options = {}) => {
      if (options.method === "POST") {
        return new Promise((resolve) => {
          pendingAward = resolve;
        });
      }
      return new Response(JSON.stringify({ badges: [badge], total: 1 }), {
        headers: { "Content-Type": "application/json" },
      });
    };
    const element = await mountLitComponent("badge-award-modal");
    element.open({
      eventId: "old-event",
      trigger: document.body,
      userIds: ["old-user"],
    });
    await waitUntil(() => element._state === "ready", "old badge options should load");
    element._selectedBadgeId = badge.badge_id;
    const oldAward = element._award();
    await waitUntil(() => Boolean(pendingAward), "old award should start");

    element.open({
      eventId: "new-event",
      trigger: document.body,
      userIds: ["new-user"],
    });
    await waitUntil(() => element._state === "ready", "new badge options should load");
    pendingAward(
      new Response(JSON.stringify({ queued_count: 1, skipped_count: 0 }), {
        headers: { "Content-Type": "application/json" },
      }),
    );
    await oldAward;
    await element.updateComplete;

    expect(element._state).to.equal("ready");
    expect(element._success).to.equal(null);
  });

  it("ignores stale searches, restores focus on Escape, and aborts work on disconnect", async () => {
    const responses = [];
    window.fetch = (_url, options = {}) =>
      new Promise((resolve) => {
        responses.push({ options, resolve });
      });
    const element = await mountLitComponent("badge-award-modal");
    const trigger = document.createElement("button");
    document.body.append(trigger);
    trigger.focus();
    element.open({ eventId: "event", trigger, userIds: ["user"] });
    await element.updateComplete;
    expect(document.activeElement).to.equal(element.querySelector("[data-badge-award-dialog]"));
    element._query = "new";
    const newerRequest = element._loadBadges();

    responses[1].resolve(
      new Response(JSON.stringify({ badges: [badge], total: 1 }), {
        headers: { "Content-Type": "application/json" },
      }),
    );
    await newerRequest;
    responses[0].resolve(
      new Response(JSON.stringify({ badges: [], total: 0 }), {
        headers: { "Content-Type": "application/json" },
      }),
    );
    await flush(element);
    expect(element._state).to.equal("ready");

    element.close();
    await element.updateComplete;
    expect(element._isOpen).to.equal(false);
    expect(document.activeElement).to.equal(trigger);

    element.remove();
    expect(responses[1].options.signal.aborted).to.equal(true);
    trigger.remove();
  });

  it("keeps focus in the dialog on load failure and aborts a pending award on disconnect", async () => {
    let awardRequest;
    let loadFails = true;
    window.fetch = async (_url, options = {}) => {
      if (options.method === "POST") {
        return new Promise((resolve) => {
          awardRequest = { options, resolve };
        });
      }
      if (loadFails) {
        return new Response("Unavailable", { status: 503 });
      }
      return new Response(JSON.stringify({ badges: [badge], total: 1 }), {
        headers: { "Content-Type": "application/json" },
      });
    };
    const element = await mountLitComponent("badge-award-modal");
    element.open({ eventId: "event", trigger: document.body, userIds: ["user"] });
    await waitUntil(() => element._state === "error", "the badge load should fail");
    expect(document.activeElement).to.equal(element.querySelector("[data-badge-award-dialog]"));

    loadFails = false;
    await element._loadBadges();
    await waitUntil(() => element._state === "ready", "badge options should load");
    element._selectedBadgeId = badge.badge_id;

    const pendingAward = element._award();
    await waitUntil(() => Boolean(awardRequest), "the award request should start");
    element.remove();

    expect(awardRequest.options.signal.aborted).to.equal(true);
    awardRequest.resolve(new Response(null, { status: 204 }));
    await pendingAward;
  });
});
