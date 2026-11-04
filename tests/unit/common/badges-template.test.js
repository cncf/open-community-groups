import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/macros/badges.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

const getMacro = (template, name) =>
  template.slice(template.indexOf(`{% macro ${name}(`), template.indexOf(`{% endmacro ${name}`));

describe("badge macros template", () => {
  it("keeps the label chip on the compact badge foundation", async () => {
    // Load the badge macros template before checking the label chip.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify label chips keep the shared badge styles.
    expect(template).to.include(
      'class="custom-badge inline-block max-w-full truncate px-2.5 py-0.5 text-stone-900',
    );
  });

  it("tightens sponsor cards on phones and marks only linked ones as external", async () => {
    // Load and isolate the sponsor badge.
    const template = normalizeWhitespace(await loadTemplate());
    const sponsorBadge = getMacro(template, "sponsor_badge");

    // Verify both branches keep their frame and gain the phone padding.
    expect(sponsorBadge.match(/rounded-xl border border-stone-200 bg-white p-4 w-full/g)).to.have.length(2);
    expect(sponsorBadge.match(/phone:px-3 phone:py-2\.5/g)).to.have.length(2);

    // Verify the phone-only icon closes the link branch and never the plain card.
    const icon =
      '<div class="svg-icon ms-auto size-4 shrink-0 bg-stone-400 icon-external-link not-phone:hidden" aria-hidden="true"></div>';
    expect(sponsorBadge).to.include(`{% if let Some(website_url) = &website_url -%} ${icon} </a> {% else -%} </div>`);
    expect(sponsorBadge.match(/icon-external-link/g)).to.have.length(1);
  });

  it("renders tone badges from the badge tone classes", async () => {
    // Load and isolate the shared tone badge.
    const template = normalizeWhitespace(await loadTemplate());
    const toneBadge = getMacro(template, "tone_badge");

    // Verify the tone selects the badge class and the label stays the direct text.
    expect(toneBadge).to.include(
      'macro tone_badge(label, tone, title = "", compact_label = "", extra_styles = None)',
    );
    expect(toneBadge).to.include('class="custom-badge badge-{{ tone }} {{ extra_styles_ }}"');
    expect(toneBadge).to.include('{% if !title.is_empty() %}title="{{ title }}"{% endif %}');
    expect(toneBadge).to.include("{%- if compact_label.is_empty() -%} {{ label }} {%- else -%}");

    // Verify the compact label is hidden from assistive technology and the full label names the badge.
    expect(toneBadge).to.match(/<span aria-hidden="true"[^>]*>\{\{ compact_label \}\}<\/span>/);
    expect(toneBadge).to.match(/<span(?! aria-hidden)[^>]*>\{\{ label \}\}<\/span>/);
  });

  it("renders payment and inbox badges from typed tones instead of label text", async () => {
    // Load and isolate the payment and inbox status badges.
    const template = normalizeWhitespace(await loadTemplate());
    const paymentStatusBadge = getMacro(template, "payment_status_badge");
    const inboxStatusBadge = getMacro(template, "inbox_status_badge");

    // Verify payment badges require the tone and delegate to the tone badge.
    expect(paymentStatusBadge).to.include("macro payment_status_badge(label, tone, extra_styles = None)");
    expect(paymentStatusBadge).to.include(
      "{{ tone_badge(label = label, tone = tone, extra_styles = extra_styles) -}}",
    );

    // Verify inbox badges take their tone from the typed conversation status.
    expect(inboxStatusBadge).to.include(
      "tone = crate::templates::dashboard::inbox::status_tone(status).as_str()",
    );

    // Verify neither badge compares label text.
    expect(paymentStatusBadge).not.to.include("label.as_bytes()");
    expect(inboxStatusBadge).not.to.include("label.as_bytes()");
  });

  it("maps status and submission badges to tone badges", async () => {
    // Load and isolate the status, submission, and test event badges.
    const template = normalizeWhitespace(await loadTemplate());
    const statusBadge = getMacro(template, "status_badge");
    const submissionStatusBadge = getMacro(template, "submission_status_badge");
    const submissionWithActionRequired = getMacro(template, "submission_status_with_action_required");
    const testEventBadge = getMacro(template, "test_event_badge");

    // Verify the event status flags choose the tone and forward the compact label.
    expect(statusBadge).to.include(
      'macro status_badge(label, canceled = false, published = false, title = "", compact_label = "", extra_styles = None)',
    );
    expect(statusBadge).to.include(
      "{% let tone -%}{% if canceled %}danger{% else if published %}success{% else %}warning{% endif %}{%- endlet -%}",
    );
    expect(statusBadge).to.include("compact_label = compact_label");

    // Verify submission status ids choose the tone and unreviewed submissions stay untoned.
    expect(submissionStatusBadge).to.include(
      'macro submission_status_badge(status_id, label, compact_label = "", extra_styles = None)',
    );
    [
      ["approved", "success"],
      ["rejected", "danger"],
      ["information-requested", "warning"],
      ["withdrawn", "neutral"],
    ].forEach(([statusId, tone]) => {
      expect(submissionStatusBadge).to.include(
        `status_id == "${statusId}" -%} {{ tone_badge(label = label, tone = "${tone}", compact_label = compact_label, extra_styles = extra_styles) -}}`,
      );
    });
    expect(submissionStatusBadge).to.include(
      "{% else -%} {# Not reviewed and unknown statuses keep the untoned badge #} {{ common_badge(content = label, extra_styles = extra_styles) -}}",
    );
    expect(submissionWithActionRequired).to.include(
      'action_required_message, compact_label = "", extra_styles = None)',
    );
    expect(submissionWithActionRequired).to.include("compact_label = compact_label");

    // Verify test event badges use the warning tone.
    expect(testEventBadge).to.include('class="custom-badge badge-warning {{ extra_styles_ }}"');
  });
});
