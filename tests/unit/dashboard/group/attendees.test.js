import { expect } from "@open-wc/testing";

import "/static/js/dashboard/group/attendees.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { setupDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("dashboard group attendees", () => {
  let env;
  let fetchMock;

  beforeEach(() => {
    env = setupDashboardTestEnv({
      path: "/dashboard/group/attendees",
      withScroll: true,
      withSwal: true,
    });
    fetchMock = mockFetch();
  });

  afterEach(() => {
    fetchMock.restore();
    env.restore();
  });

  const initializeAttendeesUi = () => {
    document.body.dispatchEvent(new CustomEvent("htmx:load", { bubbles: true }));
  };

  it("updates the attendee notification endpoint before opening the modal", () => {
    document.body.innerHTML = `
      <button
        id="open-attendee-notification-modal"
        type="button"
        data-event-id="event-42"
      >
        Notify attendees
      </button>
      <div id="attendee-notification-modal" class="hidden"></div>
      <button id="close-attendee-notification-modal" type="button">Close</button>
      <button id="cancel-attendee-notification" type="button">Cancel</button>
      <div id="overlay-attendee-notification-modal"></div>
      <form id="attendee-notification-form"></form>
    `;

    initializeAttendeesUi();

    const form = document.getElementById("attendee-notification-form");
    const modal = document.getElementById("attendee-notification-modal");
    document.getElementById("open-attendee-notification-modal")?.click();

    expect(form.getAttribute("hx-post")).to.equal("/dashboard/group/notifications/event-42");
    expect(modal.classList.contains("hidden")).to.equal(false);
  });

  it("keeps the check-in toggle disabled after a successful check-in", async () => {
    document.body.innerHTML = `
      <label class="cursor-pointer">
        <input
          type="checkbox"
          class="check-in-toggle"
          data-url="/dashboard/group/attendees/check-in/7"
        />
      </label>
    `;

    initializeAttendeesUi();

    const checkbox = document.querySelector(".check-in-toggle");
    const label = checkbox.closest("label");
    checkbox.checked = true;
    checkbox.dispatchEvent(new Event("change", { bubbles: true }));
    await waitForMicrotask();

    expect(fetchMock.calls).to.deep.equal([
      ["/dashboard/group/attendees/check-in/7", { method: "POST" }],
    ]);
    expect(checkbox.disabled).to.equal(true);
    expect(label.classList.contains("cursor-not-allowed")).to.equal(true);
    expect(label.classList.contains("cursor-pointer")).to.equal(false);
    expect(env.swal.calls).to.have.length(0);
  });

  it("reverts the check-in toggle and shows an error when the request fails", async () => {
    fetchMock.setImpl(async () => ({ ok: false, status: 500 }));

    document.body.innerHTML = `
      <label class="cursor-pointer">
        <input
          type="checkbox"
          class="check-in-toggle"
          data-url="/dashboard/group/attendees/check-in/8"
        />
      </label>
    `;

    initializeAttendeesUi();

    const checkbox = document.querySelector(".check-in-toggle");
    const label = checkbox.closest("label");
    checkbox.checked = true;
    checkbox.dispatchEvent(new Event("change", { bubbles: true }));
    await waitForMicrotask();

    expect(checkbox.checked).to.equal(false);
    expect(checkbox.disabled).to.equal(false);
    expect(label.classList.contains("cursor-pointer")).to.equal(true);
    expect(label.classList.contains("cursor-not-allowed")).to.equal(false);
    expect(env.swal.calls).to.have.length(1);
    expect(env.swal.calls[0]).to.include({
      text: "Failed to check in attendee. Please try again.",
      icon: "error",
    });
  });
});
