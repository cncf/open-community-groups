import { expect } from "@open-wc/testing";

import { positionActionsMenu } from "/static/js/common/actions-menu.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("actions menu", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("closes another open menu before opening the selected menu", () => {
    // Render two row action menus.
    document.body.innerHTML = `
      <details data-actions-menu open>
        <summary>First actions</summary>
        <button type="button">First action</button>
      </details>
      <details data-actions-menu>
        <summary>Second actions</summary>
        <button type="button">Second action</button>
      </details>
    `;

    // Open the second action menu.
    const menus = document.querySelectorAll("[data-actions-menu]");
    menus[1].querySelector("summary").click();

    // Only the selected menu remains open.
    expect(menus[0].open).to.equal(false);
    expect(menus[1].open).to.equal(true);
  });

  it("closes an open menu when an action is selected or the page is clicked", () => {
    // Render an action menu and an outside control.
    document.body.innerHTML = `
      <details data-actions-menu open>
        <summary>Actions</summary>
        <button type="button">Retry refund</button>
      </details>
      <button id="outside" type="button">Outside</button>
    `;

    // Select an action before any asynchronous response completes.
    const menu = document.querySelector("[data-actions-menu]");
    menu.querySelector("button").click();
    expect(menu.open).to.equal(false);

    // Reopen the menu and dismiss it from outside.
    menu.open = true;
    document.getElementById("outside").click();
    expect(menu.open).to.equal(false);
  });

  it("closes on escape and restores focus to the active menu summary", () => {
    // Render two open action menus to verify defensive cleanup.
    document.body.innerHTML = `
      <details data-actions-menu open>
        <summary>First actions</summary>
        <button type="button">First action</button>
      </details>
      <details data-actions-menu open>
        <summary>Second actions</summary>
        <button type="button">Second action</button>
      </details>
    `;

    // Dismiss the focused menu from the keyboard.
    const menus = document.querySelectorAll("[data-actions-menu]");
    const summary = menus[1].querySelector("summary");
    menus[1].querySelector("button").focus();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));

    // Every menu closes and the active menu trigger regains focus.
    expect(menus[0].open).to.equal(false);
    expect(menus[1].open).to.equal(false);
    expect(document.activeElement).to.equal(summary);
  });

  it("opens the dropdown above its trigger when the viewport would clip it", () => {
    // Render an open menu near the bottom of the viewport.
    document.body.innerHTML = `
      <details data-actions-menu open>
        <summary>Actions</summary>
        <div class="dropdown">Menu items</div>
      </details>
    `;
    const menu = document.querySelector("[data-actions-menu]");
    const dropdown = menu.querySelector(".dropdown");
    menu.getBoundingClientRect = () => ({ top: 500, bottom: 530 });
    dropdown.getBoundingClientRect = () => ({ bottom: window.innerHeight + 80 });

    // Position the menu after its open state is applied.
    positionActionsMenu(menu);

    // The dropdown is anchored above the trigger with the shared viewport gap.
    expect(dropdown.style.insetBlockStart).to.equal("auto");
    expect(dropdown.style.insetBlockEnd).to.equal("calc(100% + 8px)");
  });

  it("keeps the dropdown below its trigger when it fits in the viewport", () => {
    // Render an open menu with enough room below it.
    document.body.innerHTML = `
      <details data-actions-menu open>
        <summary>Actions</summary>
        <div class="dropdown">Menu items</div>
      </details>
    `;
    const menu = document.querySelector("[data-actions-menu]");
    const dropdown = menu.querySelector(".dropdown");
    menu.getBoundingClientRect = () => ({ top: 100, bottom: 130 });
    dropdown.getBoundingClientRect = () => ({ bottom: 260 });

    // Position the menu without a viewport collision.
    positionActionsMenu(menu);

    // Existing template positioning continues to place it below the trigger.
    expect(dropdown.style.insetBlockStart).to.equal("");
    expect(dropdown.style.insetBlockEnd).to.equal("");
  });

  it("opens above when a scrolling table wrapper would clip the dropdown", () => {
    // Render an open menu inside the horizontally scrolling table pattern.
    document.body.innerHTML = `
      <div id="table-wrapper" style="overflow: auto">
        <details data-actions-menu open>
          <summary>Actions</summary>
          <div class="dropdown">Menu items</div>
        </details>
      </div>
    `;
    const wrapper = document.getElementById("table-wrapper");
    const menu = document.querySelector("[data-actions-menu]");
    const dropdown = menu.querySelector(".dropdown");
    wrapper.getBoundingClientRect = () => ({ top: 20, bottom: 320 });
    menu.getBoundingClientRect = () => ({ top: 260, bottom: 290 });
    dropdown.getBoundingClientRect = () => ({ bottom: 410 });

    // Position the menu within the scrolling ancestor's visible bounds.
    positionActionsMenu(menu);

    // The dropdown opens upward before the ancestor can clip its contents.
    expect(dropdown.style.insetBlockStart).to.equal("auto");
    expect(dropdown.style.insetBlockEnd).to.equal("calc(100% + 8px)");
  });
});
