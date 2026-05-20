import { expect } from "@open-wc/testing";

import "/static/js/common/user-chip.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent } from "/tests/unit/test-utils/lit.js";

describe("user-chip", () => {
  afterEach(() => {
    resetDom();
  });

  it("renders nothing when no user is provided", async () => {
    // Render the user-chip fixture.
    const element = await mountLitComponent("user-chip");

    // Renders nothing when no user is provided.
    expect(element.children.length).to.equal(0);
  });

  it("parses a json user payload and renders the display name", async () => {
    // Render the user-chip fixture.
    const element = await mountLitComponent("user-chip", {
      user: JSON.stringify({
        name: "Ada Lovelace",
        username: "ada",
        title: "Mathematician",
        photo_url: "https://example.com/ada.png",
      }),
    });

    // Parsed a json user payload and renders the display name.
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

    // Set up dispatches the user modal event on click when display-modal is enabled.
    let eventDetail = null;
    element.addEventListener("open-user-modal", (event) => {
      eventDetail = event.detail;
    });

    // Click the control and verify the resulting state.
    element.querySelector('[role="button"]')?.click();

    // Dispatches the user modal event on click when display-modal is enabled.
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
    // Render the user-chip fixture.
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

    // Opened the modal from keyboard interactions when clickable.
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
    expect(element.querySelector(".icon-star")).to.not.equal(null);
    expect(element.textContent).to.include("Radia Perlman");
  });
});
