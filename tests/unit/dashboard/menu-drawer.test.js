import { expect } from "@open-wc/testing";

import {
  closeDashboardMenuDrawer,
  openDashboardMenuDrawer,
} from "/static/js/dashboard/menu-drawer.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("dashboard menu drawer", () => {
  let originalMatchMedia;

  beforeEach(() => {
    resetDom();
    originalMatchMedia = window.matchMedia;
    // Release any drawer state leaked by a previous test case.
    window.dispatchEvent(new Event("pageshow"));
  });

  afterEach(() => {
    window.matchMedia = originalMatchMedia;
    resetDom();
  });

  const renderFixture = () => {
    document.body.innerHTML = `
      <aside id="dashboard-menu-drawer" class="-translate-x-full" tabindex="-1">
        <button id="close-dashboard-menu" type="button">Close menu</button>
        <a id="drawer-logout-link" href="/log-out">Log out</a>
      </aside>
      <div id="dashboard-menu-backdrop" class="hidden"></div>
      <button id="open-dashboard-menu" type="button" aria-expanded="false">Open dashboard menu</button>
    `;
  };

  // Forces the drawer helpers to treat the viewport as mobile or desktop.
  const stubViewport = ({ isDesktop }) => {
    window.matchMedia = () => ({ matches: isDesktop });
  };

  it("opens from the menu button and moves focus into the drawer", () => {
    // Render the drawer fixture and open it through the menu button.
    renderFixture();
    document.getElementById("open-dashboard-menu").click();

    // Verify the drawer slides in, the backdrop shows, and focus enters the drawer.
    const drawer = document.getElementById("dashboard-menu-drawer");
    expect(drawer.classList.contains("-translate-x-full")).to.equal(false);
    expect(document.getElementById("dashboard-menu-backdrop").classList.contains("hidden")).to.equal(false);
    expect(document.getElementById("open-dashboard-menu").getAttribute("aria-expanded")).to.equal("true");
    expect(document.activeElement).to.equal(drawer);
  });

  it("closes from the close button and restores focus to the open button", () => {
    // Render the drawer fixture and open it before closing from the close button.
    renderFixture();
    openDashboardMenuDrawer();
    document.getElementById("close-dashboard-menu").click();

    // Verify the drawer slides out, the backdrop hides, and focus returns to the trigger.
    expect(document.getElementById("dashboard-menu-drawer").classList.contains("-translate-x-full")).to.equal(
      true,
    );
    expect(document.getElementById("dashboard-menu-backdrop").classList.contains("hidden")).to.equal(true);
    expect(document.getElementById("open-dashboard-menu").getAttribute("aria-expanded")).to.equal("false");
    expect(document.activeElement).to.equal(document.getElementById("open-dashboard-menu"));
  });

  it("closes when the backdrop is clicked", () => {
    // Render the drawer fixture and open it before clicking the backdrop.
    renderFixture();
    openDashboardMenuDrawer();
    document.getElementById("dashboard-menu-backdrop").click();

    // Verify the drawer and the backdrop are hidden again.
    expect(document.getElementById("dashboard-menu-drawer").classList.contains("-translate-x-full")).to.equal(
      true,
    );
    expect(document.getElementById("dashboard-menu-backdrop").classList.contains("hidden")).to.equal(true);
  });

  it("closes on Escape only while the drawer is open", () => {
    // Render the drawer fixture and press Escape while the drawer is closed.
    renderFixture();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));

    // Verify the closed drawer ignores Escape and keeps focus untouched.
    expect(document.getElementById("open-dashboard-menu").getAttribute("aria-expanded")).to.equal("false");
    expect(document.activeElement).to.not.equal(document.getElementById("open-dashboard-menu"));

    // Open the drawer and press Escape again.
    openDashboardMenuDrawer();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));

    // Verify the drawer closes and focus returns to the open button.
    expect(document.getElementById("dashboard-menu-drawer").classList.contains("-translate-x-full")).to.equal(
      true,
    );
    expect(document.activeElement).to.equal(document.getElementById("open-dashboard-menu"));
  });

  it("ignores Escape presses consumed by other widgets", () => {
    // Render the drawer fixture and open it before dispatching a consumed Escape.
    renderFixture();
    openDashboardMenuDrawer();
    const consumedEscape = new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true });
    consumedEscape.preventDefault();
    document.dispatchEvent(consumedEscape);

    // Verify the drawer stays open when another widget already handled Escape.
    expect(document.getElementById("dashboard-menu-drawer").classList.contains("-translate-x-full")).to.equal(
      false,
    );
  });

  it("ignores drawer helpers when the drawer markup is missing", () => {
    // Call both helpers on a page without the drawer markup.
    openDashboardMenuDrawer();
    closeDashboardMenuDrawer();

    // Verify no drawer state leaks into the empty document.
    expect(document.getElementById("dashboard-menu-drawer")).to.equal(null);
  });

  it("locks body scroll while open and unlocks it on close", () => {
    // Render the drawer fixture and open it.
    renderFixture();
    openDashboardMenuDrawer();

    // Verify the shared body scroll lock is held while the drawer is open.
    expect(document.body.style.overflow).to.equal("hidden");

    // Close the drawer and verify the scroll lock is released.
    closeDashboardMenuDrawer();
    expect(document.body.style.overflow).to.equal("");
  });

  it("hides the closed drawer from keyboard and assistive users on mobile", () => {
    // Render the drawer fixture on a mobile viewport and synchronize its state.
    renderFixture();
    stubViewport({ isDesktop: false });
    window.dispatchEvent(new Event("pageshow"));

    // Verify the closed off-canvas drawer is inert and hidden from assistive users.
    const drawer = document.getElementById("dashboard-menu-drawer");
    expect(drawer.inert).to.equal(true);
    expect(drawer.getAttribute("aria-hidden")).to.equal("true");

    // Open the drawer and verify it becomes reachable again.
    openDashboardMenuDrawer();
    expect(drawer.inert).to.equal(false);
    expect(drawer.hasAttribute("aria-hidden")).to.equal(false);

    // Close the drawer and verify it is hidden once more.
    closeDashboardMenuDrawer();
    expect(drawer.inert).to.equal(true);
    expect(drawer.getAttribute("aria-hidden")).to.equal("true");
  });

  it("keeps Tab focus inside the open drawer on mobile", () => {
    // Render the drawer fixture on a mobile viewport and open the drawer.
    renderFixture();
    stubViewport({ isDesktop: false });
    openDashboardMenuDrawer();

    // Tab past the last focusable control and verify focus wraps to the first one.
    document.getElementById("drawer-logout-link").focus();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Tab", bubbles: true, cancelable: true }));
    expect(document.activeElement).to.equal(document.getElementById("close-dashboard-menu"));

    // Shift+Tab before the first control and verify focus wraps to the last one.
    document.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Tab", shiftKey: true, bubbles: true, cancelable: true }),
    );
    expect(document.activeElement).to.equal(document.getElementById("drawer-logout-link"));
  });

  it("does not trap Tab focus when the static desktop menu is displayed", () => {
    // Render the drawer fixture on a desktop viewport with the menu markup open.
    renderFixture();
    stubViewport({ isDesktop: true });
    openDashboardMenuDrawer();

    // Verify Tab presses are left for the browser to handle.
    document.getElementById("drawer-logout-link").focus();
    const tabEvent = new KeyboardEvent("keydown", { key: "Tab", bubbles: true, cancelable: true });
    document.dispatchEvent(tabEvent);
    expect(tabEvent.defaultPrevented).to.equal(false);
    expect(document.activeElement).to.equal(document.getElementById("drawer-logout-link"));
  });

  it("closes the drawer before HTMX saves a history snapshot", () => {
    // Render the drawer fixture and open it before HTMX saves the page snapshot.
    renderFixture();
    openDashboardMenuDrawer();
    document.dispatchEvent(new Event("htmx:beforeHistorySave"));

    // Verify the snapshot captures a closed drawer with its scroll lock released.
    expect(document.getElementById("dashboard-menu-drawer").classList.contains("-translate-x-full")).to.equal(
      true,
    );
    expect(document.getElementById("dashboard-menu-backdrop").classList.contains("hidden")).to.equal(true);
    expect(document.getElementById("open-dashboard-menu").getAttribute("aria-expanded")).to.equal("false");
    expect(document.body.style.overflow).to.equal("");
  });

  it("releases the scroll lock when a swap replaces the open drawer", () => {
    // Render the drawer fixture and open it before an HTMX swap replaces the markup.
    renderFixture();
    openDashboardMenuDrawer();
    renderFixture();
    document.dispatchEvent(new Event("htmx:afterSwap"));

    // Verify the swapped-in closed drawer no longer holds the body scroll lock.
    expect(document.body.style.overflow).to.equal("");
  });

  it("resets an open drawer when the page is restored from history", () => {
    // Render the drawer fixture and open it before a history restoration.
    renderFixture();
    openDashboardMenuDrawer();
    document.dispatchEvent(new Event("htmx:historyRestore"));

    // Verify the restored page shows a closed drawer without a scroll lock.
    expect(document.getElementById("dashboard-menu-drawer").classList.contains("-translate-x-full")).to.equal(
      true,
    );
    expect(document.getElementById("dashboard-menu-backdrop").classList.contains("hidden")).to.equal(true);
    expect(document.body.style.overflow).to.equal("");
  });
});
