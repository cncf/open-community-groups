import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/refunds_list.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group refunds list template", () => {
  it("refreshes the active refunds partial without losing its filters", async () => {
    // Load the refunds list template before checking refresh markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify action-triggered refreshes preserve the current filters.
    expect(template).to.include('id="refunds-refresh"');
    expect(template).to.include('hx-get="{{ refresh_url }}"');
    expect(template).to.include('hx-trigger="refresh-group-refunds from:body"');
    expect(template).to.include('hx-target="#dashboard-content"');
  });

  it("exposes the operational refund views and list filters", async () => {
    // Load the refunds list template before checking view and filter markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the list exposes each operational view and supported filter.
    expect(template).to.include('aria-label="Refund views"');
    expect(template).to.include("option.dashboard_url");
    expect(template).to.include("option.partial_url");
    expect(template).to.include("option.label");
    expect(template).to.include('id="refund-view-{{ loop.index0 }}"');
    expect(template).to.include('aria-current="page"');
    expect(template).to.include('id="refund-filters"');
    expect(template).to.include('id="refund-filter-apply"');
    expect(template).to.include('name="ts_query"');
    expect(template).to.include('name="event_id"');
    expect(template).to.include('hx-get="/dashboard/group/refunds"');
    expect(template).to.include(`hx-disabled-elt="find button[type='submit']"`);
    expect(template).to.include('hx-ext="no-empty-vals"');
    expect(template).to.include("dashboard/placeholders/group_refunds_table.html");
  });

  it("shows checkout, provider, recovery, and completion status contracts", async () => {
    // Load the refunds list template before checking status markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify refund rows expose each status and audit detail.
    expect(template).to.include("refund.status.label()");
    expect(template).to.include("refund.status.tone()");
    expect(template).to.include("refund.failure_message");
    expect(template).to.include("refund.attempt_count");
    expect(template).to.include("refund.created_at");
    expect(template).to.include("refund.provider_refund_id");
    expect(template).to.include("refund.review_note");
  });

  it("addresses review and retry actions by purchase identifier", async () => {
    // Load the refunds list template before checking action markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify review and retry actions use the purchase identifier.
    expect(template).to.include('hx-put="/dashboard/group/refunds/{{ refund.event_purchase_id }}/approve"');
    expect(template).to.include('hx-put="/dashboard/group/refunds/{{ refund.event_purchase_id }}/reject"');
    expect(template).to.include('hx-put="/dashboard/group/refunds/{{ refund.event_purchase_id }}/retry"');
    expect(template).to.include('id="reject-refund-{{ refund.event_purchase_id }}"');
    expect(template).to.include("data-confirm-action");
    expect(template).to.include("data-actions-menu");
    expect(template).to.include("refund.can_retry()");
    expect(template).not.to.include('role="menu"');
    expect(template).not.to.include('role="menuitem"');
  });

  it("shows event-management recovery controls and explains disabled access", async () => {
    // Load the refunds list template before checking recovery controls.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify recovery controls expose access requirements and form fields.
    expect(template).to.include("refund.can_recover()");
    expect(template).to.include("can_manage_events");
    expect(template).not.to.include("is_group_admin");
    expect(template).to.include("data-refund-recovery-open");
    expect(template).to.include("disabled");
    expect(template).to.include("Events write access is required to complete refund recovery.");
    expect(template).to.include('role="tooltip"');
    expect(template).to.include('id="refund-recovery-modal"');
    expect(template).to.include('hx-put="/dashboard/group/refunds/recovery"');
    expect(template).to.include('name="recovery_reference"');
    expect(template).to.include('name="recovery_note"');
  });
});
