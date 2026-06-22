import { expect } from "@open-wc/testing";

import { initUserDropdown } from "/static/js/common/header.js";
import {
  resetDom,
  setLocationPath,
  mockScrollTo,
} from "/tests/unit/test-utils/dom.js";
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
    window.localStorage.removeItem("ocg-theme");
    document.documentElement.classList.remove("ocg-dark");
    scrollToMock.restore();
    setLocationPath(originalPath);
  });

  it("toggles the dropdown and closes it on outside click", () => {
    // Build the DOM fixture with user dropdown button, user dropdown, and outside.
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden">
        <a>Profile</a>
      </div>
      <div id="outside">Outside</div>
    `;

    // Wire dropdown handlers before exercising trigger and outside clicks.
    initUserDropdown();

    // Track the trigger and menu state during the click flow.
    const button = document.getElementById("user-dropdown-button");
    const dropdown = document.getElementById("user-dropdown");

    // Open the dropdown from the trigger button.
    button.click();
    expect(dropdown.classList.contains("hidden")).to.equal(false);

    // Close the dropdown from an outside click.
    document
      .getElementById("outside")
      .dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(dropdown.classList.contains("hidden")).to.equal(true);
  });

  it("allows avatar clicks to close other open popovers", () => {
    // Build the DOM fixture with user dropdown button and user dropdown.
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden"></div>
    `;

    // Wire dropdown handlers before checking click propagation.
    initUserDropdown();

    // Track whether the avatar click reaches other document listeners.
    const button = document.getElementById("user-dropdown-button");
    let documentClickReceived = false;
    const handleDocumentClick = () => {
      documentClickReceived = true;
    };

    // Clicking the avatar still bubbles to the document.
    document.addEventListener("click", handleDocumentClick);
    button.click();
    document.removeEventListener("click", handleDocumentClick);

    // Other document-level popover handlers can receive the avatar click.
    expect(documentClickReceived).to.equal(true);
  });

  it("closes the dropdown on escape and focuses the button", () => {
    // Build the DOM fixture with user dropdown button and user dropdown.
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown">
        <a>Profile</a>
      </div>
    `;

    // Wire dropdown handlers before sending Escape.
    initUserDropdown();

    // Track the dropdown state and whether Escape restores focus.
    const button = document.getElementById("user-dropdown-button");
    const dropdown = document.getElementById("user-dropdown");
    let focused = false;

    // Stub focus so the test can observe it.
    button.focus = () => {
      focused = true;
    };

    // Escape closes the open dropdown and returns focus to the trigger.
    document.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Escape", bubbles: true }),
    );

    // The dropdown is hidden and the trigger receives focus.
    expect(dropdown.classList.contains("hidden")).to.equal(true);
    expect(focused).to.equal(true);
  });

  it("closes on regular link clicks but keeps the dropdown open for spinner links", () => {
    // Build the DOM fixture with user dropdown button, user dropdown, and profile link.
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown">
        <a id="profile-link">Profile</a>
        <a id="loading-link"><span class="hx-spinner"></span>Loading</a>
      </div>
    `;

    // Wire dropdown handlers before comparing link click behavior.
    initUserDropdown();

    // Clicking a regular dropdown link closes the menu.
    const dropdown = document.getElementById("user-dropdown");
    document
      .getElementById("profile-link")
      .dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(dropdown.classList.contains("hidden")).to.equal(true);

    // Spinner links keep the menu open while loading continues.
    dropdown.classList.remove("hidden");
    document
      .getElementById("loading-link")
      .dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(dropdown.classList.contains("hidden")).to.equal(false);
  });

  it("shows spinner loading on non-boosted dropdown links", () => {
    // Build the DOM fixture with user dropdown button, user dropdown, and external link.
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown">
        <a id="external-link" hx-boost="false">
          External
          <span class="hx-spinner"></span>
        </a>
      </div>
    `;

    // Wire dropdown handlers before clicking the non-boosted link.
    initUserDropdown();

    // Clicking a non-boosted dropdown link keeps the menu open and shows loading.
    const link = document.getElementById("external-link");
    const dropdown = document.getElementById("user-dropdown");
    link.dispatchEvent(new MouseEvent("click", { bubbles: true }));

    // The dropdown remains visible while the link is marked busy.
    expect(dropdown.classList.contains("hidden")).to.equal(false);
    expect(link.classList.contains("header-dropdown-link-pending")).to.equal(
      true,
    );
    expect(link.getAttribute("aria-busy")).to.equal("true");

    // Pageshow clears the dropdown link loading state.
    window.dispatchEvent(new Event("pageshow"));

    // The dropdown link is no longer marked busy.
    expect(link.classList.contains("header-dropdown-link-pending")).to.equal(
      false,
    );
    expect(link.hasAttribute("aria-busy")).to.equal(false);
  });

  it("toggles dark mode and persists the selected theme", () => {
    // Build the DOM fixture with desktop and dropdown theme toggles.
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden"></div>
      <button data-theme-toggle aria-label="Switch to dark mode">
        <span class="theme-toggle-icon">☾</span>
      </button>
      <button data-theme-toggle aria-label="Switch to dark mode">
        <span class="theme-toggle-icon">☾</span>
        <span class="theme-toggle-label">Dark mode</span>
      </button>
    `;

    // Wire header handlers before toggling the theme.
    initUserDropdown();

    // The first click enables dark mode on the whole document.
    document.querySelector("[data-theme-toggle]").click();
    expect(document.documentElement.classList.contains("ocg-dark")).to.equal(
      true,
    );
    expect(window.localStorage.getItem("ocg-theme")).to.equal("dark");
    expect(
      document.querySelector(".theme-toggle-label").textContent,
    ).to.equal("Light mode");

    // The second click returns to light mode and updates all controls.
    document.querySelector("[data-theme-toggle]").click();
    expect(document.documentElement.classList.contains("ocg-dark")).to.equal(
      false,
    );
    expect(window.localStorage.getItem("ocg-theme")).to.equal("light");
    expect(
      document.querySelector(".theme-toggle-label").textContent,
    ).to.equal("Dark mode");
  });

  it("scrolls to the top after dashboard swaps", () => {
    // Mark the current page as a dashboard path before the swap.
    setLocationPath("/dashboard/groups");
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden"></div>
      <div id="dashboard-content"></div>
    `;

    // Wire header swap handlers before dispatching the dashboard swap.
    initUserDropdown();

    // Swapping dashboard content scrolls the page back to the top.
    dispatchHtmxAfterSwap(document, {
      target: document.getElementById("dashboard-content"),
    });

    // Dashboard swaps trigger the expected scroll position.
    expect(scrollToMock.calls).to.deep.equal([{ top: 0, behavior: "auto" }]);
  });

  it("does not scroll after swaps outside dashboard pages", () => {
    // Mark the current page as a non-dashboard path before the swap.
    setLocationPath("/alliances/goup");
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden"></div>
      <div id="dashboard-content"></div>
    `;

    // Wire header swap handlers before dispatching the non-dashboard swap.
    initUserDropdown();

    // Swapping dashboard content outside dashboard pages does not scroll.
    dispatchHtmxAfterSwap(document, {
      target: document.getElementById("dashboard-content"),
    });

    // Non-dashboard swaps leave the scroll position untouched.
    expect(scrollToMock.calls).to.deep.equal([]);
  });

  it("shows loading on boosted header nav links after a short delay", async () => {
    // Build the DOM fixture with user dropdown button, user dropdown, and explore link.
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

    // Wire header nav loading handlers before starting the request.
    initUserDropdown();

    // Starting a boosted request does not show loading immediately.
    const link = document.getElementById("explore-link");
    dispatchHtmxBeforeRequest(link, { elt: link });

    // The link is still idle before the delay has elapsed.
    expect(link.classList.contains("header-nav-link-pending")).to.equal(false);

    // Waiting past the delay shows the nav loading state.
    await new Promise((resolve) => setTimeout(resolve, 140));

    // The link is marked busy after the delay.
    expect(link.classList.contains("header-nav-link-pending")).to.equal(true);
    expect(link.getAttribute("aria-busy")).to.equal("true");

    // Completing the request clears the nav loading state.
    dispatchHtmxAfterRequest(link, { elt: link });

    // The link is no longer marked busy after completion.
    expect(link.classList.contains("header-nav-link-pending")).to.equal(false);
    expect(link.hasAttribute("aria-busy")).to.equal(false);
  });

  it("skips header nav loading when a boosted request finishes quickly", async () => {
    // Build the DOM fixture with user dropdown button, user dropdown, and stats link.
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

    // Wire header nav loading handlers before the quick request finishes.
    initUserDropdown();

    // Start and finish the boosted request before the loading delay elapses.
    const link = document.getElementById("stats-link");
    dispatchHtmxBeforeRequest(link, { elt: link });
    dispatchHtmxAfterRequest(link, { elt: link });

    // Waiting past the delay does not show loading for completed requests.
    await new Promise((resolve) => setTimeout(resolve, 140));

    // Quickly completed boosted requests never mark the link busy.
    expect(link.classList.contains("header-nav-link-pending")).to.equal(false);
    expect(link.hasAttribute("aria-busy")).to.equal(false);
  });

  it("shows loading on boosted header nav link clicks", async () => {
    // Build the DOM fixture with user dropdown button, user dropdown, and explore link.
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

    // Wire header nav loading handlers before the boosted click.
    initUserDropdown();

    // Click the boosted nav link and prevent real navigation.
    const link = document.getElementById("explore-link");
    document.addEventListener("click", (event) => event.preventDefault(), {
      once: true,
    });
    link.dispatchEvent(
      new MouseEvent("click", { bubbles: true, cancelable: true, button: 0 }),
    );

    // Waiting past the delay shows loading for the clicked nav link.
    await new Promise((resolve) => setTimeout(resolve, 140));

    // The clicked link is marked busy after the delay.
    expect(link.classList.contains("header-nav-link-pending")).to.equal(true);
    expect(link.getAttribute("aria-busy")).to.equal("true");

    // Completing the request clears loading from the clicked link.
    dispatchHtmxAfterRequest(link, { elt: link });

    // The clicked link is no longer marked busy after completion.
    expect(link.classList.contains("header-nav-link-pending")).to.equal(false);
    expect(link.hasAttribute("aria-busy")).to.equal(false);
  });

  it("keeps loading when a different header nav request finishes", async () => {
    // Build the DOM fixture with user dropdown button, user dropdown, and explore link.
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

    // Wire header nav loading handlers before comparing active requests.
    initUserDropdown();

    // Track both nav links while requests compete for loading state.
    const exploreLink = document.getElementById("explore-link");
    const statsLink = document.getElementById("stats-link");

    // The first request marks the explore link busy after the delay.
    dispatchHtmxBeforeRequest(exploreLink, { elt: exploreLink });
    await new Promise((resolve) => setTimeout(resolve, 140));

    // The explore link shows loading for its active request.
    expect(exploreLink.classList.contains("header-nav-link-pending")).to.equal(
      true,
    );

    // A second request moves loading from explore to stats.
    dispatchHtmxBeforeRequest(statsLink, { elt: statsLink });
    await new Promise((resolve) => setTimeout(resolve, 140));

    // Only the latest nav request remains marked busy.
    expect(exploreLink.classList.contains("header-nav-link-pending")).to.equal(
      false,
    );
    expect(statsLink.classList.contains("header-nav-link-pending")).to.equal(
      true,
    );

    // Finishing the old request does not clear loading from the latest link.
    dispatchHtmxAfterRequest(exploreLink, { elt: exploreLink });
    dispatchHtmxAfterSwap(document, {
      elt: exploreLink,
      target: document.body,
    });

    // The stats link keeps its loading state while its request is active.
    expect(statsLink.classList.contains("header-nav-link-pending")).to.equal(
      true,
    );
    expect(statsLink.getAttribute("aria-busy")).to.equal("true");

    // Finishing the latest request clears its loading state.
    dispatchHtmxAfterRequest(statsLink, { elt: statsLink });

    // The stats link is no longer marked busy after completion.
    expect(statsLink.classList.contains("header-nav-link-pending")).to.equal(
      false,
    );
    expect(statsLink.hasAttribute("aria-busy")).to.equal(false);
  });

  it("keeps delayed loading queued after a matching swap event", async () => {
    // Build the DOM fixture with user dropdown button, user dropdown, and explore link.
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden"></div>
      <a id="explore-link" href="/explore" hx-boost="true" data-header-nav-link>
        Explore
      </a>
    `;

    // Wire header nav loading handlers before the swap-first flow.
    initUserDropdown();

    // Start a boosted request and receive the swap before completion.
    const link = document.getElementById("explore-link");
    dispatchHtmxBeforeRequest(link, { elt: link });
    dispatchHtmxAfterSwap(document, { elt: link, target: document.body });

    // Waiting past the delay still shows loading after the swap.
    await new Promise((resolve) => setTimeout(resolve, 140));

    // The swapped link remains marked busy while the request is active.
    expect(link.classList.contains("header-nav-link-pending")).to.equal(true);
    expect(link.getAttribute("aria-busy")).to.equal("true");

    // Completing the matching request clears the queued loading state.
    dispatchHtmxAfterRequest(link, { elt: link });

    // The swapped link is no longer marked busy after completion.
    expect(link.classList.contains("header-nav-link-pending")).to.equal(false);
    expect(link.hasAttribute("aria-busy")).to.equal(false);
  });

  it("shows loading on non-boosted header nav link clicks", async () => {
    // Build the DOM fixture with user dropdown button, user dropdown, and external link.
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden"></div>
      <a
        id="external-link"
        href="https://example.com"
        hx-boost="false"
        data-header-nav-link
      >
        External
      </a>
    `;

    // Wire header nav loading handlers before the non-boosted click.
    initUserDropdown();

    // Click the non-boosted nav link and prevent real navigation.
    const link = document.getElementById("external-link");
    document.addEventListener("click", (event) => event.preventDefault(), {
      once: true,
    });
    link.dispatchEvent(
      new MouseEvent("click", { bubbles: true, cancelable: true, button: 0 }),
    );

    // Waiting past the delay shows loading for the non-boosted link.
    await new Promise((resolve) => setTimeout(resolve, 140));

    // The non-boosted link is marked busy after the delay.
    expect(link.classList.contains("header-nav-link-pending")).to.equal(true);
    expect(link.getAttribute("aria-busy")).to.equal("true");

    // Pageshow clears loading after browser navigation returns.
    window.dispatchEvent(new Event("pageshow"));

    // The non-boosted link is no longer marked busy after pageshow.
    expect(link.classList.contains("header-nav-link-pending")).to.equal(false);
    expect(link.hasAttribute("aria-busy")).to.equal(false);
  });
});
