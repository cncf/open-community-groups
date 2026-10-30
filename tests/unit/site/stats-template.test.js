import { expect } from "@open-wc/testing";

/**
 * Loads a server template source as text.
 * @param {string} path - Template path relative to the templates folder.
 * @returns {Promise<string>} Template source.
 */
const loadTemplate = async (path) => {
  const response = await fetch(`/ocg-server/templates/${path}`);

  expect(response.ok).to.equal(true);

  return response.text();
};

describe("site stats template", () => {
  it("keeps the public chart padding while dashboards use the shared default", async () => {
    // Load the public stats page and the shared chart macro.
    const page = await loadTemplate("site/stats/page.html");
    const macros = await loadTemplate("macros/stats.html");

    // Verify every public chart passes its original padding explicitly.
    expect(page.match(/stats_macro::analytics_chart\(/g)).to.have.length(8);
    expect(page.match(/padding_class = "px-2 py-4 md:p-6"/g)).to.have.length(8);

    // Verify the chart wrapper renders the padding before the caller's classes.
    expect(macros).to.include('padding_class = "px-2 py-4 md:p-4 xl:p-6") -%}');
    expect(macros).to.include("rounded-lg {{ padding_class }} {{ wrapper_class }}");
  });
});
