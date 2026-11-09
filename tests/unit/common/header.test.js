import { expect } from "@open-wc/testing";

import { initUserDropdown } from "/static/js/common/header.js";
import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
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
import { stubMatchMedia } from "/tests/unit/test-utils/media.js";

/** Renders the phone shell around the user menu. */
const renderSheetFixture = () => {
  const menu = `
    <button id="user-dropdown-button" type="button" aria-expanded="false">User</button>
    <div id="user-dropdown" class="hidden account-sheet" style="position: fixed" role="menu">
      <ul class="sheet-panel sheet-body" role="none">
        <li class="sheet-head sheet-grab" role="none">
          <button id="sheet-close" type="button" role="menuitem" aria-label="Close menu">
            <div id="sheet-close-icon" class="icon-close"></div>
          </button>
        </li>
        <li role="none">
          <a id="stats-row" href="/stats" role="menuitem"><span class="hx-spinner"></span>Stats</a>
        </li>
        <li role="none">
          <a id="dashboard-row" href="/dashboard/user" role="menuitem">
            <span class="hx-spinner"></span>My dashboard
          </a>
        </li>
        <li role="none">
          <a id="check-in-row" href="/dashboard/user?tab=check-in" role="menuitem">
            <span class="hx-spinner"></span>Check in
          </a>
        </li>
        <li role="none">
          <a id="invitations-row" href="/dashboard/user?tab=invitations" role="menuitem">
            <span class="hx-spinner"></span>Invitations
          </a>
        </li>
        <li class="account-sheet-cta" role="none">
          <a id="log-in-row" href="#log-in" role="menuitem">Log in</a>
        </li>
        <li role="none">
          <a id="home-row" href="/" role="menuitem">Home</a>
        </li>
        <li style="display: none" role="none">
          <button id="mobile-version" type="button" role="menuitem">Mobile version</button>
        </li>
        <li class="hidden" role="none">
          <button id="desktop-version" type="button" role="menuitem">Desktop version</button>
        </li>
      </ul>
    </div>
  `;

  document.body.innerHTML = `
    <div>
      <div>
        <header id="header">
          <a id="logo-link" href="/" aria-label="Go to homepage">Logo</a>
          <a id="title-link" href="/" aria-label="Go to Test Site homepage">Test Site</a>
          ${menu}
        </header>
      </div>
      <section id="jumbotron"></section>
    </div>
    <main id="main-content"></main>
    <footer id="site-footer" role="contentinfo"></footer>
    <div id="outside">Outside</div>
  `;
  initUserDropdown();

  return {
    close: document.getElementById("sheet-close"),
    dropdown: document.getElementById("user-dropdown"),
    panel: document.querySelector("#user-dropdown .sheet-panel"),
    userButton: document.getElementById("user-dropdown-button"),
  };
};

/** Collects the sheet state that must not outlive the sheet. */
const getSheetMarkers = () => ({
  ariaCurrent: document.querySelectorAll("[aria-current]").length,
  ariaExpanded: document.querySelectorAll('[aria-expanded="true"]').length,
  drag: document.querySelectorAll("[data-sheet-drag]").length,
  inert: document.querySelectorAll("[inert]").length,
  lock: document.body.dataset.modalOpenCount ?? "0",
  overflow: document.body.style.overflow,
});

const CLEAR_SHEET_MARKERS = {
  ariaCurrent: 0,
  ariaExpanded: 0,
  drag: 0,
  inert: 0,
  lock: "0",
  overflow: "",
};

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
    // Build the DOM fixture with user dropdown button, user dropdown, and docs link.
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown">
        <a id="docs-link" hx-boost="false">
          Docs
          <span class="hx-spinner"></span>
        </a>
      </div>
    `;

    // Wire dropdown handlers before clicking the non-boosted link.
    initUserDropdown();

    // Clicking a non-boosted dropdown link keeps the menu open and shows loading.
    const link = document.getElementById("docs-link");
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
    setLocationPath("/communities/cncf");
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
    // Build the DOM fixture with user dropdown button, user dropdown, and docs link.
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

    // Wire header nav loading handlers before the non-boosted click.
    initUserDropdown();

    // Click the non-boosted nav link and prevent real navigation.
    const link = document.getElementById("docs-link");
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

  describe("account sheet", () => {
    const originalCloseWatcher = window.CloseWatcher;
    let media;
    const historyRestoreEvent = () => new Event("htmx:historyRestore", { bubbles: true });
    const restoredPageshowEvent = () => new PageTransitionEvent("pageshow", { persisted: true });

    afterEach(() => {
      // Release any sheet state left by the test case.
      window.dispatchEvent(restoredPageshowEvent());
      media?.restore();
      window.CloseWatcher = originalCloseWatcher;
    });

    it("keeps the anchored menu under a false query", () => {
      // Render the shell with the phone query off.
      media = stubMatchMedia();
      const { dropdown, userButton } = renderSheetFixture();
      const addedListeners = [];
      const originalAddEventListener = document.addEventListener;
      document.addEventListener = (type, ...rest) => {
        addedListeners.push(type);
        originalAddEventListener.call(document, type, ...rest);
      };

      // Open the menu from its trigger.
      userButton.click();
      document.addEventListener = originalAddEventListener;

      // Verify nothing sheet related was written or bound beyond the expanded state.
      expect(dropdown.classList.contains("hidden")).to.equal(false);
      expect(getSheetMarkers()).to.deep.equal({ ...CLEAR_SHEET_MARKERS, ariaExpanded: 1 });
      expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);
      expect(addedListeners).to.deep.equal([]);
      expect(document.activeElement).not.to.equal(document.getElementById("sheet-close"));
    });

    it("keeps the anchored menu open on a margin click", () => {
      // Open the anchored menu with the phone query off.
      media = stubMatchMedia();
      const { dropdown, userButton } = renderSheetFixture();
      userButton.click();

      // Click the menu's own margin.
      dropdown.dispatchEvent(new MouseEvent("click", { bubbles: true }));

      // Verify the menu stays open.
      expect(dropdown.classList.contains("hidden")).to.equal(false);
    });

    it("closes the anchored menu from Sign up without moving focus", () => {
      // Open the anchored menu with the phone query off.
      media = stubMatchMedia();
      const { dropdown, userButton } = renderSheetFixture();
      userButton.click();

      // Follow a link that shows no spinner.
      document.getElementById("log-in-row").click();

      // Verify the menu closes as it does today.
      expect(dropdown.classList.contains("hidden")).to.equal(true);
      expect(document.activeElement).not.to.equal(userButton);
    });

    it("opens with the sheet state in place", () => {
      // Render the shell on a dashboard tab.
      setLocationPath("/dashboard/user?tab=invitations");
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
      const { close, dropdown, panel, userButton } = renderSheetFixture();

      // Open the sheet.
      userButton.click();

      // Verify the sheet takes the page over and focus enters it.
      expect(dropdown.classList.contains("hidden")).to.equal(false);
      expect(document.body.dataset.modalOpenCount).to.equal("1");
      expect(document.body.style.overflow).to.equal("hidden");
      expect(document.activeElement).to.equal(close);
      expect(userButton.getAttribute("aria-expanded")).to.equal("true");
      expect(panel.hasAttribute("data-sheet-drag")).to.equal(true);

      // Verify everything behind the scrim is inert.
      ["jumbotron", "logo-link", "main-content", "site-footer", "title-link"].forEach((id) => {
        expect(document.getElementById(id).inert, id).to.equal(true);
      });

      // Verify the sheet's own link to the same page stays reachable.
      expect(document.getElementById("home-row").inert).to.equal(false);

      // Verify only the row of the current tab is marked.
      expect(document.getElementById("invitations-row").getAttribute("aria-current")).to.equal("page");
      expect(document.getElementById("check-in-row").hasAttribute("aria-current")).to.equal(false);
      expect(document.getElementById("dashboard-row").hasAttribute("aria-current")).to.equal(false);
      expect(document.getElementById("stats-row").hasAttribute("aria-current")).to.equal(false);
      expect(dropdown.hasAttribute("aria-hidden")).to.equal(false);
    });

    it("marks the row without a tab only on the page without one", () => {
      // Render the shell on the dashboard without a tab.
      setLocationPath("/dashboard/user");
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
      const { userButton } = renderSheetFixture();

      // Open the sheet.
      userButton.click();

      // Verify that row is marked and the tab rows are not.
      expect(document.getElementById("dashboard-row").getAttribute("aria-current")).to.equal("page");
      expect(document.getElementById("check-in-row").hasAttribute("aria-current")).to.equal(false);
      expect(document.getElementById("invitations-row").hasAttribute("aria-current")).to.equal(false);
    });

    it("marks a row by pathname when the page has a query", () => {
      // Render the shell on a page whose row has no query.
      setLocationPath("/stats?range=30");
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
      const { userButton } = renderSheetFixture();

      // Open the sheet.
      userButton.click();

      // Verify the row is marked.
      expect(document.getElementById("stats-row").getAttribute("aria-current")).to.equal("page");
    });

    [
      ["close button", () => document.getElementById("sheet-close").click()],
      ["close icon", () => document.getElementById("sheet-close-icon").click()],
      [
        "scrim",
        () =>
          document
            .getElementById("user-dropdown")
            .dispatchEvent(new MouseEvent("click", { bubbles: true })),
      ],
      ["outside click", () => document.getElementById("outside").click()],
      [
        "Escape",
        () => document.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" })),
      ],
      ["link without a spinner", () => document.getElementById("log-in-row").click()],
      ["trigger", () => document.getElementById("user-dropdown-button").click()],
    ].forEach(([name, closeSheet]) => {
      it(`closes from the ${name} and restores focus to the opener`, () => {
        // Open the sheet.
        media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
        const { dropdown, userButton } = renderSheetFixture();
        userButton.click();

        // Close it.
        closeSheet();

        // Verify the sheet released everything and focus went back.
        expect(dropdown.classList.contains("hidden")).to.equal(true);
        expect(getSheetMarkers()).to.deep.equal(CLEAR_SHEET_MARKERS);
        expect(document.activeElement).to.equal(userButton);
      });
    });

    it("keeps the sheet open while a spinner link loads", () => {
      // Open the sheet.
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
      const { dropdown, userButton } = renderSheetFixture();
      userButton.click();

      // Follow a link that shows a spinner.
      const link = document.getElementById("stats-row");
      document.addEventListener("click", (event) => event.preventDefault(), { once: true });
      link.click();

      // Verify the sheet stays up until the swap.
      expect(dropdown.classList.contains("hidden")).to.equal(false);
    });

    it("traps Tab over the rendered rows, including the hidden class row", () => {
      // Open the sheet.
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
      const { close, userButton } = renderSheetFixture();
      userButton.click();
      const desktopVersion = document.getElementById("desktop-version");
      const pressTab = (shiftKey = false) =>
        document.dispatchEvent(
          new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Tab", shiftKey }),
        );

      // Verify Shift+Tab wraps to the last rendered row.
      pressTab(true);
      expect(document.activeElement).to.equal(desktopVersion);

      // Verify Tab wraps back to the close button.
      pressTab();
      expect(document.activeElement).to.equal(close);
    });

    it("sends a close request through the close button", () => {
      // Stub a close watcher that records itself.
      let watcher = null;
      window.CloseWatcher = class extends EventTarget {
        constructor() {
          super();
          watcher = this;
        }

        destroy() {
          this.destroyed = true;
        }
      };
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
      const { dropdown, userButton } = renderSheetFixture();
      userButton.click();

      // Fire the close request.
      watcher.dispatchEvent(new Event("close"));

      // Verify it closed the sheet and released the watcher.
      expect(dropdown.classList.contains("hidden")).to.equal(true);
      expect(watcher.destroyed).to.equal(true);
      expect(document.activeElement).to.equal(userButton);
    });

    it("releases sheet state and keeps the menu open when the query turns false", () => {
      // Open the sheet.
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
      const { dropdown, userButton } = renderSheetFixture();
      userButton.click();

      // Rotate past md.
      media.setMatches(PHONE_MEDIA_QUERY, false);

      // Verify the sheet state is gone and the menu is still up.
      expect(dropdown.classList.contains("hidden")).to.equal(false);
      expect(getSheetMarkers()).to.deep.equal({ ...CLEAR_SHEET_MARKERS, ariaExpanded: 1 });
      expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);

      // Verify the anchored rules are back.
      dropdown.dispatchEvent(new MouseEvent("click", { bubbles: true }));
      expect(dropdown.classList.contains("hidden")).to.equal(false);
    });

    it("releasing the sheet past md keeps aria-expanded true while the anchored menu stays open", () => {
      // Open the sheet.
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
      const { userButton } = renderSheetFixture();
      userButton.click();

      // Rotate past md.
      media.setMatches(PHONE_MEDIA_QUERY, false);

      // Verify the trigger still reports the anchored menu as open.
      expect(userButton.getAttribute("aria-expanded")).to.equal("true");

      // Close the anchored menu from outside.
      document.getElementById("outside").click();

      // Verify the trigger reports it closed.
      expect(userButton.getAttribute("aria-expanded")).to.equal("false");
    });

    it("desktop toggle syncs aria-expanded on open and close", () => {
      // Render the shell with the phone query off.
      media = stubMatchMedia();
      const { userButton } = renderSheetFixture();
      expect(userButton.getAttribute("aria-expanded")).to.equal("false");

      // Open the anchored menu.
      userButton.click();
      expect(userButton.getAttribute("aria-expanded")).to.equal("true");

      // Close it from the trigger.
      userButton.click();
      expect(userButton.getAttribute("aria-expanded")).to.equal("false");
    });

    it("outside click, Escape and a menu link click set aria-expanded to false", () => {
      // Render the shell with the phone query off.
      media = stubMatchMedia();
      const { userButton } = renderSheetFixture();

      // Close the open menu from an outside click.
      userButton.click();
      expect(userButton.getAttribute("aria-expanded")).to.equal("true");
      document.getElementById("outside").click();
      expect(userButton.getAttribute("aria-expanded")).to.equal("false");

      // Close the open menu with Escape.
      userButton.click();
      expect(userButton.getAttribute("aria-expanded")).to.equal("true");
      document.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));
      expect(userButton.getAttribute("aria-expanded")).to.equal("false");

      // Close the open menu by following a link without a spinner.
      userButton.click();
      expect(userButton.getAttribute("aria-expanded")).to.equal("true");
      document.getElementById("log-in-row").click();
      expect(userButton.getAttribute("aria-expanded")).to.equal("false");
    });

    it('history restore resets a stale aria-expanded="true" on a hidden menu', () => {
      // Render a snapshot whose trigger claims a menu that is hidden.
      media = stubMatchMedia();
      const { dropdown, userButton } = renderSheetFixture();
      userButton.setAttribute("aria-expanded", "true");

      // Restore it.
      document.dispatchEvent(historyRestoreEvent());

      // Verify the trigger matches the hidden menu.
      expect(dropdown.classList.contains("hidden")).to.equal(true);
      expect(userButton.getAttribute("aria-expanded")).to.equal("false");
    });

    it("closes a menu that crossed into phone widths from its scrim", () => {
      // Open the anchored menu, then cross into phone widths.
      media = stubMatchMedia();
      const { dropdown, userButton } = renderSheetFixture();
      userButton.click();
      media.setMatches(PHONE_MEDIA_QUERY, true);

      // Tap the scrim that now covers the page.
      dropdown.dispatchEvent(new MouseEvent("click", { bubbles: true }));

      // Verify the menu closes rather than trapping the page.
      expect(dropdown.classList.contains("hidden")).to.equal(true);
    });

    it("releases the sheet when a swap replaces it", () => {
      // Open the sheet.
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
      const { userButton } = renderSheetFixture();
      userButton.click();

      // Swap the body the way a boosted link does.
      renderSheetFixture();
      dispatchHtmxAfterSwap(document, { target: document.body });

      // Verify nothing is held for the sheet that left.
      expect(getSheetMarkers()).to.deep.equal(CLEAR_SHEET_MARKERS);
      expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);
    });

    /**
     * Replaces the user menu the way the section refetch does. The new sheet still
     * shows at afterSwap, because HTMX keeps the old class on it until settling.
     * @returns {void}
     */
    const swapUserMenu = () => {
      document.getElementById("user-dropdown-button").remove();
      document.getElementById("user-dropdown").remove();
      document.getElementById("header").insertAdjacentHTML(
        "beforeend",
        `
          <button id="user-dropdown-button" type="button" aria-expanded="false">User</button>
          <div id="user-dropdown"></div>
        `,
      );
      dispatchHtmxAfterSwap(document, { target: document.getElementById("header") });
    };

    it("releases a sheet a refetch replaced before the new node settles", () => {
      // Open the sheet from the user button, which the refetch replaces.
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
      const { userButton } = renderSheetFixture();
      userButton.click();

      // Replace the menu.
      swapUserMenu();

      // Verify nothing is held and the replacement takes focus. The unsettled node
      // still shows, so its trigger reports it expanded until settling.
      const newButton = document.getElementById("user-dropdown-button");
      expect(userButton.isConnected).to.equal(false);
      expect(getSheetMarkers()).to.deep.equal({ ...CLEAR_SHEET_MARKERS, ariaExpanded: 1 });
      expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);
      expect(document.activeElement).to.equal(newButton);

      // Settle the new node the way HTMX does, restoring its rendered class.
      document.getElementById("user-dropdown").classList.add("hidden");
      document.dispatchEvent(new Event("htmx:afterSettle", { bubbles: true }));
      expect(getSheetMarkers()).to.deep.equal(CLEAR_SHEET_MARKERS);

      // Verify the next tap opens the sheet instead of closing one nobody sees.
      newButton.click();
      expect(document.getElementById("user-dropdown").classList.contains("hidden")).to.equal(false);
    });

    it("does not touch focus when a swap leaves the open sheet alone", () => {
      // Open the sheet.
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
      const { close, dropdown, userButton } = renderSheetFixture();
      userButton.click();

      // Swap something else.
      dispatchHtmxAfterSwap(document, { target: document.getElementById("main-content") });

      // Verify the sheet still holds the page.
      expect(dropdown.classList.contains("hidden")).to.equal(false);
      expect(document.activeElement).to.equal(close);
      expect(document.body.dataset.modalOpenCount).to.equal("1");
      expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(2);
    });

    it("strips sheet state before HTMX saves history", () => {
      // Open the sheet.
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
      const { dropdown, userButton } = renderSheetFixture();
      userButton.click();

      // Save the history snapshot.
      document.body.dispatchEvent(new Event("htmx:beforeHistorySave", { bubbles: true }));

      // Verify the snapshot carries no open state.
      expect(dropdown.classList.contains("hidden")).to.equal(true);
      expect(getSheetMarkers()).to.deep.equal(CLEAR_SHEET_MARKERS);
      expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);
    });

    [
      ["htmx:historyRestore", () => document.dispatchEvent(historyRestoreEvent())],
      ["a restored pageshow", () => window.dispatchEvent(restoredPageshowEvent())],
    ].forEach(([name, restore]) => {
      it(`resets a restored open sheet from the DOM on ${name}`, () => {
        // Render a snapshot that shows an open sheet no module state knows of.
        media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
        const { dropdown, userButton } = renderSheetFixture();
        dropdown.classList.remove("hidden");
        document.getElementById("main-content").inert = true;
        userButton.setAttribute("aria-expanded", "true");

        // Restore it.
        restore();

        // Verify the DOM is closed and clean.
        expect(dropdown.classList.contains("hidden")).to.equal(true);
        expect(getSheetMarkers()).to.deep.equal(CLEAR_SHEET_MARKERS);
      });

      it(`releases an open sheet on ${name}`, () => {
        // Open the sheet.
        media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
        const { dropdown, userButton } = renderSheetFixture();
        userButton.click();

        // Restore the page.
        restore();

        // Verify the sheet is gone and the lock released.
        expect(dropdown.classList.contains("hidden")).to.equal(true);
        expect(getSheetMarkers()).to.deep.equal(CLEAR_SHEET_MARKERS);
      });
    });

    it("leaves a sheet opened before the first pageshow alone", () => {
      // Open the sheet before the page finishes loading.
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });
      const { dropdown, userButton } = renderSheetFixture();
      userButton.click();

      // Fire the page's first pageshow.
      window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: false }));

      // Verify the sheet stays open.
      expect(dropdown.classList.contains("hidden")).to.equal(false);
    });

    it("leaves an open anchored menu alone on restore under a false query", () => {
      // Open the anchored menu with the phone query off.
      media = stubMatchMedia();
      const { dropdown, userButton } = renderSheetFixture();
      userButton.click();

      // Restore the page.
      window.dispatchEvent(restoredPageshowEvent());

      // Verify the menu is untouched.
      expect(dropdown.classList.contains("hidden")).to.equal(false);
    });
  });
});
