import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/attendees_list.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group attendees list template", () => {
  it("renders cancel attendance as a confirmed delete action for eligible attendees", async () => {
    // Load the attendees list template before checking cancel attendance markup.
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include('attendee.status == "confirmed"');
    expect(template).to.include('id="cancel-attendance-{{ attendee.user_id }}"');
    expect(template).to.include(
      'hx-delete="/dashboard/group/events/{{ event.event_id }}/attendees/{{ attendee.user_id }}/attendance"',
    );
    expect(template).to.include('hx-trigger="confirmed"');
    expect(template).to.include('hx-disabled-elt="this"');
    expect(template).to.include("data-confirm-action");
    expect(template).to.include('data-confirm-message="Are you sure you want to cancel this attendance?"');
    expect(template).to.include('data-success-message="Attendance canceled."');
    expect(template).to.include(
      'data-error-message="Something went wrong canceling this attendance. Please try again later."',
    );
  });

  it("keeps cancel attendance disabled for unsupported attendee states", async () => {
    // Load the attendees list template before checking disabled states.
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include("!self::is_paid_attendee(attendee.amount_minor)");
    expect(template).to.include("!event.canceled");
    expect(template).to.include("!event.is_past()");
    expect(template).to.include('title="Paid attendee attendance cannot be canceled from attendee actions."');
    expect(template).to.include('title="Canceled event attendance cannot be canceled."');
    expect(template).to.include('title="Past event attendance cannot be canceled."');
  });

  it("renders cancel invitation for manual question-pending invitations", async () => {
    // Load the attendees list template before checking invitation actions.
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include(
      'attendee.status == "registration-questions-pending") && attendee.name.is_none()',
    );
    expect(template).to.include(
      'attendee.status == "registration-questions-pending" && attendee.manually_invited',
    );
    expect(template).to.include('id="cancel-invitation-{{ attendee.user_id }}"');
    expect(template).to.include(
      'hx-put="/dashboard/group/events/{{ event.event_id }}/attendees/{{ attendee.user_id }}/invitation/cancel"',
    );
  });

  it("renders registration answers in the review modal layout", async () => {
    // Load the attendees list template before checking answers markup.
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include('aria-describedby="attendee-answers-subtitle"');
    expect(template).to.include('id="attendee-answers-subtitle"');
    expect(template).to.include('<ol class="space-y-3">');
    expect(template).to.include('<li class="rounded-md border border-stone-200 bg-white p-4">');
    expect(template).to.include("{{ loop.index }}");
    expect(template).to.include("No answer provided");
    expect(template).to.include("text-sm italic text-stone-500");
    expect(template).not.to.include(">Free text<");
    expect(template).not.to.include(">Single select<");
    expect(template).not.to.include(">Multi select<");
    expect(template).to.include(
      "question.is_option_selected(attendee.registration_answers.as_ref(), option.id)",
    );
  });
});
