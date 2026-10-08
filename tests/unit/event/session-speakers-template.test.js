import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/event/page.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("event page session speakers template", () => {
  it("renders featured speakers first in the same row as regular speakers", async () => {
    // Load the event page template before checking the session speakers.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify both speaker loops share one wrapping row, featured speakers first.
    expect(template).to.include(
      `<div class="flex flex-wrap items-center gap-3"> {% for speaker in session.speakers -%} {% if speaker.featured && speaker.user.name.is_some() -%} <user-chip user='{{ speaker.user|json }}' featured small display-modal></user-chip> {% endif -%} {% endfor -%} {% for speaker in session.speakers -%} {% if !speaker.featured && speaker.user.name.is_some() -%} <user-chip user='{{ speaker.user|json }}' small display-modal></user-chip> {% endif -%} {% endfor -%} </div>`,
    );
    expect(template).to.not.include("featured-sessions-grid");
    expect(template).to.not.include("regular-sessions-speakers");
  });
});
