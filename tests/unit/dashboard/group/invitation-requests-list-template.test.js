import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch(
    "/ocg-server/templates/dashboard/group/invitation_requests_list.html",
  );

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
    expect(template).to.include(
      "request.user.name.as_deref() |assigned_or(request.user.username)",
    );
  });

  it("uses the shared search convention for table filtering", async () => {
    // Load the invitation requests list template before checking search markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify invitation request search follows the existing dashboard HTMX pattern.
    expect(template).to.include('id="invitation-requests-search-form"');
    expect(template).to.include(
      'hx-get="/dashboard/group/events/{{ event.event_id }}/invitation-requests"',
    );
    expect(template).to.include('hx-trigger="change, submit"');
    expect(template).to.include('hx-target="#invitation-requests-content"');
    expect(template).to.include(
      '<label for="search_invitation_requests" class="sr-only">Search invitation requests</label>',
    );
    expect(template).to.include('name="ts_query"');
    expect(template).to.include('value="{{ ts_query|assigned_or("") }}"');
    expect(template).to.include('placeholder="Search requests"');
    expect(template).to.include('aria-label="Clear invitation request search"');
    expect(template).to.include(
      "dashboard/placeholders/group_invitation_requests_no_results.html",
    );
  });

  it("renders request sort select, title, and status filter controls", async () => {
    // Load the invitation requests template before checking table filters.
    const template = normalizeWhitespace(await loadTemplate());

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
    expect(template).to.include('<span class="whitespace-nowrap">Requested</span>');
    expect(template).to.include('class="px-3 xl:px-5 py-1.5"');
    expect(template).to.include(
      'class="hidden 2xl:table-cell px-3 xl:px-5 py-1.5"',
    );
    expect(template).to.include(
      'class="hidden xl:table-cell px-3 xl:px-5 py-1.5 w-40"',
    );
    expect(template).to.include('class="px-3 xl:px-5 py-1.5 w-48"');
    expect(template).to.include(
      'class="hidden 2xl:table-cell px-3 xl:px-5 py-4 max-w-0"',
    );
    expect(template).to.include('class="hidden xl:table-cell px-3 xl:px-5 py-4 whitespace-nowrap w-40"');
    expect(template).to.include('class="hidden 2xl:table-cell px-3 xl:px-5 py-4 whitespace-nowrap w-40"');
    expect(template).to.include('class="px-3 xl:px-5 py-1.5 w-24 text-right"');
    expect(template).to.include('<span class="sr-only">Actions</span>');
    expect(template).to.include('class="xl:hidden px-8 py-12 text-center" colspan="3"');
    expect(template).to.include(
      'class="hidden xl:table-cell 2xl:hidden px-8 py-12 text-center" colspan="4"',
    );
    expect(template).to.include('class="hidden 2xl:table-cell px-8 py-12 text-center" colspan="6"');
    expect(template).to.include(
      'dashboard::table_filter_menu(id = "invitation-requests-position-filter"',
    );
    expect(template).to.include(
      'dashboard::table_filter_menu(id = "invitation-requests-status-filter"',
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
    expect(template).to.not.include('dashboard::active_table_filter_badge("Status:');
    expect(template).to.not.include('dashboard::active_table_filter_badge("Sort:');
  });

  it("preserves current filters for invitation request refreshes", async () => {
    // Load the invitation requests list template before checking refresh markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify action-triggered refreshes reuse the handler-built filtered URL.
    expect(template).to.include('id="invitation-requests-refresh"');
    expect(template).to.include('hx-get="{{ refresh_url }}"');
    expect(template).to.include(
      'hx-trigger="refresh-event-invitation-requests from:body"',
    );
    expect(template).not.to.include("refresh_limit");
  });
});
