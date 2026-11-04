import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/user/check_in_list.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard user check-in template", () => {
  it("uses the dashboard content width", async () => {
    // Load the Check-In template before checking its page alignment.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the partial does not add a centered page-width constraint.
    expect(template).to.include('<section class="relative min-w-0" data-user-check-in-root');
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

  it("wraps a long unbroken event name inside the check-in card on phones", async () => {
    // Load the shared card macro, where the title's width comes from its own content.
    const response = await fetch("/ocg-server/templates/macros/cards.html");
    expect(response.ok).to.equal(true);
    const cards = normalizeWhitespace(await response.text());

    // Verify the title can shrink below its longest word.
    expect(cards).to.include("md:text-[0.9rem]/[1.1rem] phone:wrap-anywhere");
  });

  it("hides checked-in events and preserves the empty state", async () => {
    // Load the Check-In template before checking event visibility.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify only pending credentials render and the empty grid reveals its placeholder.
    expect(template).to.include("{% if !event.checked_in -%}");
    expect(template).not.to.include(">Checked in</span>");
    expect(template).to.include("empty:hidden");
    expect(template).to.include("peer-empty:block");
    expect(template).to.include("No events awaiting check-in");
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
    expect(template).to.include('data-user-check-in-user> <div id="user-check-in-photo"');
    expect(template).to.include(
      'class="text-center text-xs text-stone-500" data-user-check-in-qr-caption>Show this code to an organizer</p>',
    );
    expect(template).to.include(
      'class="btn-primary-outline w-full sm:w-auto" data-user-check-in-close>Close</button>',
    );
  });

  it("opens the credential as a phone sheet", async () => {
    // Load the Check-In template before checking the credential sheet.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the panel adopts the sheet primitive, with a title row that can be dragged.
    expect(template).to.include("sheet-panel phone:h-[calc(100dvh-4rem)]");
    expect(template).to.include("sheet-head sheet-grab");
    expect(template).to.include("phone:max-w-[max(12rem,min(100%,calc(100dvh-21rem)))]");
    expect(template).to.include("phone:line-clamp-2 phone:wrap-anywhere");
  });

  it("keeps the QR failure state free of the shared broken-image tile", async () => {
    // Load the Check-In template before checking the QR area.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the image opts out of the tile, with no phone token left to hide it.
    expect(template).to.match(/id="user-check-in-qr-image"[^>]*data-ocg-skip-broken-image>/);
    expect(template).not.to.include("data-ocg-broken-image-icon");

    // Verify the caption is hidden by the module rather than by a phone token.
    expect(template).not.to.include("[&>p]:hidden");
  });

  it("shows the tap cue on phones only, away from assistive technology", async () => {
    // Load the Check-In template before checking the card cue.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the cue is hidden off phones and adds nothing to the card's accessible name.
    const cue = template.slice(0, template.indexOf("Show QR code"));
    const cueStart = cue.lastIndexOf('<span class="not-phone:hidden');
    expect(cueStart).to.be.greaterThan(-1);
    expect(cue.slice(cueStart)).to.include('aria-hidden="true"');
    expect(cue.slice(cueStart)).to.include("icon-qr-code");
  });
});
