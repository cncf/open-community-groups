import { expect } from "@open-wc/testing";

const SECTION_TITLES = [
  "Call for Speakers",
  "About this event",
  "Agenda",
  "Featured speakers",
  "Sponsors",
  "Gallery",
  "Tags",
];

const loadTemplate = async (path) => {
  const response = await fetch(path);

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("event page phone template", () => {
  let template;

  before(async () => {
    template = normalizeWhitespace(await loadTemplate("/ocg-server/templates/event/page.html"));
  });

  it("keeps the action row off desktop and drops the calendar without a future date", () => {
    // Slice the row between its comments.
    const row = template.slice(
      template.indexOf("{# Phone action row -#}"),
      template.indexOf("{# End phone action row -#}"),
    );

    // Verify the whole row is hidden off phones, with the share host filling it.
    expect(row).to.include('<div class="not-phone:hidden flex gap-2 phone:col-span-2">');
    expect(row).to.include('<share-modal class="flex-1" trigger-variant="action"');

    // Verify the calendar pill sits in an unpadded box too, or the row would not split evenly.
    expect(row).to.include('<div class="flex-1"> <a href=');

    // Verify Add to calendar needs a start date and an event still to come.
    expect(row).to.include("{% if event.starts_at.is_some() && !event.is_past() && !event.canceled -%}");
    expect(row).to.include("/event/{{ event.slug }}/calendar.ics");
  });

  it("keeps availability captions whole and long place names inside the pill", () => {
    // Verify the captions drop to the next line as a unit.
    expect(template).to.include("items-center gap-2 leading-none phone:flex-wrap phone:gap-y-1");
    expect(
      template.match(/opacity-0 transition-opacity duration-150 phone:whitespace-nowrap/g),
    ).to.have.length(2);

    // Verify the no-coordinates pill breaks an unbroken name.
    expect(template).to.include("phone:whitespace-normal phone:wrap-anywhere");
  });

  it("gives the multi-day labels the eyebrow's contrast", () => {
    for (const label of ["From", "To"]) {
      expect(template).to.include(
        `<div class="text-xs uppercase font-medium mb-0.5 phone:text-stone-500">${label}</div>`,
      );
    }
  });

  it("marks past events only on phones", () => {
    expect(template).to.include(
      '{% if event.is_past() -%} <span class="custom-badge not-phone:hidden px-2.5 py-0.5">Past event</span> {% endif -%}',
    );
  });

  it("renders directions as a phone-only pill beside the Location title", () => {
    expect(template).to.include(
      '{% if let Some(url) = event.directions_url() -%} <a data-directions-link href="{{ url }}" target="_blank" rel="noopener noreferrer" class="btn-secondary-anchor pill-link not-phone:hidden">Directions</a> {% endif -%}',
    );
  });

  it("hides the Location card on phones when it has no place to show", () => {
    expect(template).to.include("{% let has_location_details = event.directions_url().is_some() -%}");
    expect(template).to.include("{% if !has_location_details %}phone:hidden{% endif %}");
  });

  it("swaps the empty location text for the full address on phones", () => {
    // Slice the branch used when no location part fits the display limit.
    const branch = template.slice(
      template.lastIndexOf("<div", template.indexOf("Location not provided")),
      template.indexOf("{% else -%}", template.indexOf("Location not provided")),
    );

    // Verify phones drop the placeholder and get a clamped address pill.
    expect(template).to.include(
      '<div class="relative flex w-full items-center justify-center phone:hidden"> <div class="text-xl font-semibold text-stone-700 text-center">Location not provided</div>',
    );
    expect(branch).to.include("{% if let Some(text) = self.event.location(usize::MAX) %}");
    expect(branch).to.match(/<div class="not-phone:hidden absolute [^"]*phone:line-clamp-6 /);

    // Verify the bottom inset is a border, which clips the next line where padding would show it.
    expect(branch).to.match(
      /<div class="not-phone:hidden absolute [^"]*phone:border-b-4 phone:border-transparent phone:pb-0">/,
    );
  });

  it("gives every section title the phone heading", () => {
    // Verify the titles named once on the page.
    for (const title of SECTION_TITLES) {
      expect(template).to.match(new RegExp(`section-strip phone:-mx-3"> ${title} </div>`));
    }

    // Verify all twelve, since Speakers and Hosts each render from two branches.
    expect(template.match(/section-strip phone:-mx-3/g)).to.have.length(12);
  });

  it("collapses the About text and agenda descriptions", () => {
    expect(template).to.include(
      '<div class="read-more"> <div class="text-stone-500 text-sm/6 markdown read-more-body phone:text-[15px]/6 phone:text-stone-600"',
    );
    expect(template).to.include(
      '<div class="read-more"> <div class="text-sm/6 text-stone-600 markdown mt-3 read-more-body"',
    );
    expect(template.match(/class="read-more-toggle not-phone:hidden /g)).to.have.length(2);
  });

  it("turns the contact and CFS modals into sheets", () => {
    for (const name of ["cfs", "contact"]) {
      const start = template.indexOf(`<div id="${name}-modal"`);
      const modal = template.slice(start, template.indexOf(`id="${name}-modal-root"`, start));

      expect(modal).to.include('<div class="modal-panel p-4 max-w-2xl phone:p-0">');
      expect(modal).to.include('<div class="modal-card sheet-panel rounded-lg">');
      expect(modal).to.include('class="sheet-head sheet-grab flex items-center');
    }
  });
});

describe("map macro phone template", () => {
  it("shows the long pill, hides the short one and turns the modal into a sheet", async () => {
    const template = normalizeWhitespace(await loadTemplate("/ocg-server/templates/macros/maps.html"));

    // Verify the long pill shows and wraps, in the preview and in the sheet.
    expect(
      template.match(
        /phone:block phone:max-w-\[calc\(100%-1rem\)\] phone:rounded-lg phone:whitespace-normal phone:wrap-anywhere/g,
      ),
    ).to.have.length(2);

    // Verify the short pill hides in both places.
    expect(template.match(/xl:hidden phone:hidden/g)).to.have.length(2);

    // Verify the sheet classes.
    expect(template).to.include('<div class="modal-card sheet-panel rounded-lg">');
    expect(template).to.include('<div class="sheet-head sheet-grab flex items-center');
    expect(template).to.include("phone:h-[60dvh]");

    // Verify a long title truncates instead of squeezing the 44px close button.
    expect(template).to.include("phone:min-w-0 phone:truncate");
    expect(template).to.include("inline-flex justify-center items-center phone:shrink-0");
  });
});
