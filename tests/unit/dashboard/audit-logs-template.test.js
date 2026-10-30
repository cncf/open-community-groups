import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/audit_logs.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

const getSection = (template, start, end) => template.slice(template.indexOf(start), template.indexOf(end));

const getColspans = (section) => [...section.matchAll(/colspan="(\d+)"/g)].map(([, colspan]) => colspan);

describe("dashboard audit logs template", () => {
  it("spans every visible column in the empty state", async () => {
    // Load and isolate both empty state branches.
    const emptyState = getSection(
      normalizeWhitespace(await loadTemplate()),
      "{# Empty state -#}",
      "{# End empty state -#}",
    );
    const [actorBranch, nonActorBranch] = emptyState.split("{% else -%}");

    // Verify the actor branch covers 3, 4 and 5 columns and the other branch 3 and 4.
    expect(actorBranch).to.include("{% if show_actor -%}");
    expect(getColspans(actorBranch)).to.deep.equal(["3", "4", "5"]);
    expect(getColspans(nonActorBranch)).to.deep.equal(["3", "4"]);
  });

  it("shares the date column visibility between its header and cells", async () => {
    // Load the audit logs template.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the capture only applies when the actor column is shown.
    expect(template).to.include("{% let date_cell_visibility -%}{% if show_actor %}");

    // Verify the header and the row cell both use the capture.
    expect(template).to.match(/<th scope="col" class="\{\{ date_cell_visibility \}\} [^"]*">Date<\/th>/);
    expect(getSection(template, "{# Date -#}", "{# End date -#}")).to.include(
      '<td class="{{ date_cell_visibility }} ',
    );
  });

  it("lists the date in the details popover when the actor column is shown", async () => {
    // Load and isolate the details popover.
    const details = getSection(
      normalizeWhitespace(await loadTemplate()),
      "{# Details -#}",
      "{# End details -#}",
    );
    const typeIndex = details.indexOf(">Type</div>");
    const dateRowIndex = details.indexOf("{% if show_actor -%}");

    // Verify the date row follows the type row, behind the actor condition.
    expect(typeIndex).to.be.greaterThan(-1);
    expect(dateRowIndex).to.be.greaterThan(typeIndex);
    expect(details.slice(dateRowIndex)).to.match(
      /^\{% if show_actor -%\} <div [^>]*> <div [^>]*>Date<\/div> <div [^>]*> \{\{ log\.created_at\.format\("%b %d, %Y %I:%M %p UTC"\) \}\} <\/div> <\/div> \{% endif -%\}/,
    );
  });

  it("keeps the details popover contract", async () => {
    // Load and isolate the details popover.
    const details = getSection(
      normalizeWhitespace(await loadTemplate()),
      "{# Details -#}",
      "{# End details -#}",
    );

    // Verify the trigger and card keep the attributes the popover module reads.
    expect(details).to.include("data-audit-log-details-group");
    expect(details).to.include("data-audit-log-details-trigger");
    expect(details).to.include('aria-controls="{{ log.details_popover_id }}"');
    expect(details).to.include('aria-expanded="false"');
    expect(details).to.include('aria-label="View log details"');
    expect(details).to.include('id="{{ log.details_popover_id }}" data-audit-log-details-card');
  });
});
