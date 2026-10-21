import { expect } from "@open-wc/testing";

import { bindShowMoreFocus } from "/static/js/common/show-more.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

/**
 * Renders a list whose last item holds a show more button and binds it.
 * @returns {{button: HTMLButtonElement, list: HTMLUListElement, root: HTMLElement}}
 */
const renderList = () => {
  document.body.innerHTML = `
    <div id="root">
      <ul id="list">
        <li>First answer</li>
        <li><button id="show-more" type="button" data-show-more>Show more</button></li>
      </ul>
    </div>
  `;
  const root = document.getElementById("root");
  bindShowMoreFocus(root);

  return {
    button: document.getElementById("show-more"),
    list: document.getElementById("list"),
    root,
  };
};

/**
 * Replaces the button item with new items the way an HTMX outerHTML swap does.
 * @param {HTMLButtonElement} button Show more button.
 * @param {string} html Items returned by the server.
 */
const swapItems = (button, html) => {
  const item = button.closest("li");
  button.dispatchEvent(
    new CustomEvent("htmx:beforeSwap", {
      bubbles: true,
      detail: { elt: button, requestConfig: { elt: button }, shouldSwap: true, target: item },
    }),
  );
  const list = item.parentElement;
  item.outerHTML = html;
  list.lastElementChild.dispatchEvent(new CustomEvent("htmx:afterSettle", { bubbles: true }));
};

describe("show more focus", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("focuses the first appended item", () => {
    // Render the list and focus its show more button
    const { button, list } = renderList();
    button.focus();

    // Swap the button item with the next answers
    swapItems(button, "<li>Second answer</li><li>Third answer</li>");

    // Verify the first new answer takes the focus
    const second = list.children[1];
    expect(document.activeElement).to.equal(second);
    expect(second.getAttribute("tabindex")).to.equal("-1");
  });

  it("prefers the first control of the appended item", () => {
    // Render the list and focus its show more button
    const { button, list } = renderList();
    button.focus();

    // Swap the button item with an item holding a control
    swapItems(button, '<li><span>Survey</span><button type="button">Answer</button></li>');

    // Verify the control takes the focus and the item stays out of the tab order
    const item = list.children[1];
    expect(document.activeElement).to.equal(item.querySelector("button"));
    expect(item.hasAttribute("tabindex")).to.equal(false);
  });

  it("leaves the focus elsewhere untouched", () => {
    // Render the list next to a field the user moved to
    const { button, root } = renderList();
    root.insertAdjacentHTML("beforeend", '<input id="other" />');
    const other = document.getElementById("other");
    other.focus();

    // Swap the button item with the next answers
    swapItems(button, "<li>Second answer</li>");

    // Verify the focus stays on the field
    expect(document.activeElement).to.equal(other);
  });

  it("ignores swaps of other buttons", () => {
    // Render the list and replace the show more marker
    const { button, list } = renderList();
    button.removeAttribute("data-show-more");
    button.focus();

    // Swap the button item with the next answers
    swapItems(button, "<li>Second answer</li>");

    // Verify no item is made focusable
    expect(list.children[1].hasAttribute("tabindex")).to.equal(false);
  });
});
