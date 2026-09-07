import { expect } from "@open-wc/testing";

const EXTERNAL_PAYMENT_TEMPLATE_NAMES = ["event_external_payment_pending", "event_external_payment_reminder"];

const loadTemplate = async (name) => {
  const response = await fetch(`/ocg-server/templates/notifications/${name}.html`);

  expect(response.ok).to.equal(true);

  return response.text();
};

describe("external payment notification templates", () => {
  it("keeps every payment detail in one structured list", async () => {
    const templates = await Promise.all(EXTERNAL_PAYMENT_TEMPLATE_NAMES.map(loadTemplate));

    templates.forEach((template) => {
      const detailsListStart = template.indexOf('<ul class="default"');
      const detailsListEnd = template.indexOf("</ul>", detailsListStart);
      const detailsList = template.slice(detailsListStart, detailsListEnd);

      expect(detailsListStart).to.be.greaterThan(-1);
      expect(detailsListEnd).to.be.greaterThan(detailsListStart);
      ["Ticket", "Event", "Group", "Amount", "Reference", "Deadline", "Instructions"].forEach((label) => {
        expect(detailsList).to.include(`<strong>${label}:</strong>`);
      });
      expect(detailsList).to.include("external_payment_instructions");
    });
  });

  it("labels the event timezone and safely wraps attendee-supplied details", async () => {
    const templates = await Promise.all(EXTERNAL_PAYMENT_TEMPLATE_NAMES.map(loadTemplate));

    templates.forEach((template) => {
      expect(template).to.include('deadline.with_timezone(timezone).format("%b %d, %Y at %H:%M %Z")');
      expect(template).to.match(/white-space:\s*pre-wrap/gu);
      expect(template).to.match(/overflow-wrap:\s*(?:anywhere|break-word)/gu);
    });
  });
});
