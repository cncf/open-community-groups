import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/user/events_list.html");

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
    expect(template).to.include('id="cancel-attendance-{{ item.event.event_id }}"');
    expect(template).to.include("{% if item.can_cancel_attendance() -%}");
    expect(template).to.include(
      'hx-delete="/dashboard/user/events/{{ item.event.community_name }}/{{ item.event.event_id }}/attendance"',
    );
    expect(template).to.include('hx-trigger="confirmed"');
    expect(template).to.include('hx-disabled-elt="this"');
    expect(template).to.include("data-confirm-action");
    expect(template).to.include('data-confirm-message="Are you sure you want to cancel your attendance?"');
    expect(template).to.include('data-success-message="You have successfully canceled your attendance."');
    expect(template).to.include(
      'data-error-message="Something went wrong canceling your attendance. Please try again later."',
    );
  });

  it("keeps cancel attendance visible but disabled when cancellation is unavailable", async () => {
    // Load the user events template before checking disabled cancellation.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify unavailable cancellations stay visible and disabled.
    expect(template).to.include("disabled");
    expect(template).to.include('title="This attendance cannot be canceled from My Events."');
    expect(template).to.include('<span class="sr-only">Actions</span>');
    expect(template).to.include('aria-label="Open event actions"');
    expect(template).to.include("data-actions-menu");
  });

  it("renders pending attendance status and typed roles as badges", async () => {
    // Load the user events template before checking pending badges.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify pending attendance and active offer states are visually distinct.
    expect(template).to.include(
      "{% if let Some(enrollment_status_label) = item.enrollment_status_label() -%}",
    );
    expect(template).to.include(
      '{{ badges::status_badge(label = enrollment_status_label, extra_styles = Some("uppercase")) -}}',
    );
    expect(template).to.include(
      '{{ badges::common_badge(content = role.label() , extra_styles = Some("px-2.5 py-0.5")) -}}',
    );
    expect(template).to.include('{% if role.label() == "Event offer" -%}');
    expect(template).to.include(
      '{{ badges::common_badge(content = role.label() , extra_styles = Some("border-yellow-800 bg-yellow-100 px-2.5 py-0.5 font-semibold text-yellow-800")) -}}',
    );
    expect(template).to.include(">Status / role</th>");
  });

  it("renders rejected refund status and escaped wrapping reason content", async () => {
    // Load the user events template before checking rejected refund feedback.
    const template = normalizeWhitespace(await loadTemplate());

    // Rejected rows always get a danger badge and only render a present reason as normal text.
    expect(template).to.include(
      "item.refund_request_status == Some(crate::types::payments::EventRefundRequestStatus::Rejected)",
    );
    expect(template).to.include(
      '{{ badges::invitation_badge(label = "Refund rejected", tone = "danger", with_border = true) -}}',
    );
    expect(template).to.include(
      "{% if let Some(refund_rejection_reason) = &item.refund_rejection_reason -%}",
    );
    expect(template).to.include('<span class="font-medium">Reason:</span>');
    expect(template).to.include('<span class="whitespace-pre-wrap">{{ refund_rejection_reason }}</span>');
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
    expect(template).to.include('id="cancel-checkout-{{ item.event.event_id }}"');
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
    expect(template).to.include("{% if item.has_paid_purchase && !item.event.is_past() -%}");
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
    expect(template).to.include("/dashboard/user?tab=invitations#event-offer-{{ admission_offer_id }}");
    expect(template).to.include("<span>View event offer</span>");
    expect(template).to.include("<span>Continue to checkout</span>");
  });
});
