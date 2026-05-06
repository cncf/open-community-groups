import { expect } from "@open-wc/testing";

import { initUserDropdown } from "/static/js/common/header.js";
import { resetDom, setLocationPath, mockScrollTo } from "/tests/unit/test-utils/dom.js";
import {
  dispatchHtmxAfterRequest,
  dispatchHtmxAfterSwap,
  dispatchHtmxBeforeRequest,
} from "/tests/unit/test-utils/htmx.js";

describe("header", () => {
  const originalPath = window.location.pathname;

  let scrollToMock;

  beforeEach(() => {
    resetDom();
    scrollToMock = mockScrollTo();
  });

  afterEach(() => {
    resetDom();
    scrollToMock.restore();
    setLocationPath(originalPath);
  });

  it("toggles the dropdown and closes it on outside click", () => {
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden">
        <a>Profile</a>
      </div>
      <div id="outside">Outside</div>
    `;

    initUserDropdown();

    const button = document.getElementById("user-dropdown-button");
    const dropdown = document.getElementById("user-dropdown");

    button.click();
    expect(dropdown.classList.contains("hidden")).to.equal(false);

    document.getElementById("outside").dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(dropdown.classList.contains("hidden")).to.equal(true);
  });

  it("allows avatar clicks to close other open popovers", () => {
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden"></div>
    `;

    initUserDropdown();

    const button = document.getElementById("user-dropdown-button");
    let documentClickReceived = false;
    const handleDocumentClick = () => {
      documentClickReceived = true;
    };

    document.addEventListener("click", handleDocumentClick);
    button.click();
    document.removeEventListener("click", handleDocumentClick);

    expect(documentClickReceived).to.equal(true);
  });

  it("closes the dropdown on escape and focuses the button", () => {
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown">
        <a>Profile</a>
      </div>
    `;

    initUserDropdown();

    const button = document.getElementById("user-dropdown-button");
    const dropdown = document.getElementById("user-dropdown");
    let focused = false;

    button.focus = () => {
      focused = true;
    };

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));

    expect(dropdown.classList.contains("hidden")).to.equal(true);
    expect(focused).to.equal(true);
  });

  it("closes on regular link clicks but keeps the dropdown open for spinner links", () => {
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown">
        <a id="profile-link">Profile</a>
        <a id="loading-link"><span class="hx-spinner"></span>Loading</a>
      </div>
    `;

    initUserDropdown();

    const dropdown = document.getElementById("user-dropdown");
    document.getElementById("profile-link").dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(dropdown.classList.contains("hidden")).to.equal(true);

    dropdown.classList.remove("hidden");
    document.getElementById("loading-link").dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(dropdown.classList.contains("hidden")).to.equal(false);
  });

  it("scrolls to the top after dashboard swaps", () => {
    setLocationPath("/dashboard/groups");
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden"></div>
      <div id="dashboard-content"></div>
    `;

    initUserDropdown();

    dispatchHtmxAfterSwap(document, {
      target: document.getElementById("dashboard-content"),
    });

    expect(scrollToMock.calls).to.deep.equal([{ top: 0, behavior: "auto" }]);
  });

  it("does not scroll after swaps outside dashboard pages", () => {
    setLocationPath("/communities/cncf");
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden"></div>
      <div id="dashboard-content"></div>
    `;

    initUserDropdown();

    dispatchHtmxAfterSwap(document, {
      target: document.getElementById("dashboard-content"),
    });

    expect(scrollToMock.calls).to.deep.equal([]);
  });

  it("shows loading on boosted header nav links after a short delay", async () => {
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden"></div>
      <a
        id="explore-link"
        href="/explore"
        hx-boost="true"
        data-header-nav-link
      >
        Explore
      </a>
    `;

    initUserDropdown();

    const link = document.getElementById("explore-link");
    dispatchHtmxBeforeRequest(link, { elt: link });

    expect(link.classList.contains("header-nav-link-pending")).to.equal(false);

    await new Promise((resolve) => setTimeout(resolve, 140));

    expect(link.classList.contains("header-nav-link-pending")).to.equal(true);
    expect(link.getAttribute("aria-busy")).to.equal("true");

    dispatchHtmxAfterRequest(link, { elt: link });

    expect(link.classList.contains("header-nav-link-pending")).to.equal(false);
    expect(link.hasAttribute("aria-busy")).to.equal(false);
  });

  it("skips header nav loading when a boosted request finishes quickly", async () => {
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden"></div>
      <a
        id="stats-link"
        href="/stats"
        hx-boost="true"
        data-header-nav-link
      >
        Stats
      </a>
    `;

    initUserDropdown();

    const link = document.getElementById("stats-link");
    dispatchHtmxBeforeRequest(link, { elt: link });
    dispatchHtmxAfterRequest(link, { elt: link });

    await new Promise((resolve) => setTimeout(resolve, 140));

    expect(link.classList.contains("header-nav-link-pending")).to.equal(false);
    expect(link.hasAttribute("aria-busy")).to.equal(false);
  });

  it("shows loading on boosted header nav link clicks", async () => {
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden"></div>
      <a
        id="explore-link"
        href="/explore"
        hx-boost="true"
        data-header-nav-link
      >
        Explore
      </a>
    `;

    initUserDropdown();

    const link = document.getElementById("explore-link");
    document.addEventListener("click", (event) => event.preventDefault(), { once: true });
    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, button: 0 }));

    await new Promise((resolve) => setTimeout(resolve, 140));

    expect(link.classList.contains("header-nav-link-pending")).to.equal(true);
    expect(link.getAttribute("aria-busy")).to.equal("true");

    dispatchHtmxAfterRequest(link, { elt: link });

    expect(link.classList.contains("header-nav-link-pending")).to.equal(false);
    expect(link.hasAttribute("aria-busy")).to.equal(false);
  });

  it("keeps loading when a different header nav request finishes", async () => {
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden"></div>
      <a id="explore-link" href="/explore" hx-boost="true" data-header-nav-link>
        Explore
      </a>
      <a id="stats-link" href="/stats" hx-boost="true" data-header-nav-link>
        Stats
      </a>
    `;

    initUserDropdown();

    const exploreLink = document.getElementById("explore-link");
    const statsLink = document.getElementById("stats-link");

    dispatchHtmxBeforeRequest(exploreLink, { elt: exploreLink });
    await new Promise((resolve) => setTimeout(resolve, 140));

    expect(exploreLink.classList.contains("header-nav-link-pending")).to.equal(true);

    dispatchHtmxBeforeRequest(statsLink, { elt: statsLink });
    await new Promise((resolve) => setTimeout(resolve, 140));

    expect(exploreLink.classList.contains("header-nav-link-pending")).to.equal(false);
    expect(statsLink.classList.contains("header-nav-link-pending")).to.equal(true);

    dispatchHtmxAfterRequest(exploreLink, { elt: exploreLink });
    dispatchHtmxAfterSwap(document, { elt: exploreLink, target: document.body });

    expect(statsLink.classList.contains("header-nav-link-pending")).to.equal(true);
    expect(statsLink.getAttribute("aria-busy")).to.equal("true");

    dispatchHtmxAfterRequest(statsLink, { elt: statsLink });

    expect(statsLink.classList.contains("header-nav-link-pending")).to.equal(false);
    expect(statsLink.hasAttribute("aria-busy")).to.equal(false);
  });

  it("keeps delayed loading queued after a matching swap event", async () => {
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden"></div>
      <a id="explore-link" href="/explore" hx-boost="true" data-header-nav-link>
        Explore
      </a>
    `;

    initUserDropdown();

    const link = document.getElementById("explore-link");
    dispatchHtmxBeforeRequest(link, { elt: link });
    dispatchHtmxAfterSwap(document, { elt: link, target: document.body });

    await new Promise((resolve) => setTimeout(resolve, 140));

    expect(link.classList.contains("header-nav-link-pending")).to.equal(true);
    expect(link.getAttribute("aria-busy")).to.equal("true");

    dispatchHtmxAfterRequest(link, { elt: link });

    expect(link.classList.contains("header-nav-link-pending")).to.equal(false);
    expect(link.hasAttribute("aria-busy")).to.equal(false);
  });

  it("shows loading on non-boosted header nav link clicks", async () => {
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden"></div>
      <a
        id="docs-link"
        href="/docs"
        hx-boost="false"
        data-header-nav-link
      >
        Docs
      </a>
    `;

    initUserDropdown();

    const link = document.getElementById("docs-link");
    document.addEventListener("click", (event) => event.preventDefault(), { once: true });
    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, button: 0 }));

    await new Promise((resolve) => setTimeout(resolve, 140));

    expect(link.classList.contains("header-nav-link-pending")).to.equal(true);
    expect(link.getAttribute("aria-busy")).to.equal("true");

    window.dispatchEvent(new Event("pageshow"));

    expect(link.classList.contains("header-nav-link-pending")).to.equal(false);
    expect(link.hasAttribute("aria-busy")).to.equal(false);
  });
});
