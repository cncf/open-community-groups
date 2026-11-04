import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/user/submissions_list.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard user submissions list template", () => {
  it("puts the group context before the event link", async () => {
    // Load the template before checking the event cell order
    const template = normalizeWhitespace(await loadTemplate());
    const groupIndex = template.indexOf("{{ submission.event.group_name }}");
    const eventIndex = template.indexOf("{{ submission.event.name }}");

    // Verify the context is read before the event name
    expect(groupIndex).to.be.greaterThan(-1);
    expect(groupIndex).to.be.lessThan(eventIndex);
  });

  it("summarizes submission labels in a tooltip trigger", async () => {
    // Load the template before checking the labels summary
    const template = normalizeWhitespace(await loadTemplate());
    const labelsGuardIndex = template.indexOf("{% if !submission.labels.is_empty() -%}");
    const labelsSummaryIndex = template.indexOf(
      "{{ dashboard::labels_summary(labels = submission.labels, tooltip_id = labels_tooltip_id) -}}",
    );

    // Verify the tooltip id is unique per submission
    expect(template).to.include(
      "{% let labels_tooltip_id -%}user-submission-labels-{{ submission.cfs_submission_id }}{%- endlet %}",
    );

    // Verify the summary renders only for labelled submissions, next to the full chips
    expect(labelsGuardIndex).to.be.greaterThan(-1);
    expect(labelsSummaryIndex).to.be.greaterThan(labelsGuardIndex);
    expect(template).to.include("{{ badges::label_chip(name = &label.name, color = &label.color) -}}");
  });

  it("passes a compact label to the inline status of information requests", async () => {
    // Load the template before checking the inline status line
    const template = normalizeWhitespace(await loadTemplate());

    // Verify information requests get a compact label from the status id
    expect(template).to.include(
      '{% let status_compact_label -%}{% if submission.status_id == "information-requested" %}Info requested{% endif %}{%- endlet %}',
    );
    expect(template).to.include('<span class="sr-only">Status</span>');
    expect(template.match(/compact_label = status_compact_label/g)).to.have.lengthOf(1);

    // Verify both status copies keep the action required indicator
    expect(
      template.match(/badges::submission_status_with_action_required\(status_id = submission\.status_id/g),
    ).to.have.lengthOf(2);
    expect(template.match(/action_required_message = submission\.action_required_message/g)).to.have.lengthOf(
      2,
    );
  });

  it("spans the empty state across the columns visible at each breakpoint", async () => {
    // Load the template before checking the per-breakpoint empty rows
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the empty state matches the hidden Status and Updated columns
    expect(template).to.include('<td class="px-8 py-16 text-center" colspan="3">');
    expect(template).to.include('<td class="px-8 py-16 text-center" colspan="4">');
    expect(template).to.include('<td class="px-8 py-16 text-center" colspan="5">');
  });
});
