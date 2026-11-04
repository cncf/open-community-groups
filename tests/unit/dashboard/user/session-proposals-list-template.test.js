import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/user/session_proposals_list.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard user session proposals list template", () => {
  it("passes compact labels to the long proposal statuses", async () => {
    // Load the template before checking the status badge calls
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the long catalog statuses get compact labels
    expect(template).to.include(
      'title = "This proposal can be submitted to event call for speakers.", compact_label = "Ready")',
    );
    expect(template).to.include('you\'ll need to remove the co-speaker.", compact_label = "Declined")');
    expect(template).to.include(
      'title = "This proposal is waiting for co-speaker response.", compact_label = "Awaiting")',
    );

    // Verify the short statuses keep their full label only
    expect(template.match(/compact_label = /g)).to.have.lengthOf(3);
    expect(template).to.include('badges::status_badge(label = "Linked", published = true');
    expect(template).to.include('badges::status_badge(label = "Submitted", extra_styles');
  });

  it("names the co-speaker below the proposal title", async () => {
    // Load the template before checking the proposal cell
    const template = normalizeWhitespace(await loadTemplate());
    const titleIndex = template.indexOf("{{ session_proposal.title }}");
    const coSpeakerLineIndex = template.indexOf(
      "with {{ co_speaker.name.as_deref().unwrap_or(&co_speaker.username) }}",
    );
    const coSpeakerHeaderIndex = template.indexOf(">Co-speaker</th>");

    // Verify the co-speaker line reads the optional co-speaker after the title
    expect(template).to.include("{% if let Some(co_speaker) = &session_proposal.co_speaker -%}");
    expect(coSpeakerLineIndex).to.be.greaterThan(titleIndex);
    expect(coSpeakerHeaderIndex).to.be.greaterThan(-1);
    expect(
      template.match(/\{% if let Some\(co_speaker\) = &session_proposal\.co_speaker -%\}/g),
    ).to.have.lengthOf(2);
  });

  it("keeps the co-speaker invitation actions and their contracts", async () => {
    // Load the template before checking the pending invitations table
    const template = normalizeWhitespace(await loadTemplate());

    // Verify each invitation keeps its view, accept and decline actions
    expect(template).to.include('data-action="view-pending-session-proposal"');
    expect(template).to.include('data-action="accept-co-speaker-invitation"');
    expect(template).to.include(
      'id="reject-co-speaker-invitation-{{ invitation.session_proposal.session_proposal_id }}"',
    );
    expect(template).to.include('data-action="reject-co-speaker-invitation"');
    expect(template).to.include('aria-label="Decline invitation"');
    expect(template).to.include(
      'hx-put="/dashboard/user/session-proposals/{{ invitation.session_proposal.session_proposal_id }}/co-speaker-invitation/reject" hx-trigger="confirmed"',
    );
  });

  it("spans the empty state across the columns visible at each breakpoint", async () => {
    // Load the template before checking the per-breakpoint empty rows
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the empty state matches the hidden Co-speaker and Updated columns
    expect(template).to.include('<td class="px-8 py-16 text-center" colspan="3">');
    expect(template).to.include('<td class="px-8 py-16 text-center" colspan="4">');
    expect(template).to.include('<td class="px-8 py-16 text-center" colspan="5">');
  });
});
