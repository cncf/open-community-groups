import { expect } from "@open-wc/testing";

/**
 * Loads a server template as text.
 * @param {string} path Template path under the templates folder.
 * @returns {Promise<string>} Template text with collapsed whitespace.
 */
const loadTemplate = async (path) => {
  const response = await fetch(`/ocg-server/templates/${path}`);

  expect(response.ok).to.equal(true);

  return (await response.text()).replace(/\s+/g, " ").trim();
};

describe("event contact modal templates", () => {
  it("keeps the static modal frame on the cached event page", async () => {
    // Load the event page template
    const template = await loadTemplate("event/page.html");

    // Verify the opener loads the modal content into the root that opens the modal
    expect(template).to.include('<button id="open-contact-modal" type="button"');
    expect(template).to.include(
      'hx-get="/{{ event.community.name }}/event/{{ event.event_id }}/contact-modal"',
    );
    expect(template).to.include('hx-target="#contact-modal-root"');
    expect(template).to.include('<div id="contact-modal-root" data-modal-open-on-swap="contact-modal"');

    // Verify a failed modal load shows the declarative error alert
    expect(template).to.include(
      'hx-disabled-elt="#open-contact-modal" data-htmx-response data-error-message="Something went wrong loading the contact form. Please try again later."',
    );

    // Verify every close control toggles the dialog
    expect(template).to.include(
      '<div id="contact-modal" role="dialog" aria-modal="true" aria-labelledby="contact-modal-title"',
    );
    expect(template).to.include('<div id="overlay-contact-modal" data-modal-toggle="contact-modal"');
    expect(template).to.include(
      '<button id="close-contact-modal" type="button" data-modal-toggle="contact-modal"',
    );
  });

  it("renders the contact opener at the end of the event description", async () => {
    // Load the event description and organizers sections of the event page template
    const template = await loadTemplate("event/page.html");
    const descriptionStart = template.indexOf("{# Event description -#}");
    const descriptionEnd = template.indexOf("{# End event description -#}");
    const description = template.slice(descriptionStart, descriptionEnd);
    const organizers = template.slice(
      template.indexOf("{# Organizers section -#}"),
      template.indexOf("{# End organizers section -#}"),
    );

    // Verify the opener and modal follow the meeting details, outside any organizers guard
    expect(descriptionStart).to.be.greaterThan(-1);
    expect(descriptionEnd).to.be.greaterThan(descriptionStart);
    expect(description).not.to.include("event.organizers");
    expect(description.indexOf("data-meeting-details")).to.be.lessThan(
      description.indexOf('<button id="open-contact-modal"'),
    );
    expect(description).to.include(
      '<span class="svg-icon size-3 icon-email bg-current" aria-hidden="true"></span> <span>Contact organizers</span> </button>',
    );
    expect(description).to.match(/\{# End contact organizers modal -#\} <\/div> $/);

    // Verify the organizers section no longer renders the opener or modal
    expect(organizers).not.to.include('id="open-contact-modal"');
    expect(organizers).not.to.include('id="contact-modal"');
  });

  it("keeps the contact form contract", async () => {
    // Load the contact modal template
    const template = await loadTemplate("event/contact_modal.html");

    // Verify the form posts to the contact route and uses the declarative response alerts
    expect(template).to.include('<form id="contact-form"');
    expect(template).to.include(
      'hx-post="/{{ context.community_name }}/event/{{ context.event_id }}/contact"',
    );
    expect(template).to.include('hx-target="#contact-modal-root"');
    expect(template).to.include('hx-disabled-elt="#contact-submit-button"');
    expect(template).to.include("data-htmx-response");

    // Verify the labelled message field leaves the character limit to the server
    expect(template).to.include('<label for="contact-body" class="form-label">Message</label>');
    expect(template).to.include('<textarea id="contact-body" name="body"');
    expect(template).not.to.include("maxlength=");
    expect(template).to.include("{{ crate::validation::MAX_LEN_INBOX_MESSAGE }} characters");

    // Verify cancel closes the modal
    expect(template).to.include(
      '<button id="cancel-contact-modal" type="button" data-modal-toggle="contact-modal"',
    );
  });
});
