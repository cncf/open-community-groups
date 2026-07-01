import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch(
    "/ocg-server/templates/dashboard/group/attendees_list.html",
  );

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

const sliceTemplateSection = (template, startToken, endToken) => {
  const start = template.indexOf(startToken);
  const end = template.indexOf(endToken, start);

  expect(start).to.be.greaterThan(-1);
  expect(end).to.be.greaterThan(start);

  return template.slice(start, end);
};

describe("dashboard group attendees list template", () => {
  it("renders attendee identity cells as profile modal triggers", async () => {
    // Load the attendees list template before checking profile trigger markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the attendee identity area uses the shared profile trigger macro.
    expect(template).to.include(
      "dashboard::user_profile_modal_trigger(attendee.user, self::user_initials(attendee.user.name.as_deref() , attendee.user.username.as_str()))",
    );
    expect(template).to.include('attendee.status == "invitation-pending"');
    expect(template).to.include("attendee.email");
  });

  it("renders cancel attendance as a confirmed delete action for eligible attendees", async () => {
    // Load the attendees list template before checking cancel attendance markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify eligible attendees get a confirmed cancel action.
    expect(template).to.include('attendee.status == "confirmed"');
    expect(template).to.include(
      'id="cancel-attendance-{{ attendee.user.user_id }}"',
    );
    expect(template).to.include(
      'hx-delete="/dashboard/group/events/{{ event.event_id }}/attendees/{{ attendee.user.user_id }}/attendance"',
    );
    expect(template).to.include('hx-trigger="confirmed"');
    expect(template).to.include('hx-disabled-elt="this"');
    expect(template).to.include("data-confirm-action");
    expect(template).to.include(
      'data-confirm-message="Are you sure you want to cancel this attendance?"',
    );
    expect(template).to.include('data-success-message="Attendance canceled."');
    expect(template).to.include(
      'data-error-message="Something went wrong canceling this attendance. Please try again later."',
    );
  });

  it("keeps cancel attendance disabled for unsupported attendee states", async () => {
    // Load the attendees list template before checking disabled states.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify keeps cancel attendance disabled for unsupported attendee states.
    expect(template).to.include(
      "!self::is_paid_attendee(attendee.amount_minor)",
    );
    expect(template).to.include("!event.canceled");
    expect(template).to.include("!event.is_past()");
    expect(template).to.include(
      'title="Paid attendee attendance cannot be canceled from attendee actions."',
    );
    expect(template).to.include(
      'title="Canceled event attendance cannot be canceled."',
    );
    expect(template).to.include(
      'title="Past event attendance cannot be canceled."',
    );
  });

  it("renders cancel invitation for manual question-pending invitations", async () => {
    // Load the attendees list template before checking invitation actions.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify renders cancel invitation for manual question-pending invitations.
    expect(template).to.include(
      'attendee.status == "registration-questions-pending") && attendee.user.name.is_none()',
    );
    expect(template).to.include(
      'attendee.status == "registration-questions-pending" && attendee.manually_invited',
    );
    expect(template).to.include(
      'id="cancel-invitation-{{ attendee.user.user_id }}"',
    );
    expect(template).to.include(
      'hx-put="/dashboard/group/events/{{ event.event_id }}/attendees/{{ attendee.user.user_id }}/invitation/cancel"',
    );
  });

  it("uses all-attendee eligibility for the attendee email modal entrypoint", async () => {
    // Load the attendees list template before checking notification entrypoint guards.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the primary entrypoint uses all-attendee eligibility.
    expect(template).to.include('id="attendee-email-actions-button"');
    expect(template).to.include("data-attendee-email-actions-dropdown");
    expect(template).to.include("all_attendees_email_recipient_total == 0");
    expect(template).to.include(
      'data-notification-recipient-total="{{ all_attendees_email_recipient_total }}"',
    );
    expect(template).to.include('data-notification-scope="all"');
    expect(template).to.include("All eligible attendees");
    expect(template).to.include(
      "No attendees with verified email addresses and email notifications enabled.",
    );
    expect(template).not.to.include(
      "No confirmed attendees with verified email addresses and email notifications enabled.",
    );
  });

  it("groups attendee QR, invite, and CSV downloads in the actions menu", async () => {
    const template = normalizeWhitespace(await loadTemplate());
    const actionsMenu = sliceTemplateSection(
      template,
      'id="attendee-actions-menu"',
      "{# End header actions -#}",
    );

    expect(actionsMenu).to.include('id="open-event-qr-code-modal"');
    expect(actionsMenu).to.include("icon-qr-code");
    expect(actionsMenu).to.include("Show check-in QR code");
    expect(actionsMenu).to.include('id="open-attendee-invitation-modal"');
    expect(actionsMenu).to.include("Invite attendee");
    expect(actionsMenu).to.include("border-t border-stone-100");
    expect(actionsMenu).to.include("Attendees list CSV");
    expect(actionsMenu).to.include("Attendees list CSV (including answers)");
    expect(actionsMenu).not.to.include("> Actions <");
    expect(actionsMenu).not.to.include("> Exports <");
  });

  it("uses the shared attendee search convention for table filtering", async () => {
    // Load the attendees list template before checking search markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify attendee search follows the existing dashboard HTMX pattern.
    expect(template).to.include('id="attendees-search-form"');
    expect(template).to.include('hx-trigger="change, submit"');
    expect(template).to.include('hx-target="#attendees-content"');
    expect(template).to.include(
      '<label for="search_attendees" class="sr-only">Search attendees</label>',
    );
    expect(template).to.include('name="ts_query"');
    expect(template).to.include('placeholder="Search attendees"');
    expect(template).to.include('aria-label="Clear attendee search"');
    expect(template).to.include(
      "dashboard/placeholders/group_attendees_no_results.html",
    );
  });

  it("renders attendee table sorting and filter controls", async () => {
    // Load the attendees list template before checking table controls.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify attendee filters preserve current table state.
    expect(template).to.include('name="checked_in" value="{{ checked_in }}"');
    expect(template).to.include('name="event_ticket_type_ids[]"');
    expect(template).to.include('name="sort" value="{{ sort }}"');
    expect(template).to.include('name="title" value="{{ title }}"');
    expect(template).to.include('name="ts_query" value="{{ ts_query }}"');
    expect(template).to.include(
      'dashboard::table_sort_button(label = "Attendee", sort_value = "name-desc"',
    );
    expect(template).to.include(
      'dashboard::table_sort_button(label = "Attendee", sort_value = "name-asc"',
    );
    expect(template).to.include(
      'dashboard::table_sort_button(label = "RSVP Date", sort_value = "created-at-desc"',
    );
    expect(template).to.include(
      'dashboard::table_sort_button(label = "RSVP Date", sort_value = "created-at-asc"',
    );
    expect(template).to.include('class="px-3 xl:px-5 py-1.5"');
    expect(template).to.include('class="hidden px-3 xl:px-5 py-1.5 w-12"');
    expect(template).to.include('class="hidden 2xl:table-cell px-3 xl:px-5 py-1.5"');
    expect(template).to.include(
      'class="hidden 2xl:table-cell px-3 xl:px-5 py-1.5 w-40"',
    );
    expect(template).to.include(
      'class="hidden xl:table-cell px-3 xl:px-5 py-1.5 w-48"',
    );
    expect(template).to.include('class="px-3 xl:px-5 py-1.5 w-30"');
    expect(template).to.include('class="px-3 xl:px-5 py-1.5 w-[72px]"');
    expect(template).to.include("flex items-center gap-2");
    expect(template).to.include(
      'dashboard::table_filter_menu(id = "attendees-name-filter", label = "Attendee"',
    );
    expect(template).to.include(
      'dashboard::table_filter_menu(id = "attendees-position-filter", label = "Position"',
    );
    expect(template).to.include(
      'dashboard::table_filter_menu(id = "attendees-ticket-filter", label = "Ticket type"',
    );
    expect(template).to.include(
      'dashboard::table_filter_menu(id = "attendees-check-in-filter", label = "Checked In"',
    );
    expect(template).to.include('name="title" value="present"');
    expect(template).to.include('name="title" value="missing"');
    expect(template).to.include('name="checked_in" value="true"');
    expect(template).to.include('name="checked_in" value="false"');
    expect(template).to.include("Sort: Name Z-A");
    expect(template).to.include("Sort: Oldest RSVP");
    expect(template).to.include("Ticket type");
  });

  it("integrates selected attendee email sends with the attendees table", async () => {
    // Load the attendees list template before checking table selection markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify selected-recipient sends are table-integrated.
    expect(template).to.include("Choose attendees");
    expect(template).to.include("data-attendee-email-selection-start");
    expect(template).to.include("data-attendee-email-selection-bar");
    expect(template).to.include("data-attendee-email-selection-count");
    expect(template).to.include(
      "<span data-attendee-email-selection-count>0</span>",
    );
    expect(template).to.include(
      "<span data-attendee-email-selection-label>attendees selected</span>",
    );
    expect(template).not.to.include(
      "Only attendees eligible for optional email notifications can be selected.",
    );
    expect(template).to.include("data-attendee-email-selection-column");
    expect(template).to.include("data-attendee-email-selection-checkbox");
    expect(template).to.include('class="checkbox-primary"');
    expect(template).to.include("attendee.can_receive_attendee_email");
    expect(template).to.include(
      'class="hidden xl:table-cell px-3 xl:px-5 py-1.5 w-48"',
    );
    expect(template).to.include(
      'class="hidden xl:table-cell px-3 xl:px-5 py-4 align-middle"',
    );
    expect(template).to.include('class="btn-primary-outline btn-mini h-7!"');
    expect(template).to.include('class="btn-primary btn-mini h-7!"');
    expect(template).to.include("Continue");
    expect(template).to.include('data-notification-scope="selected"');
    expect(template).to.include('id="attendee-notification-recipient-scope"');
    expect(template).to.include('id="attendee-notification-selected-fields"');
    expect(template).not.to.include("attendee-notification-recipient-search");
    expect(template).not.to.include("data-recipients-url");
  });

  it("renders registration answers in the review modal layout", async () => {
    // Load the attendees list template before checking answers markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify renders registration answers in the review modal layout.
    expect(template).to.include('aria-describedby="attendee-answers-subtitle"');
    expect(template).to.include('id="attendee-answers-subtitle"');
    expect(template).to.include('<ol class="space-y-3">');
    expect(template).to.include(
      '<li class="rounded-md border border-stone-200 bg-white p-4">',
    );
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
