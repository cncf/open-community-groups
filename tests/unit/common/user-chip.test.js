import { expect } from "@open-wc/testing";

import "/static/js/common/user-chip.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent } from "/tests/unit/test-utils/lit.js";

describe("user-chip", () => {
  afterEach(() => {
    resetDom();
  });

  it("renders nothing when no user is provided", async () => {
    const element = await mountLitComponent("user-chip");

    expect(element.children.length).to.equal(0);
  });

  it("parses a json user payload and renders the display name", async () => {
    const element = await mountLitComponent("user-chip", {
      user: JSON.stringify({
        name: "Ada Lovelace",
        username: "ada",
        title: "Mathematician",
        photo_url: "https://example.com/ada.png",
      }),
    });

    expect(element.textContent).to.include("Ada Lovelace");
    expect(element.textContent).to.include("Mathematician");
    expect(element.querySelector("logo-image")?.getAttribute("placeholder")).to.equal("AL");
  });

  it("dispatches the user modal event on click when display-modal is enabled", async () => {
    const element = await mountLitComponent("user-chip", {
      user: {
        name: "Grace Hopper",
        username: "grace",
        title: "Rear Admiral",
        company: "US Navy",
        bio: "Compiler pioneer",
        photo_url: "https://example.com/grace.png",
        website_url: "https://example.com/grace",
      },
      displayModal: true,
      bioIsHtml: true,
    });

    let eventDetail = null;
    element.addEventListener("open-user-modal", (event) => {
      eventDetail = event.detail;
    });

    element.querySelector('[role="button"]')?.click();

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
      linkedinUrl: undefined,
      provider: undefined,
      twitterUrl: undefined,
      websiteUrl: "https://example.com/grace",
    });
  });

  it("opens the modal from keyboard interactions when clickable", async () => {
    const element = await mountLitComponent("user-chip", {
      user: {
        name: "Margaret Hamilton",
        username: "margaret",
      },
      displayModal: true,
    });

    const openedBy = [];

    element.addEventListener("open-user-modal", () => {
      openedBy.push("opened");
    });

    const card = element.querySelector('[role="button"]');
    card.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
    card.dispatchEvent(new KeyboardEvent("keydown", { key: " ", bubbles: true }));

    expect(openedBy).to.deep.equal(["opened", "opened"]);
  });

  it("renders the compact featured variant", async () => {
    const element = await mountLitComponent("user-chip", {
      user: {
        name: "Radia Perlman",
        username: "radia",
      },
      small: true,
      featured: true,
    });

    const card = element.firstElementChild;

    expect(card?.className).to.include("bg-amber-50/50");
    expect(element.querySelector(".icon-star")).to.not.equal(null);
    expect(element.textContent).to.include("Radia Perlman");
  });
});
