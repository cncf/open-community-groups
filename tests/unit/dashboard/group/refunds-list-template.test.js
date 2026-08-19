import { expect } from "@open-wc/testing";

const loadDashboardMacros = async () => {
  const response = await fetch("/ocg-server/templates/macros/dashboard.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const loadTemplate = async () => {
  const response = await fetch(
    "/ocg-server/templates/dashboard/group/refunds_list.html",
  );

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group refunds list template", () => {
  it("requires an attendee-visible reason only for refund rejections", async () => {
    // Load the shared modal macro before checking both review variants.
    const macros = normalizeWhitespace(await loadDashboardMacros());

    // Rejections expose required attendee-visible copy and accessible helper text.
    expect(macros).to.include("review_note_required = false");
    expect(macros).to.include("Reason shown to attendee");
    expect(macros).to.include("Review note (optional)");
    expect(macros).to.include(
      'aria-describedby="{{ review_note_id }}-help" required',
    );
    expect(macros).to.include('id="{{ review_note_id }}-help"');
    expect(macros).to.include(
      "This reason appears in the attendee's email, My Events, and the event page.",
    );
  });

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
    expect(template).to.include(
      'text-sm font-semibold text-nowrap text-stone-900">Event',
    );
    expect(template).to.include('id="refund-view"');
    expect(template).to.include('name="view"');
    expect(template).to.include('class="block h-10 w-40 rounded-md');
    expect(template).to.include('for="refund-view"');
    expect(template).to.include(
      'text-sm font-semibold text-nowrap text-stone-900">Refund status',
    );
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
    expect(template).to.include(
      "flex flex-col gap-6 xl:flex-row xl:items-start xl:justify-between",
    );
    expect(template).to.include("flex-wrap items-center justify-start gap-6");
    expect(template).to.include("xl:justify-end");
    expect(template).to.include(
      "dashboard/placeholders/group_refunds_table.html",
    );
    expect(template).not.to.include(">Clear</a>");
    expect(template).not.to.include("View attendees");
  });

  it("shows checkout, provider, recovery, and completion status contracts", async () => {
    // Load the refunds list template before checking status markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify refund rows expose each status and audit detail.
    expect(template).to.include("refund.status.label()");
    expect(template).to.include("badges::payment_status_badge");
    expect(template).to.include("refund.status.tone()");
    expect(template).to.include("refund.failure_message");
    expect(template).to.include("refund.attempt_count");
    expect(template).to.include("attempt_count > 0 && refund.can_retry()");
    expect(template).to.include("refund.created_at");
    expect(template).to.include("refund.provider_refund_id");
    expect(template).to.include("refund.review_note");
  });

  it("keeps the refund price visible and moves secondary details into a tooltip", async () => {
    // Load the refunds list template before checking refund detail placement.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the stone price badge owns an accessible details tooltip.
    expect(template).to.include(
      "data-localized-currency>{{ refund.formatted_amount() }}</span>",
    );
    expect(template).to.include(
      'class="custom-badge border-stone-500 bg-stone-100 px-2.5 py-0.5 text-stone-700"',
    );
    expect(template).not.to.include("icon-info");
    expect(template).to.include(
      "relative inline-flex cursor-help rounded-full",
    );
    expect(template).to.include(
      "-end-1 -top-1 size-2.5 rounded-full border-2 border-white bg-stone-500",
    );
    expect(template).to.include(
      "refund-details-{{ refund.event_purchase_id }}",
    );
    expect(template).to.include(
      'aria-describedby="{{ refund_details_tooltip_id }}"',
    );
    expect(template).to.include("dashboard::tooltip_panel(");
    expect(template).to.include('title = "Refund details"');
    expect(template).to.include('width_classes = "w-72"');
    expect(template).to.include(
      '<span class="block font-semibold text-stone-500">Ticket</span>',
    );
    expect(template).to.include(
      '<span class="mt-0.5 block text-stone-900">{{ refund.ticket_title }}</span>',
    );
    expect(template).to.include(
      '<span class="mt-0.5 block text-stone-900">{{ refund.created_at.format("%b %d, %Y") }}</span>',
    );
    expect(template).to.include(
      '<span class="mt-0.5 block text-stone-900">{{ refund.updated_at.format("%b %d, %Y at %H:%M UTC") }}</span>',
    );
    expect(template).to.include(
      '<span class="block 2xl:hidden"> <span class="block font-semibold text-stone-500">Updated</span>',
    );
    expect(template).not.to.include(
      'class="mt-2 text-xs text-stone-500 2xl:hidden"',
    );

    // Verify the tooltip distinguishes refund origin from attendee request copy.
    expect(template).to.include("Original attendee request reason");
    expect(template).to.include(
      'refund.kind.as_deref() == Some("attendance-cancellation")',
    );
    expect(template).to.include(
      'refund.kind.as_deref() == Some("event-cancellation")',
    );
    expect(template).not.to.include(
      '<div class="mt-1 text-xs text-stone-600">{{ refund.kind_label() }}</div>',
    );
    expect(template).to.include(
      '<span class="block font-semibold text-stone-500">Request</span>',
    );
    expect(template).to.include(
      '<span class="block font-semibold text-stone-500">Review</span>',
    );
    expect(template).to.include("group-hover/refund-details:visible");
    expect(template).to.include("group-focus-within/refund-details:visible");
  });

  it("keeps refund details visible without a narrow-table scrollbar", async () => {
    // Load the refunds list template before checking responsive table markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify narrow layouts combine details while wider layouts restore columns.
    expect(template).to.include('class="relative overflow-visible"');
    expect(template).to.not.include("min-w-[920px]");
    expect(template).to.include(
      'class="hidden xl:table-cell px-3 xl:px-5 py-3">Event',
    );
    expect(template).to.include(
      'class="hidden xl:table-cell px-3 xl:px-5 py-3">Status',
    );
    expect(template).to.include(
      'class="hidden 2xl:table-cell px-3 xl:px-5 py-3">Updated',
    );
    expect(template).to.include(
      'class="w-[40%] px-3 py-3 xl:w-auto xl:px-5">Attendee',
    );
    expect(template).to.include(
      'class="w-[40%] px-3 py-4 xl:w-auto xl:max-w-64 xl:px-5"',
    );
    expect(template).to.include(
      'class="mb-2 truncate font-medium text-stone-900 xl:hidden"',
    );
    expect(template).to.include('colspan="3" class="xl:hidden');
    expect(template).to.include(
      'colspan="5" class="hidden xl:table-cell 2xl:hidden',
    );
    expect(template).to.include('colspan="6" class="hidden 2xl:table-cell');
  });

  it("presents exhausted financial work in a neutral table", async () => {
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).not.to.include(
      'class="mb-8 rounded-xl border border-stone-200 bg-stone-50/60 p-4 sm:p-5"',
    );
    expect(template).to.include(
      'aria-label="Financial work needing attention"',
    );
    expect(
      template.indexOf('aria-label="Financial work needing attention"'),
    ).to.be.lessThan(template.indexOf('id="refund-filters"'));
    expect(template).to.include(
      '<caption class="border-b border-amber-200 bg-amber-50 px-3 py-3 text-left text-amber-900 xl:px-5">',
    );
    expect(template).to.include(
      'class="relative mt-8 mb-10 overflow-x-auto lg:overflow-x-visible"',
    );
    expect(template).to.include("Financial work needs attention");
    expect(template).to.include("Automatic retries are exhausted.");
    expect(template).to.include(
      'data-financial-work-kind="{{ recovery.kind }}"',
    );
    expect(template).to.include(
      '<th scope="col" class="px-3 py-3 xl:px-5">Attendee</th>',
    );
    expect(template).to.include(
      '<th scope="col" class="px-3 py-3 xl:px-5">Event</th>',
    );
    expect(template).to.include(
      '<th scope="col" class="px-3 py-3 xl:px-5">Operation</th>',
    );
    expect(template).to.include(
      '<th scope="col" class="px-3 py-3 xl:px-5">Status</th>',
    );
    expect(template).not.to.include(
      '<th scope="col" class="px-3 py-3 xl:px-5">Attempts</th>',
    );
    expect(template).to.include(
      '<td class="px-3 py-4 text-stone-900 xl:px-5">{{ recovery.operation }}</td>',
    );
    expect(template).not.to.include(
      '<th scope="col" class="px-4 py-3 text-right">Actions</th>',
    );
    expect(
      template.match(
        /class="odd:bg-white even:bg-stone-50\/50 border-b border-stone-200 align-middle"/g,
      ),
    ).to.have.lengthOf(2);
    expect(template).to.include('<span class="sr-only">Actions</span>');
    expect(template).to.include('title = "Last failure"');
    expect(template).to.include(
      "{{ recovery.failure_message }} ({{ recovery.attempt_count }} attempt{% if recovery.attempt_count != 1 %}s{% endif %})",
    );
    expect(template).to.include(
      'class="pointer-events-none absolute -end-1 -top-1 size-2.5 rounded-full border-2 border-white bg-red-800"',
    );
    expect(template).to.include(
      '<span class="custom-badge border-red-800 bg-red-100 px-2.5 py-0.5 text-red-800">Needs retry</span>',
    );
    expect(template).not.to.include(
      '<span class="block font-semibold text-stone-500">Attempts</span>',
    );
    expect(template).to.include(
      'class="custom-badge border-red-800 bg-red-100 px-2.5 py-0.5 text-red-800"',
    );
    expect(template).to.include("data-financial-recovery-open");
    expect(template).to.include("svg-icon size-4 icon-pencil");
    expect(template).to.include(
      'hx-put="/dashboard/group/financial-work/retry"',
    );
    expect(template).to.include('id="financial-recovery-modal"');
    expect(template).to.include(
      'hx-put="/dashboard/group/financial-work/recovery"',
    );
    expect(template).to.include('name="provider_object_id"');
    expect(template).to.include('name="recovery_reference"');
    expect(template).to.include('name="recovery_note"');
    expect(template).not.to.include("bg-red-50/40");
    expect(template).not.to.include("shadow-sm");
  });

  it("shows retry counts only for exhausted status badges", async () => {
    const template = normalizeWhitespace(await loadTemplate());

    expect(
      template.match(/attempt_count > 0 && refund\.can_retry\(\)/g),
    ).to.have.lengthOf(2);
    expect(
      template.match(
        /\{\{ refund\.status\.label\(\) \}\} \(\{\{ attempt_count \}\} attempt/g,
      ),
    ).to.have.lengthOf(2);
    expect(template).not.to.include('title = "Retry attempts"');
    expect(template).not.to.include("refund-attempts");
    expect(template).not.to.include("attempt_count <= 0");
    expect(template).not.to.include("!refund.can_retry()");
    expect(template).not.to.include('class="mt-2 text-xs text-stone-600"');
  });

  it("addresses review and retry actions by purchase identifier", async () => {
    // Load the refunds list template before checking action markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify review and retry actions use the purchase identifier.
    expect(template).to.include(
      'data-refund-approve-url="/dashboard/group/refunds/{{ refund.event_purchase_id }}/approve"',
    );
    expect(template).to.include("data-refund-approve-open");
    expect(template).to.include(
      'hx-put="/dashboard/group/refunds/{{ refund.event_purchase_id }}/retry"',
    );
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
      "Explain why this refund request is being rejected.",
    );
    expect(template).to.include("review_note_required = true");
    expect(template).to.include('id_prefix = "refund-approve"');
    expect(template).to.include(
      'review_note_id = "refund-approve-review-note"',
    );
    expect(template.match(/show_reason = true/g)).to.have.lengthOf(2);
    expect(template).to.include(
      "Add a review note to explain why this refund request is being approved.",
    );
    expect(template).to.include("data-actions-menu");
    expect(template).to.include("refund.can_retry()");
    expect(template).not.to.include('role="menu"');
    expect(template).not.to.include('role="menuitem"');
    expect(template).to.include(
      'class="dropdown absolute end-0 top-8 z-10 w-[210px] rounded-lg border border-stone-200 bg-white py-1 shadow-lg"',
    );
    expect(template).to.include(
      "gap-2 px-3 py-2 text-left text-sm text-stone-700 transition-colors hover:bg-stone-50",
    );
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
    expect(template).to.include(
      "Events write access is required to complete refund recovery.",
    );
    expect(template).to.include(
      "refund-recovery-requirement-{{ refund.event_purchase_id }}",
    );
    expect(template).to.include('aria-describedby="{{ recovery_tooltip_id }}"');
    expect(template).to.include('title = "Recovery unavailable"');
    expect(template).to.include('alignment_classes = "end-1"');
    expect(template).to.include('id="refund-recovery-modal"');
    expect(template).to.include('hx-put="/dashboard/group/refunds/recovery"');
    expect(template).to.include('name="recovery_reference"');
    expect(template).to.include('name="recovery_note"');
  });
});
