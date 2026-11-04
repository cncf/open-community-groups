import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/inbox_list.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard inbox list template", () => {
  it("spans the empty state across the columns visible at each breakpoint", async () => {
    // Load the shared inbox list template before checking the empty cells.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify one empty cell per breakpoint, matching the hidden columns.
    expect(template.match(/colspan="\d"/g)).to.deep.equal(['colspan="3"', 'colspan="4"', 'colspan="5"']);
  });

  it("renders the status badge with the last activity cue", async () => {
    // Load the shared inbox list template before checking the status cell.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the typed status badge and the compact last writer line.
    expect(template).to.include("{{ badges::inbox_status_badge(status = conversation.status) -}}");
    expect(template).to.include(
      '<span class="block truncate">From {{ last_writer_label(conversation)|lower }}</span>',
    );
  });

  it("keeps the status filter menu aligned to the column end", async () => {
    // Load the shared inbox list template before checking the filter menu.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the status filter dropdown stays anchored to the column end.
    expect(template).to.include('dropdown_classes = "end-0"');
    expect(template).to.include("data-inbox-conversation-row");
  });
});
