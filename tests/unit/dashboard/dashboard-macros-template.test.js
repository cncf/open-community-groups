import { expect } from "@open-wc/testing";

const loadTemplate = async (path = "macros/dashboard.html") => {
  const response = await fetch(`/ocg-server/templates/${path}`);

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard macros template", () => {
  it("renders the shared dashboard menu shell", async () => {
    // Load the dashboard macros template before checking the shared shell.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify dashboard shells share the menu title, spinner, and caller wrapper.
    expect(template).to.include(
      'macro dashboard_menu_shell(title, spinner_classes = "group hx-spinner -mt-0.5 relative", navigation_target = "body", navigation_select = "", navigation_select_oob = "", navigation_swap = "")',
    );
    expect(template).to.include('id="dashboard-menu"');
    expect(template).to.include('hx-target="{{ navigation_target }}"');
    expect(template).to.include('id="dashboard-spinner"');
    expect(template).to.include('{{ ui::spinner(size = "size-5") -}}');
    expect(template).to.include("max-h-full w-full flex flex-col flex-1");
    expect(template).to.include("{{ caller() }}");
  });

  it("inherits dashboard navigation swap options from the menu shell", async () => {
    // Load the dashboard macros template before checking HTMX navigation ownership.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify menu links inherit their target while retaining request and history contracts.
    expect(template).to.include('hx-select="{{ navigation_select }}"');
    expect(template).to.include('hx-select-oob="{{ navigation_select_oob }}"');
    expect(template).to.include('hx-swap="{{ navigation_swap }}"');
    expect(template).not.to.include('<a hx-get="{{ href }}" hx-target="body"');
    expect(template).to.include('<a href="{{ href }}" hx-get="{{ href }}"');
    expect(template).to.include('hx-indicator="#dashboard-spinner" hx-push-url="true"');
  });

  it("passes the curated dashboard user payload to profile modal triggers", async () => {
    // Load the dashboard macros template before checking profile trigger data.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the shared macro uses the backend-curated dashboard user object.
    expect(template).to.include("data-user-profile-modal");
    expect(template).to.include("data-user-profile='{{ user|json }}'");
    expect(template).not.to.include("data-user-profile-username");
  });

  it("uses dropdown menus for table filtering", async () => {
    // Load the dashboard macros template before checking table control icons.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify table filters use the filled caret treatment.
    expect(template).to.include("macro table_filter_option_button");
    expect(template).to.include("is_clear_option = false");
    expect(template).to.include("is_clear_option && clear_value.is_empty()");
    expect(template).to.include(
      'macro table_filter_menu(id, label, is_active, extra_classes = "", dropdown_classes = "start-0")',
    );
    expect(template).to.include("{{ dropdown_classes }} top-full");
    expect(template).to.include("icon-caret-down-filled");
    expect(template).to.include("icon-caret-down-filled bg-current");
    expect(template).to.include("{{ label }} filters");
    expect(template).not.to.include("bg-primary-500 {% else -%} bg-current");
    expect(template).not.to.include("bg-primary-50 text-stone-900 ring-1 ring-primary-200");
  });

  it("renders active table filter badges with filter title and value", async () => {
    // Load the dashboard macros template before checking active filter badges.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify active filter badges display the filter title beside the value.
    expect(template).to.include("macro active_table_filter_badge(title, label)");
    expect(template).to.include(
      "custom-badge inline-flex items-center gap-1.5 bg-stone-50 px-2.5 py-0.5 text-stone-700",
    );
    expect(template).to.include('<span class="font-semibold text-stone-900">{{ title }}:</span>');
    expect(template).to.include("<span>{{ label }}</span>");
  });

  it("uses compact line height and safe wrapping for dashboard titles", async () => {
    // Load the dashboard macros template before checking title layout.
    const template = normalizeWhitespace(await loadTemplate());

    // Page and form titles share wrapping and line-height behavior.
    expect(template).to.include('<div class="min-w-0">');
    expect(template).to.include(
      'class="min-w-0 text-xl leading-tight font-medium text-stone-900 lg:text-2xl"',
    );
    expect(template).to.include('class="text-xl leading-tight font-medium text-stone-900 lg:text-2xl"');
  });

  it("renders a consistent titled tooltip panel", async () => {
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include("macro tooltip_panel(");
    expect(template).to.include('width_classes = "w-64"');
    expect(template).to.include('alignment_classes = "start-1/2 -translate-x-1/2"');
    expect(template).to.include('id="{{ id }}" role="tooltip"');
    expect(template).to.include('role="tooltip" data-tooltip-panel');
    expect(template).to.include("rounded-lg border border-stone-200 bg-white");
    expect(template).to.include("max-w-[calc(100vw-2rem)]");
    expect(template).to.include("break-words whitespace-normal");
    expect(template).to.include("text-left text-xs font-normal leading-5 text-stone-700");
    expect(template).to.include(
      "border-b border-stone-200 bg-stone-50 px-3 py-2 text-sm font-semibold text-stone-900",
    );
    expect(template).to.include('<span class="block space-y-2 px-3 py-3">{{ caller() }}</span>');
  });

  it("renders an optional selectable id beside title descriptions", async () => {
    // Load the dashboard macros template before checking title id slots.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify both title macros accept an id and render it after the description.
    expect(template).to.include(
      'macro form_title(title, description = "", button = "", id = "")',
    );
    expect(template).to.include(
      'macro page_title(title, docs_href, description = "", button = "", docs_aria_label = "", id = "")',
    );
    // Check each macro body separately so a regression in either one is caught.
    const macros = template.split("{% macro ");
    const formTitle = macros.find((macro) => macro.startsWith("form_title("));
    const pageTitle = macros.find((macro) => macro.startsWith("page_title("));
    const idMarkup =
      '{% if !description.is_empty() || !id.is_empty() -%} <div class="mt-1 flex flex-wrap items-center gap-x-3 gap-y-0"> {% if !description.is_empty() -%} <p class="text-sm/6 text-stone-500 m-0">{{ description }}</p> {% endif -%} {% if !id.is_empty() -%} <p class="text-xs/6 text-stone-500 m-0">(ID: <span class="font-mono select-all">{{ id }}</span>)</p> {% endif -%}';

    expect(formTitle).to.include(idMarkup);
    expect(pageTitle).to.include(idMarkup);
  });

  it("renders shared refund review modal contracts", async () => {
    // Load the dashboard macros template before checking refund review markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify decision modals share accessible, form, context, and note contracts.
    expect(template).to.include("macro refund_review_modal");
    expect(template).to.include('id="{{ id_prefix }}-modal"');
    expect(template).to.include('aria-describedby="{{ id_prefix }}-modal-description"');
    expect(template).to.include('id="{{ id_prefix }}-form"');
    expect(template).to.include('name="review_note"');
    expect(template).to.include("{% if show_reason -%}");
    expect(template).to.include("Review note (optional)");
  });

  it("renders the shared mobile notice with a touch-only desktop version hint", async () => {
    // Load the dashboard macros template before checking the mobile notice.
    const template = normalizeWhitespace(await loadTemplate());
    const macro = template.slice(template.indexOf("{% macro mobile_notice() -%}"));

    // Verify the overlay keeps its original card and heading.
    expect(macro).to.include(
      '<div class="fixed inset-0 z-10 flex items-center justify-center bg-stone-100 px-6 pt-16 md:hidden">',
    );
    expect(macro).to.include(
      '<p class="text-xl font-medium">This dashboard is not optimized yet for mobile devices</p>',
    );

    // Verify the hint only shows where the user menu offers the desktop version entry.
    expect(macro).to.include('<p class="hidden pointer-coarse:block text-sm text-stone-600 mt-4">');
    expect(macro).to.include("load the desktop version from the user menu at the top right");
    expect(macro).to.include("you can switch back from the same menu");
  });

  it("is used by every dashboard instead of an inline mobile notice", async () => {
    // Load the dashboard shells that render the mobile notice.
    const templates = await Promise.all([
      loadTemplate("dashboard/dashboard_base.html"),
      loadTemplate("dashboard/user/home.html"),
      loadTemplate("dashboard/group/home.html"),
    ]);

    // Verify each shell delegates to the shared macro and carries no copy of the card.
    templates.forEach((source) => {
      const template = normalizeWhitespace(source);
      expect(template).to.include("{{ dashboard::mobile_notice() -}}");
      expect(template).not.to.include("This dashboard is not optimized yet for mobile devices");
    });

    // Verify the group dashboard keeps the notice inside its out-of-band swap container.
    const groupTemplate = normalizeWhitespace(templates[2]);
    expect(groupTemplate).to.include(
      '<div id="mobile-dashboard-view" class="contents"> {% if !content.is_check_in() && !is_check_in_fallback -%} {{ dashboard::mobile_notice() -}} {% endif -%} </div>',
    );
  });
});
