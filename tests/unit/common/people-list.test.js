import { expect } from "@open-wc/testing";

import "/static/js/common/people-list.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent } from "/tests/unit/test-utils/lit.js";

describe("people-list", () => {
  afterEach(() => {
    resetDom();
  });

  it("renders nothing when there are no people", async () => {
    const element = await mountLitComponent("people-list");

    expect(element.children.length).to.equal(0);
  });

  it("renders the initial subset with the show more control", async () => {
    const element = await mountLitComponent("people-list", {
      people: [
        { name: "Ada Lovelace", title: "Mathematician" },
        { name: "Grace Hopper", company: "US Navy" },
        { name: "Margaret Hamilton", title: "Engineer" },
      ],
      initialCount: 2,
    });

    const headings = Array.from(element.querySelectorAll("h3")).map((node) => node.textContent.trim());
    const toggle = element.querySelector("button");

    expect(headings).to.deep.equal(["Ada Lovelace", "Grace Hopper"]);
    expect(toggle?.textContent).to.include("Show 1 more");
    expect(element.textContent).to.include("US Navy");
  });

  it("toggles between collapsed and expanded lists", async () => {
    const element = await mountLitComponent("people-list", {
      people: [
        { name: "Ada Lovelace" },
        { name: "Grace Hopper" },
        { name: "Margaret Hamilton" },
      ],
      initialCount: 1,
    });

    element.querySelector("button")?.click();
    await element.updateComplete;

    let headings = Array.from(element.querySelectorAll("h3")).map((node) => node.textContent.trim());
    expect(headings).to.deep.equal(["Ada Lovelace", "Grace Hopper", "Margaret Hamilton"]);
    expect(element.querySelector("button")?.textContent).to.include("Show less");

    element.querySelector("button")?.click();
    await element.updateComplete;

    headings = Array.from(element.querySelectorAll("h3")).map((node) => node.textContent.trim());
    expect(headings).to.deep.equal(["Ada Lovelace"]);
  });

  it("passes initials into logo-image placeholders", async () => {
    const element = await mountLitComponent("people-list", {
      people: [{ name: "Open Community" }],
    });

    expect(element.querySelector("logo-image")?.getAttribute("placeholder")).to.equal("OC");
  });

  it("cleans non-letter characters when asked directly", () => {
    const element = document.createElement("people-list");

    expect(element._cleanString("Ada 123!")).to.equal("Ada");
    expect(element._cleanString("Mária 😀 Dev")).to.equal("MáriaDev");
    expect(element._cleanString("")).to.equal("");
  });
});
