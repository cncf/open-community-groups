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

    // Verify each section renders both charts with their original padding explicitly.
    expect(page.match(/stats_macro::stats_section\(/g)).to.have.length(4);
    expect(macros.match(/call analytics_chart\(/g)).to.have.length(2);
    expect(macros.match(/padding_class = "px-2 py-4 md:p-6"/g)).to.have.length(2);

    // Verify the chart wrapper renders the padding before the caller's classes.
    expect(macros).to.include('padding_class = "px-2 py-4 md:p-4 xl:p-6") -%}');
    expect(macros).to.include("rounded-lg {{ padding_class }} {{ wrapper_class }}");
  });

  it("shortens charts on phones without changing the desktop height", async () => {
    // Load the shared stats section macro.
    const macros = await loadTemplate("macros/stats.html");

    // Verify running and monthly charts carry their phone heights after the desktop one.
    expect(macros.match(/class = "h-\[320px\] phone:h-\[224px\] phone:min-h-0"/g)).to.have.length(1);
    expect(macros.match(/class = "h-\[320px\] phone:h-\[208px\] phone:min-h-0"/g)).to.have.length(1);
  });
});
