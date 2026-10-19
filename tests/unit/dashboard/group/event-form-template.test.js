import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/macros/event_form.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

const extractMacro = (template, name) =>
  template.slice(
    template.indexOf(`{% macro ${name}(`),
    template.indexOf(`{% endmacro ${name} -%}`),
  );

describe("event form macros", () => {
  it("renders grouped tab options in the compact section select", async () => {
    // Load the tab navigation macro.
    const tabNav = extractMacro(normalizeWhitespace(await loadTemplate()), "tab_nav");

    // Verify the select keeps its section contract and groups options by heading.
    expect(tabNav).to.include(
      '<select id="{{ id_prefix }}-select" data-section-select aria-label="Event form section" class="select-primary w-full sm:w-sm xl:hidden">',
    );
    expect(tabNav).to.include(
      '{% for group in groups.iter() -%} <optgroup label="{{ group.label }}"> {% for tab in group.tabs -%} {{ tab_option(section = tab.section, label = tab.label, active = tab.active) -}} {% endfor -%} </optgroup> {% endfor -%} </select>',
    );
  });

  it("renders sidebar headings that label their tab lists without a section", async () => {
    // Load the tab navigation macro.
    const tabNav = extractMacro(normalizeWhitespace(await loadTemplate()), "tab_nav");

    // Verify each group heading labels its list and carries no data-section.
    expect(tabNav).to.include(
      '<nav aria-label="Event form sections" class="hidden flex-col gap-4 xl:flex">',
    );
    expect(tabNav).to.include(
      '<div id="{{ id_prefix }}-{{ group.kind }}-heading" class="px-3 pb-1 text-xs/6 text-stone-500 uppercase">{{ group.label }}</div>',
    );
    expect(tabNav).to.include(
      '<ul aria-labelledby="{{ id_prefix }}-{{ group.kind }}-heading" class="flex flex-col gap-1 font-medium">',
    );
    expect(tabNav.match(/data-section=/gu)).to.equal(null);

    // Verify tab buttons build escaped lazy-load attributes from the catalog.
    expect(tabNav).to.include("{% if let Some(lazy_load) = tab.lazy_load -%}");
    expect(tabNav).to.include(
      'hx-get="{{ lazy_load.url }}" hx-trigger="click once" hx-target="{{ lazy_load.target }}" hx-swap="innerHTML" hx-indicator="{{ lazy_load.indicator }}"',
    );
    expect(tabNav).to.include(
      "{{ tab_button(section = tab.section, icon = tab.icon, label = tab.label, active = tab.active, extra_attrs = lazy_load_attrs) -}}",
    );
  });

  it("keeps the section contract on tab buttons and options", async () => {
    // Load the tab button and option macros.
    const template = normalizeWhitespace(await loadTemplate());
    const tabButton = extractMacro(template, "tab_button");
    const tabOption = extractMacro(template, "tab_option");

    // Verify buttons and options expose the section names used by page scripts.
    expect(tabButton).to.include('data-section="{{ section }}" data-active="{{ active_value }}" {{ extra_attrs|safe }}');
    expect(tabOption).to.include('<option value="{{ section }}" {% if active -%} selected {% endif -%}>{{ label }}</option>');
  });
});
