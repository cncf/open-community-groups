import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/user/invitations_list.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard user invitations list template", () => {
  it("orders event group and community invitations", async () => {
    // Load the invitations template before checking section order.
    const template = normalizeWhitespace(await loadTemplate());
    const eventInvitations = template.indexOf("{# Event Invitations -#}");
    const groupInvitations = template.indexOf("{# Groups Invitations -#}");
    const communityInvitations = template.indexOf("{# Community Invitations -#}");

    // Verify the requested order and consistent secondary section spacing.
    expect(template).to.include('dashboard::page_title(title = "Event Invitations"');
    expect(eventInvitations).to.be.greaterThan(-1);
    expect(groupInvitations).to.be.greaterThan(eventInvitations);
    expect(communityInvitations).to.be.greaterThan(groupInvitations);
    expect(template.match(/mb-12/gu)).to.have.length(2);
    expect(template).to.include('{# Groups Invitations -#} <div>');
    expect(template).to.include('{# Community Invitations -#} <div>');
    expect(template).not.to.include("mb-10");
    expect(template).not.to.include('class="pt-12"');
    expect(template).to.not.include("border-t border-stone-900/10");
  });

  it("marks initially hidden offer dialogs as hidden for assistive technology", async () => {
    // Load the claim dialog before its delegated JavaScript initializes.
    const template = normalizeWhitespace(await loadTemplate());

    // The visual and accessible initial states remain synchronized.
    expect(template).to.include(
      'data-user-event-offer-dialog role="dialog" aria-modal="true" aria-hidden="true"',
    );
  });

  it("renders ticket offer details and exact claim deadlines", async () => {
    // Load the invitations template before checking offer details.
    const template = normalizeWhitespace(await loadTemplate());

    // Ticket offers expose their tier, price, source, deadline, and pricing warning.
    expect(template).to.include("{{ invitation.ticket_title }}");
    expect(template).to.include("{{ invitation.source_label() }}");
    expect(template).to.include("{% else if let Some(price_label) = invitation.price_label() -%}");
    expect(template).to.include("data-localized-currency");
    expect(template).to.include("group/event-offer-details relative inline-flex shrink-0");
    expect(template).to.include(
      'class="custom-badge border-stone-500 bg-stone-100 px-2.5 py-0.5 text-stone-700"',
    );
    expect(template).to.include(
      "event-offer-details-{{ invitation.admission_offer_id }}",
    );
    expect(template).to.include('aria-describedby="{{ event_offer_tooltip_id }}"');
    expect(template).to.include("dashboard::tooltip_panel(");
    expect(template).to.include('title = "Ticket offer"');
    expect(template).to.include("-end-1 -top-1 size-2.5 rounded-full border-2 border-white bg-stone-500");
    expect(template).to.include("group-hover/event-offer-details:visible");
    expect(template).to.include("group-focus-within/event-offer-details:visible");
    expect(template).to.include(
      '<span class="block font-semibold text-stone-500">Ticket type</span>',
    );
    expect(template).to.include(
      '<span class="mt-0.5 block text-stone-900">{{ invitation.ticket_title }}</span>',
    );
    expect(template).to.include('<span class="block font-semibold text-stone-500">Offer</span>');
    expect(template).to.include(
      '<span class="mt-0.5 block text-stone-900">{{ invitation.source_label() }}</span>',
    );
    expect(template).not.to.include("mt-1 text-xs font-semibold text-green-800");
    expect(template).to.include(
      '{{ invitation.expires_at.with_timezone(invitation.timezone).format("%b %-e, %Y at %-I:%M %p %Z") }}',
    );
    expect(template).to.include(
      "Your price is confirmed when you first claim the offer. If checkout has already started, retries keep that confirmed price.",
    );
    expect(template).to.include(
      'class="custom-badge border-green-800 bg-green-100 px-2.5 py-0.5 text-green-800"',
    );
    expect(template).to.include("{% if invitation.is_simple_rsvp %}Confirm by{% else %}Claim by{% endif %}");
  });

  it("renders claim decline resume and cancel checkout actions", async () => {
    // Load the invitations template before checking offer actions.
    const template = normalizeWhitespace(await loadTemplate());

    // Owned offers expose every supported lifecycle action.
    expect(template).to.include("data-user-event-offer-open");
    expect(template).to.include("data-actions-menu");
    expect(template).to.include('aria-label="Open offer actions for {{ invitation.event_name }}"');
    expect(template).to.include("icon-vertical-dots");
    expect(template).to.include(
      'class="dropdown absolute end-0 top-8 z-10 w-[230px] overflow-hidden rounded-lg border border-stone-200 bg-white py-1 shadow-lg"',
    );
    expect(template).to.include(
      "gap-2 px-3 py-2 text-left text-sm text-stone-700 transition-colors hover:bg-stone-50",
    );
    expect(template).to.include("<span>Claim offer</span>");
    expect(template).to.include("<span>Continue to checkout</span>");
    expect(template).to.include("data-user-event-offer-checkout-cancel");
    expect(template).to.include(
      'hx-put="/dashboard/user/invitations/event-offers/{{ invitation.admission_offer_id }}/decline"',
    );
    expect(template).to.include("<span>Decline offer</span>");
    expect(template).to.not.include('data-success-message="The offer has been declined."');
    expect(template).to.include('name="admission_offer_id"');
    expect(template).to.include('name="event_ticket_type_id"');
  });

  it("renders Open payment page for externally pending invitation checkouts", async () => {
    // Load the invitations template before checking external payment actions.
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include(
      "{% if let Some(external_payment) = &invitation.external_payment -%}",
    );
    expect(template).to.include('href="{{ external_payment.url }}"');
    expect(template).to.include('target="_blank"');
    expect(template).to.include('rel="noopener noreferrer"');
    expect(template).to.include("<span>Open payment page</span>");
    expect(template).to.include(
      "{% else if let Some(resume_checkout_url) = &invitation.resume_checkout_url -%}",
    );
  });

  it("collects registration answers in the offer claim modal", async () => {
    // Load the invitations template before checking question fields.
    const template = normalizeWhitespace(await loadTemplate());

    // Claim-time questions share the established questionnaire macro and answer payload.
    expect(template).to.include("{{ question_answers::fields(questions = invitation.registration_questions,");
    expect(template).to.include("answers = invitation.registration_answers.as_ref()");
    expect(template).to.include("data-user-event-offer-answers");
    expect(template).to.include('name="registration_answers"');
  });
});
