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
    document.querySelector("[data-test-menu-award]")?.remove();
    document.querySelector("[data-test-bulk-speaker-award]")?.remove();
    window.fetch = originalFetch;
  });

  it("keeps internal reactive properties out of observed attributes", () => {
    // Read the custom element's reactive property declarations.
    const properties = customElements.get("badge-award-modal").properties;

    // All underscored internal values are state-only and not reflected as attributes.
    Object.values(properties).forEach((property) => {
      expect(property.state).to.equal(true);
    });
  });

  it("clamps badge option titles to two lines and omits descriptions", async () => {
    window.fetch = async () =>
      new Response(JSON.stringify({ badges: [badge], total: 1 }), {
        headers: { "Content-Type": "application/json" },
      });
    const element = await mountLitComponent("badge-award-modal");

    element.open({ eventId: "event", trigger: document.body, userIds: ["user"] });
    await waitUntil(() => element._state === "ready", "badge options should load");

    const badgeTitle = element.querySelector(".line-clamp-2");
    const badgeOptionSurface = element.querySelector('input[name="award-badge"]').nextElementSibling;
    expect(badgeTitle.textContent.trim()).to.equal(badge.name);
    expect(badgeTitle.classList.contains("break-words")).to.equal(true);
    expect(badgeOptionSurface.classList.contains("items-center")).to.equal(true);
    expect(element.textContent).not.to.include(badge.description);
  });

  it("shows the all-speakers scope in the badge picker without a separate confirmation", async () => {
    window.fetch = async () =>
      new Response(JSON.stringify({ badges: [badge], total: 1 }), {
        headers: { "Content-Type": "application/json" },
      });
    const element = await mountLitComponent("badge-award-modal");
    const trigger = document.createElement("button");
    trigger.dataset.testBulkSpeakerAward = "";
    trigger.dataset.badgeAwardOpen = "";
    trigger.dataset.badgeAwardAllSpeakers = "";
    trigger.dataset.eventId = "event-1";
    trigger.dataset.userIds = "speaker-1,session-speaker-2";
    document.body.append(trigger);

    trigger.click();
    await waitUntil(() => element._state === "ready", "badge options should load");

    expect(element._isOpen).to.equal(true);
    expect(element._allSpeakersAward).to.equal(true);
    expect(element._userIds).to.deep.equal(["speaker-1", "session-speaker-2"]);
    const allSpeakersNotice = element.querySelector("[data-badge-award-all-speakers-notice]");
    const searchForm = element.querySelector("form");
    expect(allSpeakersNotice.textContent).to.include("all event speakers");
    expect(allSpeakersNotice.textContent).to.include("individual sessions");
    expect(
      allSpeakersNotice.compareDocumentPosition(searchForm) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).to.not.equal(0);
  });

  it("restores focus to an action menu summary after closing", async () => {
    window.fetch = async () =>
      new Response(JSON.stringify({ badges: [badge], total: 1 }), {
        headers: { "Content-Type": "application/json" },
      });
    const element = await mountLitComponent("badge-award-modal");
    const menu = document.createElement("details");
    menu.dataset.testMenuAward = "";
    menu.open = true;
    menu.innerHTML = `
      <summary>Actions</summary>
      <button data-badge-award-open data-event-id="event-1" data-user-ids="user-1">Award badge</button>`;
    document.body.append(menu);

    const summary = menu.querySelector("summary");
    menu.querySelector("[data-badge-award-open]").click();
    await waitUntil(() => element._state === "ready", "badge options should load");

    element.close();

    expect(document.activeElement).to.equal(summary);
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

  it("renders empty states and preserves selection for an award retry", async () => {
    let mode = "empty";
    let awardAttempts = 0;
    window.fetch = async (_url, options = {}) => {
      if (options.method === "POST") {
        awardAttempts += 1;
        return awardAttempts === 1
          ? new Response("Try again", { status: 500 })
          : new Response(JSON.stringify({ queued_count: 1, skipped_count: 0 }), {
              headers: { "Content-Type": "application/json" },
            });
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

    expect(element._state).to.equal("ready");
    expect(element._selectedBadgeId).to.equal(badge.badge_id);
    expect(element.textContent).to.include("Try again");
    expect(element.querySelector(".btn-primary").disabled).to.equal(false);

    await element._award();

    expect(element._state).to.equal("success");
  });

  it("filters badges as the search query changes and clears the query inline", async () => {
    const requestedUrls = [];
    window.fetch = async (url) => {
      requestedUrls.push(String(url));
      return new Response(JSON.stringify({ badges: [badge], total: 1 }), {
        headers: { "Content-Type": "application/json" },
      });
    };
    const element = await mountLitComponent("badge-award-modal");
    element.open({ eventId: "event", trigger: document.body, userIds: ["user"] });
    await waitUntil(() => element._state === "ready", "badge options should load");

    const searchInput = element.querySelector("[data-badge-search]");
    expect(searchInput.form.querySelector('button[type="submit"]')).to.equal(null);
    searchInput.value = "Host";
    searchInput.dispatchEvent(new InputEvent("input", { bubbles: true }));
    await waitUntil(() => requestedUrls.length === 2, "badge query should load after a short delay");
    await waitUntil(() => element._state === "ready", "filtered badge options should load");

    expect(requestedUrls[1]).to.equal("/dashboard/group/badges/options?query=Host");
    const clearButton = element.querySelector("[data-badge-search-clear]");
    expect(clearButton).to.not.equal(null);
    clearButton.click();
    await waitUntil(() => requestedUrls.length === 3, "clearing should restore all badge options");

    expect(element._query).to.equal("");
    expect(requestedUrls[2]).to.equal("/dashboard/group/badges/options?");
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
    expect(document.activeElement).to.equal(element.querySelector('[aria-label="Close award badge dialog"]'));
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
    const searchInput = element.querySelector("[data-badge-search]");
    expect(document.activeElement).to.equal(searchInput);
    expect(element.textContent).to.include(
      "We couldn't load the badges. Check your connection and try again.",
    );
    const errorAlert = element.querySelector('[role="alert"]');
    expect(errorAlert.classList.contains("bg-red-50")).to.equal(true);
    expect(errorAlert.querySelector(".icon-error")).to.not.equal(null);

    loadFails = false;
    searchInput.form.dispatchEvent(new Event("submit", { cancelable: true }));
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
