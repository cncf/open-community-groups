import { expect } from "@open-wc/testing";

const loadTemplate = async (templatePath = "/ocg-server/templates/dashboard/group/attendees_list.html") => {
  const response = await fetch(templatePath);

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
  it("groups enrollment views and exact statuses in one selector", async () => {
    // Load the attendees list template before checking enrollment filters.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify aggregate views and exact statuses are visually separated by native optgroups.
    expect(template).to.include('for="attendees-enrollment-status"');
    expect(template).to.include('id="attendees-enrollment-status"');
    expect(template).to.include('name="status"');
    expect(template).not.to.include('name="attendance"');
    expect(template).to.include('<optgroup label="Views">');
    expect(template).to.include('<optgroup label="Current status">');
    expect(template).to.include('<optgroup label="Historical status">');

    for (const [value, label] of [
      ["current", "Current enrollments"],
      ["history", "Enrollment history"],
      ["all", "All enrollments"],
      ["confirmed", "Confirmed"],
      ["checkout-pending", "Checkout pending"],
      ["invitation-pending", "Invitation pending"],
      ["registration-pending", "Registration pending"],
      ["attendance-canceled", "Attendance canceled"],
      ["invitation-canceled", "Invitation canceled"],
      ["invitation-declined", "Invitation declined"],
      ["invitation-expired", "Invitation expired"],
    ]) {
      expect(template).to.include(`value="${value}"`);
      expect(template).to.include(`>${label}</option>`);
    }
  });

  it("uses filter-aware empty states", async () => {
    // Load the list and filtered-empty placeholder templates.
    const template = normalizeWhitespace(await loadTemplate());
    const placeholder = normalizeWhitespace(
      await loadTemplate("/ocg-server/templates/dashboard/placeholders/group_attendees_no_results.html"),
    );
    const emptyState = sliceTemplateSection(template, "{# Empty state -#}", "{# End empty state -#}");

    // Verify every table filter selects useful filtered-empty guidance.
    expect(emptyState).to.include(
      "event.canceled && status != crate::templates::dashboard::group::attendees::AttendeeEnrollmentStatusFilter::All",
    );
    expect(emptyState).to.include(
      "!event.canceled && status != crate::templates::dashboard::group::attendees::AttendeeEnrollmentStatusFilter::Current",
    );
    expect(emptyState).to.include("checked_in.is_some()");
    expect(emptyState).to.include("event_ticket_type_ids.is_some()");
    expect(emptyState).to.include("title.is_some()");
    expect(emptyState).to.include("has_active_attendee_filters");
    expect(placeholder).to.include("No attendees found matching your filters.");
    expect(placeholder).to.include("Try adjusting your search or filters");
  });

  it("keeps canceled attendee history and accessible state aligned", async () => {
    // Load the attendee row before checking canceled attendance details.
    const template = normalizeWhitespace(await loadTemplate());
    const enrollmentDate = sliceTemplateSection(
      template,
      "{# Enrollment Date -#}",
      "{# End enrollment date -#}",
    );
    const checkInToggle = sliceTemplateSection(
      template,
      "{# Checked In Toggle -#}",
      "{# End checked in toggle -#}",
    );

    // Verify historical enrollments retain their date and accurate check-in label.
    expect(enrollmentDate).to.include('attendee.created_at.format("%b %d, %Y")');
    expect(checkInToggle).to.include("Canceled attendance cannot be checked in");
    expect(checkInToggle).to.include("Pending checkout cannot be checked in");
    expect(checkInToggle).to.include("Canceled invitation cannot be checked in");
    expect(checkInToggle).to.include("Declined invitation cannot be checked in");
    expect(checkInToggle).to.include("Expired invitation cannot be checked in");
    expect(checkInToggle).to.include("Pending invitation cannot be checked in");
    expect(checkInToggle).to.include("Pending registration cannot be checked in");
    expect(checkInToggle).to.include("Your role cannot manage check-in");
  });

  it("shows refund progress and exposes retryable work", async () => {
    // Load the attendees list template before checking refund status markup.
    const template = normalizeWhitespace(await loadTemplate());
    const attendeeStatus = sliceTemplateSection(
      template,
      "{# Attendee status badge and active offer deadline. #}",
      "{# End attendee status. #}",
    );
    const ticketType = sliceTemplateSection(template, "{# Ticket type -#}", "{# End ticket type -#}");

    // Verify refund status labels use the shared status badge outside Ticket type.
    expect(attendeeStatus).to.include('badges::status_badge(label = "Waiting for checkout")');
    expect(attendeeStatus).to.include('badges::status_badge(label = "Refund queued")');
    expect(attendeeStatus).to.include('badges::status_badge(label = "Refund processing")');
    expect(attendeeStatus).to.include('badges::status_badge(label = "Refund needs retry", canceled = true)');
    expect(attendeeStatus).to.include('badges::status_badge(label = "Recovery required", canceled = true)');
    expect(attendeeStatus).to.include('badges::status_badge(label = "Refunded", published = true)');
    expect(attendeeStatus).to.include('badges::status_badge(label = "Refund rejected", canceled = true)');
    expect(ticketType).to.not.include("Refund rejected");

    // Verify retryable refund work remains available from attendee actions.
    expect(template).to.include('id="retry-refund-{{ attendee.user.user_id }}"');
    expect(template).to.include(
      'hx-put="/dashboard/group/refunds/{{ attendee.event_purchase_id.unwrap() }}/retry"',
    );
    expect(template).to.include("data-actions-menu");
  });

  it("labels completed paid offers as claimed tickets", async () => {
    // Load the attendee status badges before checking completed offer copy.
    const template = normalizeWhitespace(await loadTemplate());

    // Completed offers and claimed paid invitations take precedence over invitation copy.
    expect(template).to.include("EventAdmissionOfferStatus::Completed");
    expect(template).to.include(
      "AttendeeEnrollmentStatus::Confirmed && attendee.manually_invited && self::is_paid_attendee(attendee.amount_minor)",
    );
    expect(template).to.include('badges::status_badge(label = "Ticket claimed", published = true)');
  });

  it("shows confirmed attendees as active when no other status applies", async () => {
    // Load the attendee status macro before checking its confirmed fallback.
    const template = normalizeWhitespace(await loadTemplate());
    const attendeeStatus = sliceTemplateSection(
      template,
      "{# Attendee status badge and active offer deadline. #}",
      "{# End attendee status. #}",
    );

    // Verify confirmed attendees receive the final green status fallback.
    expect(attendeeStatus).to.include("AttendeeEnrollmentStatus::Confirmed -%}");
    expect(attendeeStatus).to.include('badges::status_badge(label = "Active", published = true)');
    expect(attendeeStatus.indexOf("Registration pending")).to.be.lessThan(
      attendeeStatus.indexOf('label = "Active"'),
    );
  });

  it("displays ticket names above their prices", async () => {
    // Load the ticket type cell before checking its two-line layout.
    const template = normalizeWhitespace(await loadTemplate());
    const ticketType = sliceTemplateSection(template, "{# Ticket type -#}", "{# End ticket type -#}");

    // Verify ticket names truncate above prices styled like attendee usernames.
    expect(ticketType).to.include('class="max-w-full truncate font-medium text-stone-900"');
    expect(ticketType).to.include('class="text-xs text-stone-600 truncate"');
    expect(ticketType).to.include("<span data-localized-currency>{{ amount_label }}</span>");
    expect(ticketType).to.not.include("(<span data-localized-currency>");
  });

  it("explains when invitations have no assignable ticket type", async () => {
    // Load the invitation modal before checking its ticket empty state.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify organizers receive a recovery path when the select has no options.
    expect(template).to.include("data-attendee-invitation-ticket-empty");
    expect(template).to.include("ticket_type.active && !ticket_type.sold_out");
    expect(template).to.include(
      "No ticket types can be assigned. Add seats or activate a ticket type with a current price before sending an invitation.",
    );
  });

  it("collects an optional review note before rejecting a refund", async () => {
    // Load the attendee refund rejection action and modal contracts.
    const template = normalizeWhitespace(await loadTemplate());
    const rejectAction = sliceTemplateSection(
      template,
      'id="reject-refund-{{ attendee.user.user_id }}"',
      "</button>",
    );

    // Verify rejection opens the note form instead of submitting directly.
    expect(rejectAction).to.include("data-attendee-refund-reject-open");
    expect(rejectAction).to.include(
      'data-refund-reject-url="/dashboard/group/refunds/{{ attendee.event_purchase_id.unwrap() }}/reject"',
    );
    expect(rejectAction).not.to.include("hx-put");
    expect(rejectAction).not.to.include("data-confirm-action");
    expect(template).to.include("dashboard::refund_review_modal");
    expect(template).to.include('id_prefix = "attendee-refund-reject"');
    expect(template).to.include('review_note_id = "attendee-refund-review-note"');
    expect(template).to.include("review_note_required = true");
  });

  it("collects an optional review note before approving a refund", async () => {
    // Load the attendee refund approval action and modal contracts.
    const template = normalizeWhitespace(await loadTemplate());
    const approveAction = sliceTemplateSection(
      template,
      'id="approve-refund-{{ attendee.user.user_id }}"',
      "</button>",
    );

    // Verify approval opens the note form instead of submitting directly.
    expect(approveAction).to.include("data-attendee-refund-approve-open");
    expect(approveAction).to.include(
      'data-refund-approve-url="/dashboard/group/refunds/{{ attendee.event_purchase_id.unwrap() }}/approve"',
    );
    expect(approveAction).not.to.include("hx-put");
    expect(template).to.include('id_prefix = "attendee-refund-approve"');
    expect(template).to.include('review_note_id = "attendee-refund-approve-review-note"');
    expect(template).not.to.include('id="attendee-refund-modal"');
    expect(template).not.to.include("data-refund-review-trigger");
  });

  it("renders attendee identity cells as profile modal triggers", async () => {
    // Load the attendees list template before checking profile trigger markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the attendee identity area uses the shared profile trigger macro.
    expect(template).to.include(
      "dashboard::user_profile_modal_trigger(attendee.user, self::user_initials(attendee.user.name.as_deref() , attendee.user.username.as_str()))",
    );
    expect(template).to.include("AttendeeEnrollmentStatus::InvitationPending");
    expect(template).to.include("attendee.email");
  });

  it("renders cancel attendance as a confirmed delete action for eligible attendees", async () => {
    // Load the attendees list template before checking cancel attendance markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify eligible attendees get a confirmed cancel action.
    expect(template).to.include("AttendeeEnrollmentStatus::Confirmed");
    expect(template).to.include('id="cancel-attendance-{{ attendee.user.user_id }}"');
    expect(template).to.include(
      'hx-delete="/dashboard/group/events/{{ event.event_id }}/attendees/{{ attendee.user.user_id }}/attendance"',
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

    // Verify keeps cancel attendance disabled for unsupported attendee states.
    expect(template).to.include("!self::is_paid_attendee(attendee.amount_minor)");
    expect(template).to.include("!event.canceled");
    expect(template).to.include("!event.is_past()");
    expect(template).to.include('title="Paid attendee attendance cannot be canceled from attendee actions."');
    expect(template).to.include('title="Canceled event attendance cannot be canceled."');
    expect(template).to.include('title="Past event attendance cannot be canceled."');
  });

  it("renders exact offer cancellation for pending invitations", async () => {
    // Load the attendees list template before checking invitation actions.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify manual invitations cancel the exact admission offer.
    expect(template).to.include("AttendeeEnrollmentStatus::InvitationPending");
    expect(template).to.include("AttendeeEnrollmentStatus::RegistrationPending && attendee.manually_invited");
    expect(template).to.include("{% if let Some(admission_offer_id) = attendee.admission_offer_id -%}");
    expect(template).to.include('id="cancel-admission-offer-{{ admission_offer_id }}"');
    expect(template).to.include('hx-put="/dashboard/group/admission-offers/{{ admission_offer_id }}/cancel"');
    expect(template).not.to.include("/invitation/cancel");
  });

  it("renders organizer invitation tiers, deadlines, and state-specific actions", async () => {
    // Load the attendees list template before checking organizer invitation states.
    const template = normalizeWhitespace(await loadTemplate());
    const attendeeCell = sliceTemplateSection(template, "{# Attendee -#}", "{# End attendee -#}");

    // Verify invitations always use the ticket type select contract.
    expect(template).not.to.include("{% if ticket_types.len() == 1 -%}");
    expect(template).to.include('id="attendee-invitation-ticket-type"');
    expect(template).to.include('name="event_ticket_type_id"');
    expect(template).to.include("{% if ticket_types.len() == 1 %}selected{% endif %}");
    expect(template).to.include(
      "ticket_type.availability == crate::types::payments::EventTicketTypeAvailability::InvitationOnly",
    );
    expect(template).to.include("(Invitation only)");
    expect(template).to.include("(Public)");

    // Verify offer states use consistent badges in the dedicated status column.
    expect(template).to.include('badges::status_badge(label = "Offer pending")');
    expect(template).to.include('badges::status_badge(label = "Checkout pending")');
    expect(template).to.include("{{ attendee_status(attendee, event) -}}");
    expect(template).to.not.include("Awaiting claim");
    expect(template).to.not.include("Checkout in progress");
    expect(template).to.not.include("badges::invitation_badge");

    // Verify offer deadlines are available from an info tooltip on hover and focus.
    expect(template).to.include('role="tooltip"');
    expect(template).to.include("icon-info");
    expect(template).to.include('aria-label="{% if attendee.admission_offer_status');
    expect(template).to.include("group-hover/deadline-tooltip:visible");
    expect(template).to.include("group-focus-within/deadline-tooltip:visible");
    expect(attendeeCell.indexOf("{% endcall -%}")).to.be.lessThan(
      attendeeCell.indexOf("{{ attendee_status(attendee, event) -}}"),
    );
    expect(template).to.include(
      'offer_expires_at.with_timezone(event.timezone).format("%b %d, %Y at %I:%M %p %Z")',
    );
    expect(template).to.include(
      "attendee.admission_offer_status == Some(crate::types::event::EventAdmissionOfferStatus::Pending)",
    );
    expect(template).to.include(
      "attendee.admission_offer_status == Some(crate::types::event::EventAdmissionOfferStatus::CheckoutPending)",
    );

    // Verify only expired organizer invitations expose reissue.
    expect(template).to.include('badges::status_badge(label = "Offer expired", canceled = true)');
    expect(template).to.include("Reissue invitation");
    expect(template).to.include('name="email" value="{{ attendee.email }}"');
    expect(template).to.include(
      "attendee.admission_offer_status == Some(crate::types::event::EventAdmissionOfferStatus::Expired)",
    );
    expect(template).to.not.include("Waitlist offer reissue");
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
    expect(actionsMenu).to.include("{% if !registration_questions.is_empty() -%}");
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
    expect(template).to.include('<label for="search_attendees" class="sr-only">Search attendees</label>');
    expect(template).to.include('name="ts_query"');
    expect(template).to.include('placeholder="Search attendees"');
    expect(template).to.include('aria-label="Clear attendee search"');
    expect(template).to.include("flex flex-col gap-6 2xl:flex-row 2xl:items-start 2xl:justify-between");
    expect(template).to.include("flex-wrap items-center justify-start gap-6");
    expect(template).to.include("dashboard/placeholders/group_attendees_no_results.html");
  });

  it("renders attendee sort select and table filter controls", async () => {
    // Load the attendees list template before checking table controls.
    const template = normalizeWhitespace(await loadTemplate());
    const tableHeader = sliceTemplateSection(template, "{# Table header -#}", "{# End table header -#}");
    const attendeeRow = sliceTemplateSection(template, "{# Attendee row -#}", "{# End attendee row -#}");

    // Verify attendee filters preserve current table state.
    expect(template).to.include('name="checked_in" value="{{ checked_in }}"');
    expect(template).to.include('name="event_ticket_type_ids[]"');
    expect(template).to.include('name="sort" value="{{ sort }}"');
    expect(template).to.include('name="title" value="{{ title }}"');
    expect(template).to.include('name="ts_query" value="{{ ts_query }}"');
    expect(template).to.include('<label for="attendees-sort"');
    expect(template).to.include('id="attendees-sort"');
    expect(template).to.include('name="sort"');
    expect(template).to.include('hx-trigger="change"');
    expect(template).to.include("2xl:w-auto");
    expect(template).to.include("2xl:self-end");
    expect(template).to.include("Attendee ↑");
    expect(template).to.include("Attendee ↓");
    expect(template).to.include("Enrollment Date ↑");
    expect(template).to.include("Enrollment Date ↓");
    expect(template).to.include('<option value="name-asc"');
    expect(template).to.include('<option value="name-desc"');
    expect(template).to.include('<option value="created-at-asc"');
    expect(template).to.include('<option value="created-at-desc"');
    expect(template).to.not.include("dashboard::table_sort_menu");
    expect(template).to.not.include("dashboard::table_sort_option_button");
    expect(template).to.not.include("dashboard::table_sort_control");
    expect(template).to.include('class="px-3 xl:px-5 py-1.5"');
    expect(template).to.include('class="hidden px-3 xl:px-5 py-1.5 w-12"');
    expect(template).to.include('class="hidden 2xl:table-cell px-3 xl:px-5 py-1.5"');
    expect(template).to.include('class="hidden 2xl:table-cell px-3 xl:px-5 py-1.5 w-40"');
    expect(template).to.include('class="hidden xl:table-cell px-3 xl:px-5 py-1.5 w-44"');
    expect(template).to.include('class="hidden xl:table-cell px-3 xl:px-5 py-1.5 w-48"');
    expect(template).to.include('class="px-3 xl:px-5 py-1.5 w-30"');
    expect(template).to.include('class="px-3 xl:px-5 py-1.5 w-[72px]"');
    expect(template).to.include('<span class="whitespace-nowrap">Attendee</span>');
    expect(template).to.include('<span class="whitespace-nowrap">Enrollment Date</span>');
    expect(template).to.include(
      'dashboard::table_filter_menu(id = "attendees-position-filter", label = "Position"',
    );
    expect(template).to.include(
      'dashboard::table_filter_menu(id = "attendees-ticket-filter", label = "Ticket type"',
    );
    expect(template).to.include(
      'dashboard::table_filter_menu(id = "attendees-check-in-filter", label = "Checked In", is_active = checked_in.is_some(), extra_classes = "float-right", dropdown_classes = "end-0")',
    );
    expect(template).to.include(
      'dashboard::table_filter_option_button(label = "All", name = "title", value = "", is_active = title.is_none() , is_clear_option = true)',
    );
    expect(template).to.include(
      'dashboard::table_filter_option_button(label = "Present", name = "title", value = "present"',
    );
    expect(template).to.include(
      'dashboard::table_filter_option_button(label = "Missing", name = "title", value = "missing"',
    );
    expect(template).to.include(
      'dashboard::table_filter_option_button(label = "All attendees", name = "checked_in", value = "", is_active = checked_in.is_none() , is_clear_option = true)',
    );
    expect(template).to.include(
      'dashboard::table_filter_option_button(label = "Checked in", name = "checked_in", value = "true"',
    );
    expect(template).to.include(
      'dashboard::table_filter_option_button(label = "Not checked in", name = "checked_in", value = "false"',
    );
    expect(template).to.include("Reset all");
    expect(template).to.include('dashboard::active_table_filter_badge("Checked In", "Yes")');
    expect(template).to.include('dashboard::active_table_filter_badge("Checked In", "No")');
    expect(template).to.include('dashboard::active_table_filter_badge("Position", "Present")');
    expect(template).to.include('dashboard::active_table_filter_badge("Position", "Missing")');
    expect(template).to.include('dashboard::active_table_filter_badge("Ticket type", "Selected")');
    expect(template).to.not.include('dashboard::active_table_filter_badge("Sort"');
    expect(template).to.not.include('id = "attendees-name-filter"');
    expect(template).to.include("Ticket type");
    expect(tableHeader.indexOf("Status")).to.be.lessThan(tableHeader.indexOf("Ticket type"));
    expect(tableHeader.indexOf("Ticket type")).to.be.lessThan(tableHeader.indexOf("Enrollment Date"));
    expect(attendeeRow.indexOf("{# Status -#}")).to.be.lessThan(attendeeRow.indexOf("{# Ticket type -#}"));
    expect(attendeeRow.indexOf("{# Ticket type -#}")).to.be.lessThan(
      attendeeRow.indexOf("{# Enrollment Date -#}"),
    );
  });

  it("integrates selected attendee email sends with the attendees table", async () => {
    // Load the attendees list template before checking table selection markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify selected-recipient sends are table-integrated.
    expect(template).to.include("Choose attendees");
    expect(template).to.include("data-attendee-email-selection-start");
    expect(template).to.include("data-attendee-email-selection-bar");
    expect(template).to.include("data-attendee-email-selection-count");
    expect(template).to.include("<span data-attendee-email-selection-count>0</span>");
    expect(template).to.include("<span data-attendee-email-selection-label>attendees selected</span>");
    expect(template).not.to.include(
      "Only attendees eligible for optional email notifications can be selected.",
    );
    expect(template).to.include("data-attendee-email-selection-column");
    expect(template).to.include("data-attendee-email-selection-checkbox");
    expect(template).to.include('class="checkbox-primary"');
    expect(template).to.include("attendee.can_receive_attendee_email");
    expect(template).to.include('class="hidden xl:table-cell px-3 xl:px-5 py-1.5 w-48"');
    expect(template).to.include('class="hidden xl:table-cell px-3 xl:px-5 py-4 align-middle"');
    expect(template).to.include('class="btn-primary-outline btn-mini h-7!"');
    expect(template).to.include('class="btn-primary btn-mini h-7!"');
    expect(template).to.include("Continue");
    expect(template).to.include('data-notification-scope="selected"');
    expect(template).to.include('id="attendee-notification-recipient-scope"');
    expect(template).to.include('id="attendee-notification-selected-fields"');
    expect(template).not.to.include("attendee-notification-recipient-search");
    expect(template).not.to.include("data-recipients-url");
  });

  it("offers all, checked-in, and chosen attendee badge recipients", async () => {
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include('id="attendee-badge-actions-button"');
    expect(template).to.include("data-attendee-badge-actions-dropdown");
    expect(template).to.include('data-recipient-scope="all-attendees"');
    expect(template).to.include("<span>All attendees</span>");
    expect(template).to.include('data-recipient-scope="checked-in-attendees"');
    expect(template).to.include("<span>Checked-in attendees</span>");
    expect(template).to.include('data-selection-action="badge"');
    expect(template).to.include("data-badge-eligible");
    expect(template).not.to.include('data-award-scope="bulk"');
  });

  it("renders registration answers in the review modal layout", async () => {
    // Load the attendees list template before checking answers markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify renders registration answers in the review modal layout.
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
