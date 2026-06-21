import { expect } from "@open-wc/testing";

import "/static/js/common/users/people-list.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent } from "/tests/unit/test-utils/lit.js";

describe("people-list", () => {
  afterEach(() => {
    resetDom();
  });

  it("renders nothing when there are no people", async () => {
    // Mount the list without people.
    const element = await mountLitComponent("people-list");

    // The empty list renders no light DOM content.
    expect(element.children.length).to.equal(0);
  });

  it("renders the initial subset with the show more control", async () => {
    // Mount a list with more people than the initial count.
    const element = await mountLitComponent("people-list", {
      people: [
        { name: "Ada Lovelace", title: "Mathematician" },
        { name: "Grace Hopper", company: "US Navy" },
        { name: "Margaret Hamilton", title: "Engineer" },
      ],
      initialCount: 2,
    });

    // Collect the headings and toggle elements.
    const headings = Array.from(element.querySelectorAll("h3")).map((node) =>
      node.textContent.trim(),
    );
    const toggle = element.querySelector("button");

    // The rendered text shows the scenario data.
    expect(headings).to.deep.equal(["Ada Lovelace", "Grace Hopper"]);
    expect(toggle?.textContent).to.include("Show 1 more");
    expect(element.textContent).to.include("US Navy");
  });

  it("toggles between collapsed and expanded lists", async () => {
    // Render the people-list fixture.
    const element = await mountLitComponent("people-list", {
      people: [
        { name: "Ada Lovelace" },
        { name: "Grace Hopper" },
        { name: "Margaret Hamilton" },
      ],
      initialCount: 1,
    });

    // Expand the list from the show-more control.
    element.querySelector("button")?.click();
    await element.updateComplete;

    // Expanded state shows all people and offers to collapse.
    let headings = Array.from(element.querySelectorAll("h3")).map((node) =>
      node.textContent.trim(),
    );
    expect(headings).to.deep.equal([
      "Ada Lovelace",
      "Grace Hopper",
      "Margaret Hamilton",
    ]);
    expect(element.querySelector("button")?.textContent).to.include(
      "Show less",
    );

    // Collapse the list from the show-less control.
    element.querySelector("button")?.click();
    await element.updateComplete;

    // Collapsed state returns to the initial subset.
    headings = Array.from(element.querySelectorAll("h3")).map((node) =>
      node.textContent.trim(),
    );
    expect(headings).to.deep.equal(["Ada Lovelace"]);
  });

  it("passes initials into logo-image placeholders", async () => {
    // Render the people-list fixture.
    const element = await mountLitComponent("people-list", {
      people: [{ name: "Open Alliance" }],
    });

    // Passed initials into logo-image placeholders.
    expect(
      element.querySelector("logo-image")?.getAttribute("placeholder"),
    ).to.equal("OC");
  });

  it("cleans non-letter characters when asked directly", () => {
    // Create the people-list fixture element.
    const element = document.createElement("people-list");

    // The helper removes non-letter characters and preserves letters.
    expect(element._cleanString("Ada 123!")).to.equal("Ada");
    expect(element._cleanString("Mária 😀 Dev")).to.equal("MáriaDev");
    expect(element._cleanString("")).to.equal("");
  });
});
