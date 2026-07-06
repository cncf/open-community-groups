import { expect } from "@open-wc/testing";

import { resolveUrl, setLinkContent } from "/static/js/common/url-utils.js";

describe("url-utils", () => {
  it("resolves relative and absolute urls from the current origin", () => {
    // Relative paths are expanded while absolute URLs are preserved.
    expect(resolveUrl("/groups")).to.equal(`${window.location.origin}/groups`);
    expect(resolveUrl("https://example.com/community")).to.equal("https://example.com/community");
  });

  it("returns an empty string for invalid urls", () => {
    // Invalid and empty URLs resolve to an empty string.
    expect(resolveUrl("http://[invalid")).to.equal("");
    expect(resolveUrl("")).to.equal("");
  });

  it("returns an empty string for unsafe url schemes", () => {
    // Unsafe schemes resolve to an empty string even when URL parsing succeeds.
    expect(resolveUrl("javascript:alert(1)")).to.equal("");
    expect(resolveUrl("data:text/html,hello")).to.equal("");
    expect(resolveUrl("mailto:hello@example.com")).to.equal("");
  });

  it("sets and clears link content based on the resolved url", () => {
    // Create the a fixture element.
    const link = document.createElement("a");

    // Set resolved link content on the anchor.
    setLinkContent(link, "/events");
    expect(link.textContent).to.equal(`${window.location.origin}/events`);
    expect(link.getAttribute("href")).to.equal(`${window.location.origin}/events`);

    // Clear anchor content when the URL cannot be resolved.
    setLinkContent(link, "http://[invalid");
    expect(link.textContent).to.equal("");
    expect(link.hasAttribute("href")).to.equal(false);
  });

  it("clears link content for unsafe url schemes", () => {
    // Create the anchor fixture.
    const link = document.createElement("a");

    // Clear anchor content when the URL uses an unsafe scheme.
    setLinkContent(link, "javascript:alert(1)");
    expect(link.textContent).to.equal("");
    expect(link.hasAttribute("href")).to.equal(false);
  });
});
