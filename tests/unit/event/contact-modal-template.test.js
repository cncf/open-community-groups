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

  it("only renders the contact opener when the event has organizers", async () => {
    // Load the organizers section of the event page template
    const template = await loadTemplate("event/page.html");
    const sectionStart = template.indexOf("{# Organizers section -#}");
    const sectionEnd = template.indexOf("{# End organizers section -#}");
    const section = template.slice(sectionStart, sectionEnd);

    // Verify the whole section, including the opener and modal, is guarded
    expect(sectionStart).to.be.greaterThan(-1);
    expect(sectionEnd).to.be.greaterThan(sectionStart);
    expect(section).to.match(/^\{# Organizers section -#\} \{% if !event\.organizers\.is_empty\(\) -%\}/);
    expect(section).to.match(/\{% endif -%\} $/);
    expect(section).to.include('<button id="open-contact-modal"');
    expect(section).to.include('<div id="contact-modal"');
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
