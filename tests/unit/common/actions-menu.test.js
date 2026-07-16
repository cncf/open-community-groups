import { expect } from "@open-wc/testing";

import "/static/js/common/actions-menu.js";
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
});
