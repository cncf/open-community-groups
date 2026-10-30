import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/community/home.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard community home template", () => {
  it("loads the tooltip panel enhancement for dashboard content", async () => {
    // Load the community dashboard shell before checking the tooltip wiring.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the tooltip module loads and its dashboard content scope is rendered.
    expect(template).to.include('{% extends "dashboard/dashboard_base.html" -%}');
    expect(template).to.include('<script type="module" src="/static/js/common/tooltip-panel.js">');
    expect(template).to.include('<div id="dashboard-content"');
  });

  it("uses the shared dashboard menu shell", async () => {
    // Load the community dashboard shell before checking menu layout.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the shell delegates its title and keeps the drawer trigger out of mobile.
    expect(template).to.include('dashboard::dashboard_menu_shell("Community Dashboard")');
    expect(template).to.include("{% block mobile_menu_button -%} {% endblock mobile_menu_button -%}");
    expect(template).to.include('hx-trigger="refresh-community-dashboard-table"');
  });
});
