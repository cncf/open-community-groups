import { expect } from "@open-wc/testing";

const ANALYTICS_TABS = ["groups", "members", "events", "attendees", "page-views"];

/**
 * Loads the community analytics template source.
 * @returns {Promise<string>} Template source.
 */
const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/community/analytics.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

/**
 * Collapses whitespace runs so template assertions ignore indentation.
 * @param {string} value - Template source.
 * @returns {string} Source with single spaces between tokens.
 */
const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard community analytics template", () => {
  it("exposes the analytics tab list with presentational list items", async () => {
    // Load the analytics template and isolate the tab list.
    const template = normalizeWhitespace(await loadTemplate());
    const tabListStart = template.indexOf('aria-label="Analytics tabs"');
    const tabList = template.slice(tabListStart, template.indexOf("</ul>", tabListStart));

    // Verify the list keeps its tab list role and every item is presentational.
    expect(tabListStart).to.be.greaterThan(-1);
    expect(template).to.include('role="tablist" aria-label="Analytics tabs"');
    expect(tabList.match(/<li role="presentation"/g)).to.have.length(5);
    expect(tabList.match(/<li[ >]/g)).to.have.length(5);

    // Verify every section has one tab in the list and one summary card.
    for (const tab of ANALYTICS_TABS) {
      expect(tabList).to.include(`aria-controls="analytics-panel-${tab}" data-analytics-tab="${tab}"`);
      expect(template.split(`data-analytics-tab="${tab}"`)).to.have.length(3);
    }
  });

  it("keeps the tab panels labelled by name only", async () => {
    // Load the analytics template.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify every panel keeps its id, role and aria-label without aria-labelledby.
    expect(template).to.include('id="analytics-panel-groups" role="tabpanel" aria-label="Groups"');
    expect(template).to.include('id="analytics-panel-members" role="tabpanel" aria-label="Members"');
    expect(template).to.include('id="analytics-panel-events" role="tabpanel" aria-label="Events"');
    expect(template).to.include('id="analytics-panel-attendees" role="tabpanel" aria-label="Attendees"');
    expect(template).to.include('id="analytics-panel-page-views" role="tabpanel" aria-label="Page views"');
    expect(template.match(/role="tabpanel"/g)).to.have.length(5);
    expect(template).not.to.include("aria-labelledby");
  });
});
