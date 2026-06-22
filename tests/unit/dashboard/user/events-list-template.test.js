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
      'hx-delete="/dashboard/user/events/{{ item.event.alliance_name }}/{{ item.event.event_id }}/attendance"',
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
  });

  it("renders pending attendance status and typed roles as badges", async () => {
    // Load the user events template before checking pending badges.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify pending attendance status uses the status badge and roles use regular badges.
    expect(template).to.include(
      "{% if let Some(attendance_status_label) = item.attendance_status_label() -%}",
    );
    expect(template).to.include(
      '{{ badges::status_badge(label = attendance_status_label, extra_styles = Some("uppercase") ) -}}',
    );
    expect(template).to.include(
      '{{ badges::common_badge(content = role.label() , extra_styles = Some("px-2.5 py-0.5") ) -}}',
    );
  });
});
