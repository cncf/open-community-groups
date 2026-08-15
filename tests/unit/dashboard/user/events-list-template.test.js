import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch(
    "/ocg-server/templates/dashboard/user/events_list.html",
  );

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard user events list template", () => {
  it("renders cancel attendance as a confirmed delete action when cancellation is allowed", async () => {
    // Load the user events template before checking cancellation markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify allowed cancellations get a confirmed cancel action.
    expect(template).to.include("<span>Cancel attendance</span>");
    expect(template).to.include(
      'id="cancel-attendance-{{ item.event.event_id }}"',
    );
    expect(template).to.include("{% if item.can_cancel_attendance() -%}");
    expect(template).to.include(
      'hx-delete="/dashboard/user/events/{{ item.event.community_name }}/{{ item.event.event_id }}/attendance"',
    );
    expect(template).to.include('hx-trigger="confirmed"');
    expect(template).to.include('hx-disabled-elt="this"');
    expect(template).to.include("data-confirm-action");
    expect(template).to.include(
      'data-confirm-message="Are you sure you want to cancel your attendance?"',
    );
    expect(template).to.include(
      'data-success-message="You have successfully canceled your attendance."',
    );
    expect(template).to.include(
      'data-error-message="Something went wrong canceling your attendance. Please try again later."',
    );
  });

  it("keeps cancel attendance visible but disabled when cancellation is unavailable", async () => {
    // Load the user events template before checking disabled cancellation.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify unavailable cancellations stay visible and disabled.
    expect(template).to.include("disabled");
    expect(template).to.include(
      'title="This attendance cannot be canceled from My Events."',
    );
    expect(template).to.include('<span class="sr-only">Actions</span>');
    expect(template).to.include('aria-label="Open event actions"');
    expect(template).to.include("data-actions-menu");
    expect(template).to.include(
      'class="dropdown absolute end-0 top-8 z-10 w-[220px] overflow-hidden rounded-lg border border-stone-200 bg-white py-1 shadow-lg"',
    );
    expect(template).to.include(
      "gap-2 px-3 py-2 text-left text-sm text-stone-700 transition-colors hover:bg-stone-50",
    );
  });

  it("renders roles separately from enrollment and refund statuses on desktop", async () => {
    // Load the user events template before checking pending badges.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify role and status columns stay distinct on desktop.
    expect(template).to.include(
      "{% if let Some(enrollment_status_label) = item.enrollment_status_label() -%}",
    );
    expect(template).to.include(
      "{{ badges::payment_status_badge(label = enrollment_status_label) -}}",
    );
    expect(template).to.include(
      '{{ badges::common_badge(content = role.label() , extra_styles = Some("px-2.5 py-0.5")) -}}',
    );
    expect(template).to.include('{% if role.label() == "Event offer" -%}');
    expect(template).to.include(
      '{{ badges::common_badge(content = role.label() , extra_styles = Some("border-yellow-800 bg-yellow-100 px-2.5 py-0.5 text-yellow-800")) -}}',
    );
    expect(template).to.include('<span class="xl:hidden">Status / role</span>');
    expect(template).to.include('<span class="hidden xl:inline">Role</span>');
    expect(template).to.include(
      'class="hidden xl:table-cell px-3 xl:px-5 py-3 w-56">Status</th>',
    );
    expect(template).to.include(
      'class="hidden xl:table-cell px-3 xl:px-5 py-4 w-56"',
    );
    expect(template).to.include(
      'colspan="5">{% include "dashboard/placeholders/user_events_table.html"',
    );
    expect(template).to.include(
      'colspan="6"> {% include "dashboard/placeholders/user_events_table.html"',
    );
  });

  it("renders every refund status and exposes a rejected reason tooltip", async () => {
    // Load the user events template before checking refund feedback.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify each backend refund state has a clear badge.
    expect(template).to.include(
      "item.refund_request_status == Some(crate::types::payments::EventRefundRequestStatus::Pending)",
    );
    expect(template).to.include(
      '{{ badges::payment_status_badge(label = "Refund requested") -}}',
    );
    expect(template).to.include(
      "item.refund_request_status == Some(crate::types::payments::EventRefundRequestStatus::Approving)",
    );
    expect(template).to.include(
      '{{ badges::payment_status_badge(label = "Refund processing") -}}',
    );
    expect(template).to.include(
      "item.refund_request_status == Some(crate::types::payments::EventRefundRequestStatus::Approved)",
    );
    expect(template).to.include(
      '{{ badges::payment_status_badge(label = "Refund approved") -}}',
    );
    expect(template).to.include(
      "item.refund_request_status == Some(crate::types::payments::EventRefundRequestStatus::Rejected)",
    );
    expect(template).to.include(
      '{{ badges::payment_status_badge(label = "Refund rejected") -}}',
    );
    expect(template).to.include(
      "{% if let Some(refund_rejection_reason) = &item.refund_rejection_reason -%}",
    );
    expect(template).to.include('{{ refund_status_badge(item, "mobile") -}}');
    expect(template).to.include('{{ refund_status_badge(item, "desktop") -}}');
    expect(template).not.to.include("icon-info");
    expect(template).to.include(
      "relative inline-flex cursor-help rounded-full",
    );
    expect(template).to.include(
      "refund-rejection-reason-{{ item.event.event_id }}-{{ status_instance }}",
    );
    expect(template).to.include(
      'aria-describedby="{{ refund_rejection_tooltip_id }}"',
    );
    expect(template).to.include("dashboard::tooltip_panel(");
    expect(template).to.include('title = "Refund request"');
    expect(template).to.include(
      "-end-1 -top-1 size-2.5 rounded-full border-2 border-white bg-red-800",
    );
    expect(template).to.include("group-hover/refund-reason:visible");
    expect(template).to.include("group-focus-within/refund-reason:visible");
    expect(template).to.include(
      '<span class="block font-semibold text-stone-500">Reason</span>',
    );
    expect(template).to.include(
      '<span class="mt-0.5 block whitespace-pre-wrap text-stone-900">{{ refund_rejection_reason }}</span>',
    );
    expect(template).not.to.include("refund_rejection_reason|safe");
  });

  it("renders active checkout recovery and cancellation actions", async () => {
    // Load the user events template before checking checkout actions.
    const template = normalizeWhitespace(await loadTemplate());

    // Active direct checkout rows can resume through a provider or the public event page.
    expect(template).to.include("{% else if item.can_cancel_checkout() -%}");
    expect(template).to.include(
      'href="/{{ item.event.community_name }}/group/{{ item.event.public_group_slug() }}/event/{{ item.event.slug }}"',
    );
    expect(template).to.include("<span>Continue to checkout</span>");

    // Cancellation uses the existing event checkout endpoint and refresh marker.
    expect(template).to.include(
      'id="cancel-checkout-{{ item.event.event_id }}"',
    );
    expect(template).to.include(
      'hx-delete="/{{ item.event.community_name }}/event/{{ item.event.event_id }}/checkout"',
    );
    expect(template).to.include('hx-swap="none"');
    expect(template).to.include("data-user-event-checkout-cancel");
    expect(template).to.include(
      'data-confirm-message="Are you sure you want to cancel this checkout? Your ticket hold will be released."',
    );
    expect(template).to.include(
      'data-success-message="Your checkout has been canceled and the ticket hold released."',
    );
    expect(template).to.include("<span>Cancel checkout</span>");
  });

  it("links eligible paid attendees to the event refund control", async () => {
    // Load the user events menu before checking paid-attendee actions.
    const template = normalizeWhitespace(await loadTemplate());

    // Upcoming paid rows expose a direct path to the public refund control.
    expect(template).to.include(
      "{% if item.has_paid_purchase && !item.event.is_past() -%}",
    );
    expect(template).to.include("data-user-event-refund-action");
    expect(template).to.include(
      'data-enrollment-url="/{{ item.event.community_name }}/event/{{ item.event.event_id }}/enrollment"',
    );
    expect(template).to.include("#refund-btn-main");
    expect(template).to.include("<span>Request refund</span>");
  });

  it("routes active event offers to the invitations dashboard", async () => {
    // Load the user events template before checking offer actions.
    const template = normalizeWhitespace(await loadTemplate());

    // Offer rows use explicit offer actions and checkout wording.
    expect(template).to.include("{% if item.has_active_offer() -%}");
    expect(template).to.include(
      "/dashboard/user?tab=invitations#event-offer-{{ admission_offer_id }}",
    );
    expect(template).to.include("<span>View event offer</span>");
    expect(template).to.include("<span>Continue to checkout</span>");
  });
});
