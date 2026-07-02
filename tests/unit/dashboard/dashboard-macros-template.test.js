import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/macros/dashboard.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard macros template", () => {
  it("passes the curated dashboard user payload to profile modal triggers", async () => {
    // Load the dashboard macros template before checking profile trigger data.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the shared macro uses the backend-curated dashboard user object.
    expect(template).to.include("data-user-profile-modal");
    expect(template).to.include("data-user-profile='{{ user|json }}'");
    expect(template).not.to.include("data-user-profile-username");
  });

  it("uses dropdown menus for table sorting and filtering", async () => {
    // Load the dashboard macros template before checking table control icons.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify table sorting uses a dropdown menu with radio-style options.
    expect(template).to.include(
      'macro table_sort_menu(id, current_label, extra_classes = "", dropdown_classes = "end-0")',
    );
    expect(template).to.include(
      "macro table_sort_option_button(label, value, is_active, disabled = false)",
    );
    expect(template).to.include('aria-label="Sort by {{ current_label }}"');
    expect(template).to.include("{{ current_label }}");
    expect(template).to.include("name=\"sort\"");
    expect(template).to.include('value="{{ value }}"');
    expect(template).to.include("disabled:cursor-not-allowed disabled:opacity-50");
    expect(template).to.include('disabled aria-disabled="true"');
    expect(template).to.include("aria-pressed=");

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
    expect(template).not.to.include("bg-primary-500 {% else -%} bg-current");
    expect(template).not.to.include(
      "bg-primary-50 text-primary-700 ring-1 ring-primary-200",
    );
    expect(template).not.to.include(
      "bg-primary-50 text-stone-900 ring-1 ring-primary-200",
    );
  });
});
