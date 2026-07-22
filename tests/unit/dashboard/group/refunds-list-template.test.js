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

  it("exposes the refund list filters", async () => {
    // Load the refunds list template before checking filter markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the list exposes each supported filter.
    expect(template).to.include('id="refund-filters"');
    expect(template).to.include('name="ts_query"');
    expect(template).to.include('name="event_id"');
    expect(template).to.include('for="refund-event"');
    expect(template).to.include('text-sm font-semibold text-nowrap text-stone-900">Event');
    expect(template).to.include('id="refund-view"');
    expect(template).to.include('name="view"');
    expect(template).to.include('class="block h-10 w-40 rounded-md');
    expect(template).to.include('for="refund-view"');
    expect(template).to.include('text-sm font-semibold text-nowrap text-stone-900">Refund status');
    expect(template).to.include("RefundsView::Attention");
    expect(template).to.include("RefundsView::Active -%} Active");
    expect(template).to.include("RefundsView::Completed -%} Completed");
    expect(template).to.include("Needs attention");
    expect(template).to.include("data-refund-search-clear");
    expect(template).to.include('aria-label="Clear refund search"');
    expect(template).to.include("icon-close");
    expect(template).to.include('hx-get="/dashboard/group/refunds"');
    expect(template).to.include('hx-ext="no-empty-vals"');
    expect(template).to.include('hx-trigger="change, submit"');
    expect(template).to.include("flex flex-col gap-6 xl:flex-row xl:items-start xl:justify-between");
    expect(template).to.include("flex-wrap items-center justify-start gap-6");
    expect(template).to.include("xl:justify-end");
    expect(template).to.include("dashboard/placeholders/group_refunds_table.html");
    expect(template).not.to.include(">Clear</a>");
    expect(template).not.to.include("View attendees");
  });

  it("shows checkout, provider, recovery, and completion status contracts", async () => {
    // Load the refunds list template before checking status markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify refund rows expose each status and audit detail.
    expect(template).to.include("refund.status.label()");
    expect(template).to.include("refund.status.tone()");
    expect(template).to.include("refund.failure_message");
    expect(template).to.include("refund.attempt_count");
    expect(template.split("*attempt_count != 1")).to.have.lengthOf(3);
    expect(template).to.include("refund.created_at");
    expect(template).to.include("refund.provider_refund_id");
    expect(template).to.include("refund.review_note");
  });

  it("keeps refund details visible without a narrow-table scrollbar", async () => {
    // Load the refunds list template before checking responsive table markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify narrow layouts combine details while wider layouts restore columns.
    expect(template).to.include('class="relative overflow-visible"');
    expect(template).to.not.include("min-w-[920px]");
    expect(template).to.include('class="hidden xl:table-cell px-3 xl:px-5 py-3">Event');
    expect(template).to.include('class="hidden xl:table-cell px-3 xl:px-5 py-3">Status');
    expect(template).to.include('class="hidden 2xl:table-cell px-3 xl:px-5 py-3">Updated');
    expect(template).to.include('class="w-[40%] px-3 py-3 xl:w-auto xl:px-5">Attendee');
    expect(template).to.include('class="w-[40%] px-3 py-4 xl:w-auto xl:max-w-64 xl:px-5"');
    expect(template).to.include('class="mb-2 truncate font-medium text-stone-900 xl:hidden"');
    expect(template).to.include('class="mt-2 text-xs text-stone-500 2xl:hidden"');
    expect(template).to.include('colspan="3" class="xl:hidden');
    expect(template).to.include('colspan="5" class="hidden xl:table-cell 2xl:hidden');
    expect(template).to.include('colspan="6" class="hidden 2xl:table-cell');
  });

  it("addresses review and retry actions by purchase identifier", async () => {
    // Load the refunds list template before checking action markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify review and retry actions use the purchase identifier.
    expect(template).to.include(
      'data-refund-approve-url="/dashboard/group/refunds/{{ refund.event_purchase_id }}/approve"',
    );
    expect(template).to.include("data-refund-approve-open");
    expect(template).to.include('hx-put="/dashboard/group/refunds/{{ refund.event_purchase_id }}/retry"');
    expect(template).to.include(
      'data-refund-reject-url="/dashboard/group/refunds/{{ refund.event_purchase_id }}/reject"',
    );
    expect(template).to.include("data-refund-reject-open");
    expect(template).to.include(
      'data-refund-reason="{{ refund.requested_reason.as_deref() |assigned_or("") }}"',
    );
    expect(template).to.include("dashboard::refund_review_modal");
    expect(template).to.include('id_prefix = "refund-reject"');
    expect(template).to.include('review_note_id = "refund-review-note"');
    expect(template).to.include(
      "Add a review note to explain why this refund request is being rejected.",
    );
    expect(template).to.include('id_prefix = "refund-approve"');
    expect(template).to.include('review_note_id = "refund-approve-review-note"');
    expect(template.match(/show_reason = true/g)).to.have.lengthOf(2);
    expect(template).to.include(
      "Add a review note to explain why this refund request is being approved.",
    );
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
