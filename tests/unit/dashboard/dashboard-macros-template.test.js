import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/macros/dashboard.html");

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
});
