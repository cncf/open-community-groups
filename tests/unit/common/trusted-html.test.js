import { expect } from "@open-wc/testing";

import {
  insertTrustedHtml,
  readTrustedHtml,
  setTrustedHtml,
} from "/static/js/common/trusted-html.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("common trusted html", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("reads and writes trusted html fragments", () => {
    // Build the element that owns a server-rendered HTML fragment.
    const element = document.createElement("section");

    // The helpers preserve markup for fragments that are already trusted.
    setTrustedHtml(element, "<strong>Accepted</strong>");
    expect(readTrustedHtml(element)).to.equal("<strong>Accepted</strong>");
    insertTrustedHtml(element, "beforeend", "<em> speaker</em>");
    expect(readTrustedHtml(element)).to.equal("<strong>Accepted</strong><em> speaker</em>");
  });

  it("normalizes missing trusted html values", () => {
    // Build the element that receives optional trusted markup.
    const element = document.createElement("section");

    // Missing values clear the target, and missing elements are ignored.
    setTrustedHtml(element, null);
    expect(readTrustedHtml(element)).to.equal("");
    expect(readTrustedHtml(null)).to.equal("");
    expect(() => setTrustedHtml(null, "<span>Ignored</span>")).not.to.throw();
    expect(() => insertTrustedHtml(null, "beforeend", "<span>Ignored</span>")).not.to.throw();
  });
});
