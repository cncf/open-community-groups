import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/invitation_requests_list.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group invitation requests list template", () => {
  it("renders requester identity cells as profile modal triggers", async () => {
    // Load the invitation requests list template before checking profile trigger markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the requester identity area uses the shared profile trigger macro.
    expect(template).to.include(
      "dashboard::user_profile_modal_trigger(request.user, self::user_initials(request.user.name.as_deref() , request.user.username.as_str()))",
    );
    expect(template).to.include("request.user.name.as_deref() |assigned_or(request.user.username)");
  });

  it("uses the shared search convention for table filtering", async () => {
    // Load the invitation requests list template before checking search markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify invitation request search follows the existing dashboard HTMX pattern.
    expect(template).to.include('id="invitation-requests-search-form"');
    expect(template).to.include('hx-get="/dashboard/group/events/{{ event.event_id }}/invitation-requests"');
    expect(template).to.include('hx-trigger="change, submit"');
    expect(template).to.include('hx-target="#invitation-requests-content"');
    expect(template).to.include(
      '<label for="search_invitation_requests" class="sr-only">Search invitation requests</label>',
    );
    expect(template).to.include('name="ts_query"');
    expect(template).to.include('value="{{ ts_query|assigned_or("") }}"');
    expect(template).to.include('placeholder="Search requests"');
    expect(template).to.include('aria-label="Clear invitation request search"');
    expect(template).to.include("dashboard/placeholders/group_invitation_requests_no_results.html");
  });

  it("renders request sort select, title, and status filter controls", async () => {
    // Load the invitation requests template before checking table filters.
    const template = normalizeWhitespace(await loadTemplate());
    const tableHeader = template.slice(
      template.indexOf("{# Table header -#}"),
      template.indexOf("{# End table header -#}"),
    );

    // Verify request filters preserve current search, sort, and status state.
    expect(template).to.include('name="sort" value="{{ sort }}"');
    expect(template).to.include('name="title" value="{{ title }}"');
    expect(template).to.include('name="ts_query" value="{{ ts_query }}"');
    expect(template).to.include('name="status" value="{{ status }}"');
    expect(template).to.include('<label for="invitation-requests-sort"');
    expect(template).to.include('id="invitation-requests-sort"');
    expect(template).to.include('name="sort"');
    expect(template).to.include('hx-trigger="change"');
    expect(template).to.include("sm:w-[36rem]");
    expect(template).to.include("self-end sm:ms-auto");
    expect(template).to.include("Requester ↑");
    expect(template).to.include("Requester ↓");
    expect(template).to.include("Requested ↑");
    expect(template).to.include("Requested ↓");
    expect(template).to.include('<option value="name-asc"');
    expect(template).to.include('<option value="name-desc"');
    expect(template).to.include('<option value="created-at-asc"');
    expect(template).to.include('<option value="created-at-desc"');
    expect(template).to.not.include("dashboard::table_sort_menu");
    expect(template).to.not.include("dashboard::table_sort_option_button");
    expect(template).to.not.include("dashboard::table_sort_control");
    expect(template).to.include('<span class="whitespace-nowrap">Requester</span>');
    expect(template).to.include('<span class="whitespace-nowrap">Ticket type</span>');
    expect(template).to.include('<span class="whitespace-nowrap">Requested</span>');
    expect(template).to.include('class="px-3 xl:px-5 py-1.5 xl:w-[30%]"');
    expect(template).to.include(
      'class="hidden min-[1920px]:table-cell px-3 xl:px-5 py-1.5"',
    );
    expect(template).to.include('class="hidden min-[1920px]:table-cell px-3 xl:px-5 py-1.5 w-40"');
    expect(template).to.include('class="hidden 2xl:table-cell px-3 xl:px-5 py-1.5 w-48"');
    expect(template).to.include('class="px-3 xl:px-5 py-1.5 w-48"');
    expect(template).to.include(
      'class="hidden min-[1920px]:table-cell px-3 xl:px-5 py-4 max-w-0"',
    );
    expect(template).to.include('class="hidden 2xl:table-cell px-3 xl:px-5 py-4 max-w-0 w-48"');
    expect(template).to.include('class="truncate text-xs text-stone-600 2xl:hidden"');
    expect(template).to.include(
      'class="hidden min-[1920px]:table-cell px-3 xl:px-5 py-4 whitespace-nowrap w-40"',
    );
    expect(template).to.include('class="hidden 2xl:table-cell px-3 xl:px-5 py-4 whitespace-nowrap w-40"');
    expect(template).to.include('class="px-3 xl:px-5 py-1.5 w-24 text-right"');
    expect(template).to.include('<span class="sr-only">Actions</span>');
    expect(template).to.include('class="2xl:hidden px-8 py-12 text-center" colspan="3"');
    expect(template).not.to.include("hidden xl:table-cell 2xl:hidden");
    expect(template).to.include(
      'class="hidden 2xl:table-cell min-[1920px]:hidden px-8 py-12 text-center" colspan="5"',
    );
    expect(template).to.include('class="hidden min-[1920px]:table-cell px-8 py-12 text-center" colspan="7"');
    expect(tableHeader.indexOf("Status")).to.be.lessThan(tableHeader.indexOf("Ticket type"));
    expect(tableHeader.indexOf("Ticket type")).to.be.lessThan(tableHeader.indexOf("Requested"));
    expect(tableHeader.indexOf("Requested")).to.be.lessThan(tableHeader.indexOf("Reviewed"));
    expect(template).to.include('dashboard::table_filter_menu(id = "invitation-requests-position-filter"');
    expect(template).to.include('dashboard::table_filter_menu(id = "invitation-requests-status-filter"');
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
      'dashboard::table_filter_option_button(label = "All", name = "status", value = "all", is_active = status == crate::templates::dashboard::group::invitation_requests::InvitationRequestsStatusFilter::All, clear_value = "all")',
    );
    expect(template).to.include(
      'dashboard::table_filter_option_button(label = "Accepted", name = "status", value = "accepted"',
    );
    expect(template).to.include(
      'dashboard::table_filter_option_button(label = "Rejected", name = "status", value = "rejected"',
    );
    expect(template).to.include("Reset all");
    expect(template).to.not.include("invitation-requests-requester-filter");
    expect(template).to.include('dashboard::active_table_filter_badge("Status", "Accepted")');
    expect(template).to.include('dashboard::active_table_filter_badge("Status", "Pending")');
    expect(template).to.include('dashboard::active_table_filter_badge("Status", "Rejected")');
    expect(template).to.include('dashboard::active_table_filter_badge("Position", "Present")');
    expect(template).to.include('dashboard::active_table_filter_badge("Position", "Missing")');
    expect(template).to.not.include('dashboard::active_table_filter_badge("Sort"');
  });

  it("preserves current filters for invitation request refreshes", async () => {
    // Load the invitation requests list template before checking refresh markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify action-triggered refreshes reuse the handler-built filtered URL.
    expect(template).to.include('id="invitation-requests-refresh"');
    expect(template).to.include('hx-get="{{ refresh_url }}"');
    expect(template).to.include('hx-trigger="refresh-event-invitation-requests from:body"');
    expect(template).not.to.include("refresh_limit");
  });

  it("shows ticket request offers and exact organizer actions", async () => {
    // Load the invitation requests template before checking offer workflow markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify requester-selected tiers and offer metadata remain visible.
    expect(template).to.include("request.requested_ticket_title.as_deref()");
    expect(template).to.include("Private admission");
    expect(template).to.include("request.offered_ticket_title.as_deref()");
    expect(template).to.include("Ticket offer");
    expect(template).to.include("group/request-offer relative inline-flex shrink-0");
    expect(template).to.include(
      "invitation-request-offer-details-{{ request.user.user_id }}",
    );
    expect(template).to.include('aria-describedby="{{ request_offer_tooltip_id }}"');
    expect(template).to.include("dashboard::tooltip_panel(");
    expect(template).to.include('title = "Ticket offer"');
    expect(template).to.include("group-hover/request-offer:visible");
    expect(template).to.include("group-focus-within/request-offer:visible");
    expect(template).to.include("border-2 border-white");
    expect(template).to.include("bg-amber-800");
    expect(template).to.include("bg-red-800");
    expect(template).to.include("bg-green-800");
    expect(template).not.to.include("icon-info");
    expect(template).to.include("Offer status");
    expect(template).to.include("Checkout in progress");
    expect(template).to.include("Expired");
    expect(template).to.include(
      'invitation_request_status_badge(request, event, "Pending", false, false)',
    );
    expect(template).to.include(
      'invitation_request_status_badge(request, event, "Rejected", true, false)',
    );
    expect(template).to.include(
      'invitation_request_status_badge(request, event, "Accepted", false, true)',
    );
    expect(template).to.not.include("Request pending");
    expect(template).to.not.include("Request rejected");
    expect(template).to.not.include("Request accepted");
    expect(template).to.include(
      'offer_expires_at.with_timezone(event.timezone).format("%b %d, %Y at %I:%M %p %Z")',
    );

    // Verify the requested tier is submitted with the approval action.
    expect(template).to.include('name="event_ticket_type_id"');
    expect(template).to.include("data-invitation-request-ticket-empty");
    expect(template).to.include("data-invitation-request-ticket-type");
    expect(template).to.include("data-invitation-request-ticket-submit");
    expect(template).to.include("request.requested_event_ticket_type_id");
    expect(template).to.include('name="event_ticket_type_id" value="{{ requested_event_ticket_type_id }}"');
    expect(template).to.include("Invitation-only ticket");
    expect(template).to.include(
      "ticket_type.availability == crate::types::payments::EventTicketTypeAvailability::InvitationOnly",
    );
    expect(template).to.include("ticket_type.current_price.is_some()");
    expect(template).to.include("!ticket_type.sold_out");
    expect(template).to.include(
      "No invitation-only ticket types can be assigned. Add seats or activate an invitation-only ticket type with a current price before accepting this request.",
    );

    // Verify active offers can be canceled and only expired approval offers can be reissued.
    expect(template).to.include('hx-put="/dashboard/group/admission-offers/{{ admission_offer_id }}/cancel"');
    expect(template).to.include('id="cancel-invitation-request-offer-{{ admission_offer_id }}"');
    expect(template).to.include("Cancel offer");
    expect(template).to.include("Reissue offer");
    expect(template).to.include(
      "{% if request.admission_offer_status == Some(crate::types::event::EventAdmissionOfferStatus::Expired) %}reissue{% else %}accept{% endif %}",
    );
    expect(template).to.not.include("waitlist/reissue");

    // Verify the mixed form-control dropdown avoids ARIA menu semantics.
    const actionDisclosureStart = template.indexOf(
      'data-event-id="invitation-request-{{ request.user.user_id }}"',
    );
    const actionDisclosureEnd = template.indexOf("{# End dropdown actions -#}", actionDisclosureStart);
    expect(actionDisclosureStart).to.be.greaterThan(-1);
    expect(actionDisclosureEnd).to.be.greaterThan(actionDisclosureStart);
    const actionDisclosure = template.slice(actionDisclosureStart, actionDisclosureEnd);
    expect(actionDisclosure).to.include(
      'aria-label="Open actions for {{ request.user.name.as_deref() |assigned_or(request.user.username) }}"',
    );
    expect(actionDisclosure).to.include('aria-expanded="false"');
    expect(actionDisclosure).to.not.include('aria-label="Open actions menu for');
    expect(actionDisclosure).to.not.include('aria-haspopup="menu"');
    expect(actionDisclosure).to.not.include('<ul class="py-2 text-sm text-stone-700" role="menu">');
    expect(actionDisclosure).to.not.include('role="menuitem"');
    expect(template).to.not.include('<div class="text-right text-stone-400">-</div>');
    expect(actionDisclosure).to.include(
      'class="dropdown absolute end-0 top-8 z-10 hidden w-[280px] overflow-hidden rounded-lg border border-stone-200 bg-white py-1 shadow-lg"',
    );
    expect(actionDisclosure).to.include(
      "px-3 py-2 text-start text-sm text-stone-700 transition-colors hover:bg-stone-50",
    );

    // Confirmation-owned controls do not duplicate response handling.
    const cancelOfferStart = actionDisclosure.indexOf(
      'id="cancel-invitation-request-offer-{{ admission_offer_id }}"',
    );
    const cancelOfferEnd = actionDisclosure.indexOf("</button>", cancelOfferStart);
    const cancelOffer = actionDisclosure.slice(cancelOfferStart, cancelOfferEnd);
    expect(cancelOffer).to.include("data-confirm-action");
    expect(cancelOffer).to.not.include("data-invitation-request-action");
    const rejectRequestStart = actionDisclosure.indexOf(
      'id="reject-invitation-request-{{ request.user.user_id }}"',
    );
    const rejectRequestEnd = actionDisclosure.indexOf("</button>", rejectRequestStart);
    const rejectRequest = actionDisclosure.slice(rejectRequestStart, rejectRequestEnd);
    expect(rejectRequest).to.include("data-confirm-action");
    expect(rejectRequest).to.not.include("data-invitation-request-action");

    // Verify organizers can review request answers when public registration is not open.
    expect(template).to.include("View answers");
    expect(template).to.include(
      "question_answers::review_list(questions = registration_questions, answers = request.registration_answers.as_ref())",
    );
    expect(template).to.include(
      'question_answers::review_modal(id_prefix = "invitation-request-answers")',
    );
    expect(template).to.include("data-answers-open");
    expect(template).to.include("event.registration_window_is_open()");
    expect(template).to.include("event.has_started()");
    expect(template).to.not.include("data-invitation-request-accept-blocked");
    expect(template).to.include(
      "Public registration is not currently open. New requests cannot be submitted. Pending requests can",
    );
    expect(template).to.include(
      "still be accepted or rejected, and expired approval offers can be reissued.",
    );
  });
});
