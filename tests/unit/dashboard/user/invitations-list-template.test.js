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
    expect(template).to.include('{# Groups Invitations -#} <div class="pt-12">');
    expect(template).to.include('{# Community Invitations -#} <div class="pt-12">');
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
    expect(template).to.include("{% if !invitation.is_simple_rsvp -%}");
    expect(template).to.include("{% if let Some(price_label) = invitation.price_label() -%}");
    expect(template).to.include("data-localized-currency");
    expect(template).to.include(
      '{{ invitation.expires_at.with_timezone(invitation.timezone).format("%b %-e, %Y at %-I:%M %p %Z") }}',
    );
    expect(template).to.include(
      "Your price is confirmed when you first claim the offer. If checkout has already started, retries keep that confirmed price.",
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
