import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch(
    "/ocg-server/templates/dashboard/user/check_in_list.html",
  );

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard user check-in template", () => {
  it("uses the dashboard content width", async () => {
    // Load the Check-In template before checking its page alignment.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the partial does not add a centered page-width constraint.
    expect(template).to.include(
      '<section class="relative min-w-0" data-user-check-in-root',
    );
    expect(template).not.to.include("container mx-auto");
    expect(template).not.to.include("max-w-7xl");
  });

  it("keeps medium dashboard cards stacked with shared status placement", async () => {
    // Load the Check-In template before checking responsive card presentation.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify cards split only on wide screens and retain the shared card layout.
    expect(template).to.include("md:gap-8 2xl:grid-cols-2");
    expect(template).not.to.include("md:gap-8 lg:grid-cols-2");
    expect(template).to.include("cards::check_in_event_card(event)");
    expect(template).not.to.include("status_before_title");
  });

  it("places attendee identity below the QR code and adds a modal footer", async () => {
    // Load the Check-In template before checking credential and footer structure.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify identity stays inside the credential and the Close action stays fixed.
    const credentialStart = template.indexOf("data-user-check-in-credential");
    const qrImage = template.indexOf('id="user-check-in-qr-image"');
    const userInfo = template.indexOf("data-user-check-in-user");
    const credentialEnd = template.indexOf("</div> </div> </div> <footer");
    const footer = template.indexOf('<footer class="flex shrink-0 justify-end');
    expect(qrImage).to.be.greaterThan(credentialStart);
    expect(userInfo).to.be.greaterThan(qrImage);
    expect(userInfo).to.be.lessThan(credentialEnd);
    expect(footer).to.be.greaterThan(credentialEnd);
    expect(template).to.include(
      'data-user-check-in-user> <div id="user-check-in-photo"',
    );
    expect(template).to.include(
      'class="text-center text-xs text-stone-500">Show this code to an organizer</p>',
    );
    expect(template).to.include(
      'class="btn-primary-outline w-full sm:w-auto" data-user-check-in-close>Close</button>',
    );
  });
});
