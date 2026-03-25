import { expect } from "@open-wc/testing";

import { initUserDropdown } from "/static/js/common/header.js";

describe("header", () => {
  const originalScrollTo = window.scrollTo;
  const originalPath = window.location.pathname;

  let scrollCalls;

  beforeEach(() => {
    document.body.innerHTML = "";
    scrollCalls = [];
    window.scrollTo = (options) => {
      scrollCalls.push(options);
    };
  });

  afterEach(() => {
    document.body.innerHTML = "";
    window.scrollTo = originalScrollTo;
    history.replaceState({}, "", originalPath);
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
    history.replaceState({}, "", "/dashboard/groups");
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden"></div>
      <div id="dashboard-content"></div>
    `;

    initUserDropdown();

    document.dispatchEvent(
      new CustomEvent("htmx:afterSwap", {
        detail: { target: document.getElementById("dashboard-content") },
      }),
    );

    expect(scrollCalls).to.deep.equal([{ top: 0, behavior: "auto" }]);
  });

  it("does not scroll after swaps outside dashboard pages", () => {
    history.replaceState({}, "", "/communities/cncf");
    document.body.innerHTML = `
      <button id="user-dropdown-button" type="button">User</button>
      <div id="user-dropdown" class="hidden"></div>
      <div id="dashboard-content"></div>
    `;

    initUserDropdown();

    document.dispatchEvent(
      new CustomEvent("htmx:afterSwap", {
        detail: { target: document.getElementById("dashboard-content") },
      }),
    );

    expect(scrollCalls).to.deep.equal([]);
  });
});
