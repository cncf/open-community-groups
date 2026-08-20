import { expect } from "@open-wc/testing";

import { initializeUserCheckIn } from "/static/js/dashboard/user/check-in.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("user check-in credential modal", () => {
  beforeEach(() => resetDom());
  afterEach(() => {
    window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }));
    resetDom();
  });

  const renderFixture = ({ name = "Ada Lovelace", photoUrl = "", ticketTitle = "" } = {}) => {
    document.body.innerHTML = `
      <section data-user-check-in-root data-user-name="${name}" data-username="ada" data-user-photo-url="${photoUrl}">
        <button type="button" data-user-check-in-open data-event-name="Open Source Summit" data-qr-code-url="/qr.svg" data-ticket-title="${ticketTitle}">Open</button>
        <div id="user-check-in-modal" class="hidden" aria-hidden="true">
          <button type="button" data-user-check-in-close>Close</button>
          <h2 id="user-check-in-modal-title"></h2>
          <div data-user-check-in-qr-status></div>
          <img id="user-check-in-qr-image" class="hidden">
          <button type="button" class="hidden" data-user-check-in-qr-retry>Try again</button>
          <div id="user-check-in-photo"></div>
          <p id="user-check-in-name"></p>
          <p id="user-check-in-username"></p>
          <p id="user-check-in-ticket"></p>
        </div>
      </section>
    `;
  };

  it("opens with event, attendee, ticket, and QR details", () => {
    // Render and open a credential with complete attendee and ticket details.
    renderFixture({ photoUrl: "/ada.png", ticketTitle: "Community ticket" });
    initializeUserCheckIn();
    document.querySelector("[data-user-check-in-open]").click();

    // Verify the modal presents the event, attendee, ticket, and QR code.
    expect(document.getElementById("user-check-in-modal").classList.contains("hidden")).to.equal(false);
    expect(document.getElementById("user-check-in-modal-title").textContent).to.equal("Open Source Summit");
    expect(document.getElementById("user-check-in-qr-image").getAttribute("src")).to.equal("/qr.svg");
    expect(document.getElementById("user-check-in-name").textContent).to.equal("Ada Lovelace");
    expect(document.getElementById("user-check-in-username").textContent).to.equal("@ada");
    expect(document.getElementById("user-check-in-ticket").textContent).to.equal("Community ticket");
    expect(document.querySelector("#user-check-in-photo img").getAttribute("src")).to.equal("/ada.png");
    expect(document.activeElement).to.equal(document.querySelector("[data-user-check-in-close]"));

    // Close the modal and verify focus returns to the event trigger.
    document.querySelector("[data-user-check-in-close]").click();
    expect(document.activeElement).to.equal(document.querySelector("[data-user-check-in-open]"));
  });

  it("rebinds controls from an HTMX history snapshot", () => {
    // Capture initialized check-in markup as an HTMX history snapshot.
    renderFixture({ ticketTitle: "Community ticket" });
    initializeUserCheckIn();
    const cachedRoot = document.querySelector("[data-user-check-in-root]").cloneNode(true);
    document.querySelector("[data-user-check-in-root]").replaceWith(cachedRoot);

    // Restore the cached root and open its credential modal.
    cachedRoot.dispatchEvent(new Event("htmx:historyRestore", { bubbles: true }));
    cachedRoot.querySelector("[data-user-check-in-open]").click();

    // Verify the restored controls populate and open the modal.
    expect(cachedRoot.querySelector("#user-check-in-modal").classList.contains("hidden")).to.equal(false);
    expect(cachedRoot.querySelector("#user-check-in-ticket").textContent).to.equal("Community ticket");
  });

  it("uses username, initials, and missing-ticket fallbacks", () => {
    // Open a credential without a display name, photo, or ticket title.
    renderFixture({ name: "" });
    initializeUserCheckIn();
    document.querySelector("[data-user-check-in-open]").click();

    // Verify username-derived identity and missing-ticket fallbacks.
    expect(document.getElementById("user-check-in-name").textContent).to.equal("ada");
    expect(document.getElementById("user-check-in-photo").textContent).to.equal("A");
    expect(document.getElementById("user-check-in-ticket").textContent).to.equal(
      "Ticket information unavailable",
    );
  });

  it("uses first and last name initials for the photo fallback", () => {
    // Open a photo-less credential for an attendee with a multi-part name.
    renderFixture({ name: "Ada Byron Lovelace" });
    initializeUserCheckIn();
    document.querySelector("[data-user-check-in-open]").click();

    // Verify the shared initials convention uses the first and last names.
    expect(document.getElementById("user-check-in-photo").textContent).to.equal("AL");
  });

  it("shows QR loading, failure, retry, and success states", () => {
    // Open a credential and read its QR loading controls.
    renderFixture();
    initializeUserCheckIn();
    document.querySelector("[data-user-check-in-open]").click();
    const image = document.getElementById("user-check-in-qr-image");
    const retry = document.querySelector("[data-user-check-in-qr-retry]");
    const status = document.querySelector("[data-user-check-in-qr-status]");

    // Fail the first image request and verify recovery guidance appears.
    expect(status.textContent).to.equal("Loading QR code…");
    image.dispatchEvent(new Event("error"));
    expect(status.textContent).to.equal("The QR code could not be loaded. Try again.");
    expect(retry.classList.contains("hidden")).to.equal(false);

    // Retry successfully and verify the QR code replaces the loading state.
    retry.click();
    expect(image.getAttribute("src")).to.equal("/qr.svg");
    image.dispatchEvent(new Event("load"));
    expect(image.classList.contains("hidden")).to.equal(false);
    expect(status.classList.contains("hidden")).to.equal(true);
  });

  it("closes an open modal restored from the browser cache", () => {
    // Open a credential modal before simulating a browser cache restore.
    renderFixture();
    initializeUserCheckIn();
    document.querySelector("[data-user-check-in-open]").click();

    // Restore the page from cache while the modal is active.
    window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }));

    // Verify the modal closes and releases its scroll lock.
    expect(document.getElementById("user-check-in-modal").classList.contains("hidden")).to.equal(true);
    expect(document.body.style.overflow).to.equal("");
  });

  it("closes an open modal before HTMX removes its root", () => {
    // Open a credential modal inside an HTMX-managed root.
    renderFixture();
    initializeUserCheckIn();
    const root = document.querySelector("[data-user-check-in-root]");
    document.querySelector("[data-user-check-in-open]").click();

    // Announce root cleanup while the modal is active.
    root.dispatchEvent(new Event("htmx:beforeCleanupElement", { bubbles: true }));

    // Verify cleanup closes the modal and releases its scroll lock.
    expect(document.getElementById("user-check-in-modal").classList.contains("hidden")).to.equal(true);
    expect(document.body.style.overflow).to.equal("");
  });
});
