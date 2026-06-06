import { expect } from "@open-wc/testing";

import {
  enhanceMobileCardTables,
  parseDocsRoute,
  parseSamePageAnchor,
  resolveAppPath,
  rewriteAppLinks,
  syncCurrentSidebarSectionState,
} from "/static/js/site/docs-shell-enhancements.js";
import { resetDom, setLocationPath } from "/tests/unit/test-utils/dom.js";

describe("site docs shell enhancements", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    delete window.htmx;
    resetDom();
  });

  it("resolves docs app links to top-level paths", () => {
    // Hash and absolute app links map to the same top-level routes.
    expect(resolveAppPath("#/dashboard/groups", true)).to.equal("/dashboard/groups");
    expect(resolveAppPath("/explore/events", false)).to.equal("/explore/events");
    expect(resolveAppPath("#/", true)).to.equal("/");
    expect(resolveAppPath("#/docs", true)).to.equal(null);
  });

  it("rewrites docs app links for htmx navigation", () => {
    // Build markdown links that include app and docs routes.
    document.body.innerHTML = `
      <div class="ocg-docs-root">
        <div class="markdown-section">
          <a id="app-link" href="#/dashboard/groups" target="_blank">Dashboard</a>
          <a id="docs-link" href="#/guide">Guide</a>
        </div>
      </div>
    `;
    const processCalls = [];
    window.htmx = {
      process(target) {
        processCalls.push(target);
      },
    };

    // Rewrite only app links inside the docs content.
    rewriteAppLinks(document.querySelector(".ocg-docs-root"));

    // App links are boosted and docs routes are left untouched.
    const appLink = document.getElementById("app-link");
    expect(appLink?.getAttribute("href")).to.equal("/dashboard/groups");
    expect(appLink?.getAttribute("hx-boost")).to.equal("true");
    expect(appLink?.getAttribute("hx-target")).to.equal("body");
    expect(appLink?.getAttribute("target")).to.equal(null);
    expect(document.getElementById("docs-link")?.getAttribute("href")).to.equal("#/guide");
    expect(processCalls).to.have.length(1);
  });

  it("adds mobile card labels to markdown tables", () => {
    // Build a markdown table with header labels.
    document.body.innerHTML = `
      <div class="ocg-docs-root">
        <div class="markdown-section">
          <table>
            <thead>
              <tr>
                <th>City</th>
                <th>Country</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Malaga</td>
                <td>Spain</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    `;

    // Enhance table cells for mobile card rendering.
    enhanceMobileCardTables(document.querySelector(".ocg-docs-root"));

    // Cells receive their matching header labels.
    const cells = document.querySelectorAll("tbody td");
    expect(cells[0]?.getAttribute("data-label")).to.equal("City");
    expect(cells[1]?.getAttribute("data-label")).to.equal("Country");
    expect(document.querySelector("table")?.classList.contains("ocg-mobile-card-table")).to.equal(
      true,
    );
  });

  it("parses docs routes and same-page anchors", () => {
    // Configure current route for plain hash anchors.
    setLocationPath("/docs");
    window.location.hash = "#/guide";

    // Docsify routes normalize paths and expose section IDs.
    expect(parseDocsRoute("#/guide.md?id=section-a")).to.deep.equal({
      id: "section-a",
      path: "guide",
      rawPath: "/guide.md",
    });
    expect(parseDocsRoute("#/")).to.deep.equal({
      id: null,
      path: "",
      rawPath: "/",
    });
    expect(parseSamePageAnchor("#section-a")).to.deep.equal({
      id: "section-a",
      path: "guide",
      rawPath: "/guide",
    });
  });

  it("syncs the active sidebar section from the current route", () => {
    // Build the sidebar fixture for a route with an active section.
    window.location.hash = "#/guide?id=section-a";
    document.body.innerHTML = `
      <div class="ocg-docs-root">
        <div class="sidebar-nav">
          <ul>
            <li id="guide-item" class="collapse">
              <a href="#/guide">Guide</a>
              <ul class="app-sub-sidebar">
                <li id="section-item">
                  <a href="#/guide?id=section-a">Section A</a>
                </li>
              </ul>
            </li>
          </ul>
        </div>
      </div>
    `;

    // Sync the sidebar state after route changes.
    syncCurrentSidebarSectionState(document.querySelector(".ocg-docs-root"));

    // The current page opens and the active section is marked.
    expect(document.getElementById("guide-item")?.classList.contains("collapse")).to.equal(false);
    expect(document.getElementById("section-item")?.classList.contains("active")).to.equal(true);
  });
});
