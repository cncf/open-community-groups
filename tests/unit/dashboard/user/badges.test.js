import { expect } from "@open-wc/testing";

import {
  initializeBadgeList,
  moveBadge,
  revokeBadge,
  updateListing,
} from "/static/js/dashboard/user/badges.js";

const fixture = () => {
  const feedback = document.createElement("div");
  feedback.id = "user-badges-feedback";
  const list = document.createElement("ol");
  list.dataset.badgeOrderList = "";
  list.innerHTML = `
    <li data-user-badge-id="first" draggable="true">
      <input type="checkbox" data-badge-listing data-endpoint="/listing/first" checked>
      <button type="button" data-badge-move="down">Move down</button>
      <button type="button" data-badge-revoke data-endpoint="/badges/first" data-badge-name="First">Revoke</button>
    </li>
    <li data-user-badge-id="second" draggable="true">
      <button type="button" data-badge-move="up">Move up</button>
    </li>`;
  document.body.append(feedback, list);
  return { feedback, list };
};

describe("user dashboard badges", () => {
  let originalFetch;
  let originalSwal;

  beforeEach(() => {
    originalFetch = window.fetch;
    originalSwal = window.Swal;
    window.Swal = { fire: async () => ({}) };
  });

  afterEach(() => {
    document.getElementById("user-badges-feedback")?.remove();
    document.querySelector("[data-badge-order-list]")?.remove();
    document.querySelector("[data-user-badges-empty]")?.remove();
    window.fetch = originalFetch;
    window.Swal = originalSwal;
  });

  it("persists keyboard ordering and announces the new order", async () => {
    const { feedback, list } = fixture();
    let requestBody;
    window.fetch = async (_url, options) => {
      requestBody = JSON.parse(options.body);
      return new Response(null, { status: 204 });
    };

    await moveBadge(list.querySelector('[data-badge-move="down"]'));

    expect(
      [...list.children].map((item) => item.dataset.userBadgeId),
    ).to.deep.equal(["second", "first"]);
    expect(requestBody).to.deep.equal({ user_badge_ids: ["second", "first"] });
    expect(feedback.textContent).to.equal("Badge order saved.");
  });

  it("restores the previous order after a network failure", async () => {
    const { list } = fixture();
    window.fetch = async () => {
      throw new TypeError("Network unavailable");
    };

    await moveBadge(list.querySelector('[data-badge-move="down"]'));

    expect(
      [...list.children].map((item) => item.dataset.userBadgeId),
    ).to.deep.equal(["first", "second"]);
    expect(list.dataset.badgeOrderPending).to.equal(undefined);
  });

  it("blocks overlapping reorder saves and keeps boundary controls accurate", async () => {
    const { list } = fixture();
    let resolveRequest;
    let requestCount = 0;
    window.fetch = async () => {
      requestCount += 1;
      return new Promise((resolve) => {
        resolveRequest = resolve;
      });
    };
    initializeBadgeList(list);
    const moveDown = list.querySelector('[data-badge-move="down"]');

    const firstMove = moveBadge(moveDown);
    await Promise.resolve();
    await moveBadge(moveDown);

    expect(requestCount).to.equal(1);
    expect(
      [...list.children].map((item) => item.dataset.userBadgeId),
    ).to.deep.equal(["second", "first"]);
    expect(
      [...list.querySelectorAll("[data-badge-move]")].every(
        (button) => button.disabled,
      ),
    ).to.equal(true);

    resolveRequest(new Response(null, { status: 204 }));
    await firstMove;

    expect(list.dataset.badgeOrderPending).to.equal(undefined);
    expect(
      list.querySelector('[data-user-badge-id="second"] [data-badge-move="up"]')
        .disabled,
    ).to.equal(true);
    expect(
      list.querySelector(
        '[data-user-badge-id="first"] [data-badge-move="down"]',
      ).disabled,
    ).to.equal(true);
  });

  it("reverts listing controls after a recoverable error", async () => {
    const { list } = fixture();
    window.fetch = async () => new Response("failed", { status: 500 });
    const control = list.querySelector("[data-badge-listing]");
    control.checked = false;

    await updateListing(control);

    expect(control.checked).to.equal(true);
    expect(control.disabled).to.equal(false);
  });

  it("requires irreversible confirmation and removes a revoked badge after success", async () => {
    const { feedback, list } = fixture();
    const calls = [];
    window.Swal = {
      fire: async (options) => {
        calls.push(options);
        return options.title ? { isConfirmed: true } : {};
      },
    };
    window.fetch = async (_url, options) => {
      expect(options.method).to.equal("DELETE");
      return new Response(null, { status: 204 });
    };

    await revokeBadge(list.querySelector("[data-badge-revoke]"));

    expect(calls[0].text).to.include("cannot be undone");
    expect(calls[0].text).to.include("Show on profile");
    expect(list.querySelector('[data-user-badge-id="first"]')).to.equal(null);
    expect(feedback.textContent).to.equal("Badge permanently revoked.");
  });

  it("shows the empty state after revoking the final badge", async () => {
    const { list } = fixture();
    list.lastElementChild.remove();
    window.Swal = { fire: async () => ({ isConfirmed: true }) };
    window.fetch = async () => new Response(null, { status: 204 });

    await revokeBadge(list.querySelector("[data-badge-revoke]"));

    expect(document.querySelector("[data-badge-order-list]")).to.equal(null);
    expect(
      document.querySelector("[data-user-badges-empty]")?.textContent,
    ).to.include("No active badges yet");
  });

  it("persists pointer reordering through the same order endpoint", async () => {
    const { list } = fixture();
    const bodies = [];
    window.fetch = async (_url, options) => {
      bodies.push(JSON.parse(options.body));
      return new Response(null, { status: 204 });
    };
    initializeBadgeList(list);
    const first = list.firstElementChild;
    const second = list.lastElementChild;
    first.getBoundingClientRect = () => ({ top: 0 });
    second.getBoundingClientRect = () => ({ top: 0 });
    Object.defineProperty(second, "offsetHeight", {
      configurable: true,
      value: 10,
    });
    const dataTransfer = { effectAllowed: "" };
    const dragEvent = (type, clientY = 0) => {
      const event = new Event(type, { bubbles: true, cancelable: true });
      Object.defineProperty(event, "clientY", { value: clientY });
      Object.defineProperty(event, "dataTransfer", { value: dataTransfer });
      return event;
    };

    first.dispatchEvent(dragEvent("dragstart"));
    second.dispatchEvent(dragEvent("dragover", 10));
    first.dispatchEvent(dragEvent("dragend"));
    await Promise.resolve();
    await Promise.resolve();

    expect(bodies[0]).to.deep.equal({ user_badge_ids: ["second", "first"] });
  });
});
