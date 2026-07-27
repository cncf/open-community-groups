import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/badges_awards.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group badge awards template", () => {
  it("renders always-visible filters with active filter summaries", async () => {
    // Load and normalize the award history template.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify filters remain visible and expose removable active summaries.
    expect(template).to.include('class="relative w-full max-w-full sm:w-[36rem]"');
    expect(template).to.include(
      'id="awards-advanced-filters" class="grid gap-4 rounded-lg border border-stone-200',
    );
    expect(template).not.to.include("data-awards-filters-toggle");
    expect(template).not.to.include("data-awards-filter-count");
    expect(template).not.to.include("data-awards-filters-panel");
    expect(template).not.to.include("data-awards-filter-control");
    expect(template).to.include('dashboard::active_table_filter_badge("Status", "Active")');
    expect(template).to.include('dashboard::active_table_filter_badge("Badge", badge.name)');
    expect(template).to.include('dashboard::active_table_filter_badge("Source", award_source.name)');
    expect(template).to.include('dashboard::active_table_filter_badge("Awarded from", from)');
    expect(template).to.include('dashboard::active_table_filter_badge("Through", to)');
    expect(template).to.include(">Clear all</a>");
  });

  it("keeps the revoke action disabled for revoked credentials", async () => {
    // Load and normalize the award history template.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify only active credentials expose the revoke dialog trigger.
    expect(template).to.include('data-badge-dialog-open="badge-revoke-{{ award.user_badge_id }}"');
    expect(template).to.include(
      'disabled aria-label="Revoke credential: {{ award.snapshot.name }} (already revoked)"',
    );
    expect(template).to.include('title="Credential already revoked"');
  });
});
