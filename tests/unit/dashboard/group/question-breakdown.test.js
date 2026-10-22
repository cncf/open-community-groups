import { expect } from "@open-wc/testing";

import {
  bindQuestionOptionsToggles,
  toggleQuestionOptions,
} from "/static/js/dashboard/group/question-breakdown.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

/** Renders a "Show N more" options list and its toggle inside a root. */
const renderBreakdown = ({ listId = "survey-question-0-options", withLabels = true } = {}) => {
  const root = document.createElement("section");
  const labels = withLabels
    ? 'data-label-collapsed="Show 2 more options" data-label-expanded="Show fewer options"'
    : "";
  root.innerHTML = `
    <ul id="${listId}">
      <li>AI</li>
      <li hidden data-question-option-hidden>Cloud</li>
      <li hidden data-question-option-hidden>Security</li>
    </ul>
    <button type="button" aria-controls="${listId}" aria-expanded="false" data-question-options-toggle ${labels}
      ><span data-question-options-label>Show 2 more options</span
      ><span class="svg-icon" aria-hidden="true"></span
    ></button>
  `;
  document.body.append(root);

  return {
    hiddenOptions: [...root.querySelectorAll("[data-question-option-hidden]")],
    root,
    toggle: root.querySelector("[data-question-options-toggle]"),
  };
};

describe("question breakdown", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("expands and collapses the hidden options of a list", () => {
    // Render a list with two hidden options.
    const { hiddenOptions, toggle } = renderBreakdown();

    // Expand the list.
    toggleQuestionOptions(toggle);
    expect(hiddenOptions.every((option) => !option.hidden)).to.equal(true);
    expect(toggle.getAttribute("aria-expanded")).to.equal("true");
    expect(toggle.textContent).to.equal("Show fewer options");
    expect(toggle.querySelector(".svg-icon")).to.not.equal(null);

    // Collapse it again.
    toggleQuestionOptions(toggle);
    expect(hiddenOptions.every((option) => option.hidden)).to.equal(true);
    expect(toggle.getAttribute("aria-expanded")).to.equal("false");
    expect(toggle.textContent).to.equal("Show 2 more options");
  });

  it("keeps the current label when the toggle has no label attributes", () => {
    // Render a list whose toggle carries no label attributes.
    const { hiddenOptions, toggle } = renderBreakdown({ withLabels: false });

    // Expand the list.
    toggleQuestionOptions(toggle);

    // Verify the options are shown and the label is kept.
    expect(hiddenOptions.every((option) => !option.hidden)).to.equal(true);
    expect(toggle.getAttribute("aria-expanded")).to.equal("true");
    expect(toggle.textContent).to.equal("Show 2 more options");
  });

  it("ignores toggles whose list is missing", () => {
    // Render a toggle that controls a missing list.
    const { toggle } = renderBreakdown();
    toggle.setAttribute("aria-controls", "missing-list");

    // Toggle the missing list.
    toggleQuestionOptions(toggle);

    // Verify the toggle state is unchanged.
    expect(toggle.getAttribute("aria-expanded")).to.equal("false");
    expect(toggle.textContent).to.equal("Show 2 more options");
  });

  it("binds delegated toggles once per root", () => {
    // Render a list and bind its root twice.
    const { hiddenOptions, root, toggle } = renderBreakdown();
    bindQuestionOptionsToggles(root);
    bindQuestionOptionsToggles(root);

    // Click the toggle once.
    toggle.click();

    // Verify a single listener expanded the list.
    expect(hiddenOptions.every((option) => !option.hidden)).to.equal(true);
    expect(toggle.getAttribute("aria-expanded")).to.equal("true");

    // Click the toggle label to collapse the list.
    toggle.querySelector("[data-question-options-label]").click();
    expect(hiddenOptions.every((option) => option.hidden)).to.equal(true);
    expect(toggle.getAttribute("aria-expanded")).to.equal("false");
  });

  it("ignores missing roots", () => {
    // Verify binding without a root does not throw.
    expect(() => bindQuestionOptionsToggles(null)).to.not.throw();
  });

  it("keeps the toggles of separate roots independent", () => {
    // Render two lists and bind only the first root.
    const first = renderBreakdown({ listId: "analytics-question-0-options" });
    const second = renderBreakdown({ listId: "survey-question-0-options" });
    bindQuestionOptionsToggles(first.root);

    // Click the toggle of the unbound root.
    second.toggle.click();

    // Verify only bound roots react to clicks.
    expect(second.hiddenOptions.every((option) => option.hidden)).to.equal(true);
    expect(second.toggle.getAttribute("aria-expanded")).to.equal("false");

    // Click the toggle of the bound root.
    first.toggle.click();
    expect(first.hiddenOptions.every((option) => !option.hidden)).to.equal(true);
    expect(second.hiddenOptions.every((option) => option.hidden)).to.equal(true);
  });
});
