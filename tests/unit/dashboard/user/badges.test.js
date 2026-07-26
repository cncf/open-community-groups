import { expect } from "@open-wc/testing";

import {
  downloadBadge,
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
    <li data-user-badge-id="first">
      <span data-badge-position>1</span>
      <button type="button" data-badge-drag-handle draggable="true">Reorder First</button>
      <div data-badge-card></div>
      <input type="checkbox" data-badge-listing data-endpoint="/listing/first" checked>
      <a href="/badges/first/export" download data-badge-download data-badge-name="First">Download</a>
      <button type="button" data-badge-revoke data-endpoint="/badges/first" data-badge-name="First">Revoke</button>
    </li>
    <li data-user-badge-id="second">
      <span data-badge-position>2</span>
      <button type="button" data-badge-drag-handle draggable="true">Reorder Second</button>
      <div data-badge-card></div>
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

  it("persists arrow-key ordering, updates positions, and announces the new order", async () => {
    const { feedback, list } = fixture();
    let requestBody;
    window.fetch = async (_url, options) => {
      requestBody = JSON.parse(options.body);
      return new Response(null, { status: 204 });
    };
    initializeBadgeList(list);

    list
      .querySelector('[data-user-badge-id="first"] [data-badge-drag-handle]')
      .dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "ArrowDown" }));
    await Promise.resolve();
    await Promise.resolve();

    expect([...list.children].map((item) => item.dataset.userBadgeId)).to.deep.equal(["second", "first"]);
    expect(
      [...list.querySelectorAll("[data-badge-position]")].map((position) => position.textContent),
    ).to.deep.equal(["1", "2"]);
    expect(requestBody).to.deep.equal({ user_badge_ids: ["second", "first"] });
    expect(feedback.textContent).to.equal("Badge order saved.");
  });

  it("restores the previous order after a network failure", async () => {
    const { list } = fixture();
    window.fetch = async () => {
      throw new TypeError("Network unavailable");
    };

    await moveBadge(list.querySelector("[data-badge-drag-handle]"), "down");

    expect([...list.children].map((item) => item.dataset.userBadgeId)).to.deep.equal(["first", "second"]);
    expect(list.dataset.badgeOrderPending).to.equal(undefined);
  });

  it("blocks overlapping reorder saves and restores the drag handles", async () => {
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
    const dragHandle = list.querySelector("[data-badge-drag-handle]");

    const firstMove = moveBadge(dragHandle, "down");
    await Promise.resolve();
    await moveBadge(dragHandle, "up");

    expect(requestCount).to.equal(1);
    expect([...list.children].map((item) => item.dataset.userBadgeId)).to.deep.equal(["second", "first"]);
    expect(
      [...list.querySelectorAll("[data-badge-drag-handle]")].every((handle) => handle.disabled),
    ).to.equal(true);

    resolveRequest(new Response(null, { status: 204 }));
    await firstMove;

    expect(list.dataset.badgeOrderPending).to.equal(undefined);
    expect(
      [...list.querySelectorAll("[data-badge-drag-handle]")].every(
        (handle) => !handle.disabled && handle.draggable,
      ),
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

  it("explains baked credentials and downloads after confirmation", async () => {
    const { list } = fixture();
    const link = list.querySelector("[data-badge-download]");
    let alertOptions;
    let downloadHref;
    window.Swal = {
      fire: async (options) => {
        alertOptions = options;
        return { isConfirmed: true };
      },
    };
    document.addEventListener(
      "click",
      (event) => {
        if (event.target !== link && event.target instanceof HTMLAnchorElement) {
          event.preventDefault();
          downloadHref = event.target.href;
        }
      },
      { capture: true, once: true },
    );

    await downloadBadge(link);

    expect(alertOptions.title).to.equal("Download First badge?");
    expect(alertOptions.html).to.include("signed Open Badges 3.0 credential data");
    expect(alertOptions.html).to.include("does not include your email address or username");
    expect(alertOptions.confirmButtonText).to.equal("Download PNG");
    expect(alertOptions.cancelButtonText).to.equal("Cancel");
    expect(downloadHref).to.equal(link.href);
    expect(link.dataset.badgeDownloadPending).to.equal(undefined);
  });

  it("keeps focus on the download link when confirmation is cancelled", async () => {
    const { list } = fixture();
    const link = list.querySelector("[data-badge-download]");
    window.Swal = { fire: async () => ({ isConfirmed: false }) };

    await downloadBadge(link);

    expect(document.activeElement).to.equal(link);
    expect(link.dataset.badgeDownloadPending).to.equal(undefined);
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
    expect(list.querySelector("[data-badge-drag-handle]").disabled).to.equal(true);
    expect(feedback.textContent).to.equal("Badge permanently revoked.");
  });

  it("shows the empty state after revoking the final badge", async () => {
    const { list } = fixture();
    list.lastElementChild.remove();
    window.Swal = { fire: async () => ({ isConfirmed: true }) };
    window.fetch = async () => new Response(null, { status: 204 });

    await revokeBadge(list.querySelector("[data-badge-revoke]"));

    expect(document.querySelector("[data-badge-order-list]")).to.equal(null);
    expect(document.querySelector("[data-user-badges-empty]")?.textContent).to.include(
      "No active badges yet",
    );
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
    const firstHandle = first.querySelector("[data-badge-drag-handle]");
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

    firstHandle.dispatchEvent(dragEvent("dragstart"));
    second.dispatchEvent(dragEvent("dragover", 10));

    expect(second.querySelector("[data-badge-card]").classList.contains("ring-2")).to.equal(true);

    firstHandle.dispatchEvent(dragEvent("dragend"));
    await Promise.resolve();
    await Promise.resolve();

    expect(bodies[0]).to.deep.equal({ user_badge_ids: ["second", "first"] });
    expect(first.classList.contains("opacity-70")).to.equal(false);
    expect(second.querySelector("[data-badge-card]").classList.contains("ring-2")).to.equal(false);
  });
});
