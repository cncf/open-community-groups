import { expect } from "@open-wc/testing";

import { resolveUrl, setLinkContent } from "/static/js/common/url-utils.js";

describe("url-utils", () => {
  it("resolves relative and absolute urls from the current origin", () => {
    expect(resolveUrl("/groups")).to.equal(`${window.location.origin}/groups`);
    expect(resolveUrl("https://example.com/community")).to.equal("https://example.com/community");
  });

  it("returns an empty string for invalid urls", () => {
    expect(resolveUrl("http://[invalid")).to.equal("");
    expect(resolveUrl("")).to.equal("");
  });

  it("sets and clears link content based on the resolved url", () => {
    const link = document.createElement("a");

    setLinkContent(link, "/events");
    expect(link.textContent).to.equal(`${window.location.origin}/events`);
    expect(link.getAttribute("href")).to.equal(`${window.location.origin}/events`);

    setLinkContent(link, "http://[invalid");
    expect(link.textContent).to.equal("");
    expect(link.hasAttribute("href")).to.equal(false);
  });
});
