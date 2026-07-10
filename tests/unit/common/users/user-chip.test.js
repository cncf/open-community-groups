import { expect } from "@open-wc/testing";

import "/static/js/common/users/user-chip.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent } from "/tests/unit/test-utils/lit.js";

describe("user-chip", () => {
  afterEach(() => {
    resetDom();
  });

  it("renders nothing when no user is provided", async () => {
    // Mount the chip without user data.
    const element = await mountLitComponent("user-chip");

    // The empty chip renders no light DOM content.
    expect(element.children.length).to.equal(0);
  });

  it("parses a json user payload and renders the display name", async () => {
    // Mount the chip with a serialized user payload.
    const element = await mountLitComponent("user-chip", {
      user: JSON.stringify({
        name: "Ada Lovelace",
        username: "ada",
        title: "Mathematician",
        photo_url: "https://example.com/ada.png",
      }),
    });

    // The display name, title, and initials come from the parsed payload.
    expect(element.textContent).to.include("Ada Lovelace");
    expect(element.textContent).to.include("Mathematician");
    expect(
      element.querySelector("logo-image")?.getAttribute("placeholder"),
    ).to.equal("AL");
  });

  it("dispatches the user modal event on click when display-modal is enabled", async () => {
    // Render the user-chip fixture.
    const element = await mountLitComponent("user-chip", {
      user: {
        name: "Grace Hopper",
        username: "grace",
        title: "Rear Admiral",
        company: "US Navy",
        bio: "Compiler pioneer",
        photo_url: "https://example.com/grace.png",
        github_url: "https://github.com/grace",
        website_url: "https://example.com/grace",
      },
      displayModal: true,
      bioIsHtml: true,
    });

    // Capture the modal event emitted by the chip.
    let eventDetail = null;
    element.addEventListener("open-user-modal", (event) => {
      eventDetail = event.detail;
    });

    // Click the user chip.
    element.querySelector('[role="button"]')?.click();

    // The click emits the complete modal payload.
    expect(eventDetail).to.deep.equal({
      name: "Grace Hopper",
      username: "grace",
      imageUrl: "https://example.com/grace.png",
      jobTitle: "Rear Admiral",
      company: "US Navy",
      bio: "Compiler pioneer",
      bioIsHtml: true,
      blueskyUrl: undefined,
      facebookUrl: undefined,
      githubUrl: "https://github.com/grace",
      linkedinUrl: undefined,
      provider: undefined,
      twitterUrl: undefined,
      websiteUrl: "https://example.com/grace",
    });
  });

  it("opens the modal from keyboard interactions when clickable", async () => {
    // Mount a clickable chip before sending keyboard events.
    const element = await mountLitComponent("user-chip", {
      user: {
        name: "Margaret Hamilton",
        username: "margaret",
      },
      displayModal: true,
    });

    // List the fixture values.
    const openedBy = [];

    // Listen for the emitted event.
    element.addEventListener("open-user-modal", () => {
      openedBy.push("opened");
    });

    // Collect the card element.
    const card = element.querySelector('[role="button"]');
    card.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Enter", bubbles: true }),
    );
    card.dispatchEvent(
      new KeyboardEvent("keydown", { key: " ", bubbles: true }),
    );

    // Enter and Space both emit the modal event.
    expect(openedBy).to.deep.equal(["opened", "opened"]);
  });

  it("renders the compact featured variant", async () => {
    // Render the user-chip fixture.
    const element = await mountLitComponent("user-chip", {
      user: {
        name: "Radia Perlman",
        username: "radia",
      },
      small: true,
      featured: true,
    });

    // Set up renders the compact featured variant.
    const card = element.firstElementChild;

    // The rendered text shows the scenario data.
    expect(card?.className).to.include("bg-amber-50/50");
    expect(card?.classList.contains("hover:border-amber-400")).to.equal(false);
    expect(element.querySelector(".icon-star")).to.not.equal(null);
    expect(element.textContent).to.include("Radia Perlman");
  });

  it("renders the compact rollover variants without changing backgrounds", async () => {
    const regularElement = await mountLitComponent("user-chip", {
      user: {
        name: "Grace Hopper",
        username: "grace",
      },
      displayModal: true,
      small: true,
    });
    const featuredElement = await mountLitComponent("user-chip", {
      user: {
        name: "Radia Perlman",
        username: "radia",
      },
      displayModal: true,
      featured: true,
      small: true,
    });

    const regularCard = regularElement.firstElementChild;
    const featuredCard = featuredElement.firstElementChild;

    expect(regularCard?.classList.contains("hover:border-primary-300")).to.equal(true);
    expect(regularCard?.classList.contains("hover:shadow-sm")).to.equal(true);
    expect(regularCard?.className).to.not.include("hover:bg-");
    expect(featuredCard?.classList.contains("hover:border-amber-400")).to.equal(true);
    expect(featuredCard?.classList.contains("hover:shadow-sm")).to.equal(true);
    expect(featuredCard?.className).to.not.include("hover:bg-");
  });

  it("renders the card rollover variants", async () => {
    const regularElement = await mountLitComponent("user-chip", {
      user: {
        name: "Grace Hopper",
        username: "grace",
      },
      displayModal: true,
    });
    const featuredElement = await mountLitComponent("user-chip", {
      user: {
        name: "Radia Perlman",
        username: "radia",
      },
      displayModal: true,
      featured: true,
    });

    const regularCard = regularElement.firstElementChild;
    const featuredCard = featuredElement.firstElementChild;

    expect(
      regularCard?.classList.contains("hover:border-primary-300"),
    ).to.equal(true);
    expect(regularCard?.classList.contains("hover:shadow-sm")).to.equal(true);
    expect(regularCard?.className).to.not.include("hover:bg-");
    expect(
      featuredCard?.classList.contains("hover:border-amber-500"),
    ).to.equal(true);
    expect(featuredCard?.classList.contains("hover:shadow-sm")).to.equal(true);
    expect(featuredCard?.className).to.not.include("hover:bg-");
    expect(featuredCard?.classList.contains("shadow-sm")).to.equal(false);
  });
});
