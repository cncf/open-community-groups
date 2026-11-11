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

    // The avatar repeats the visible name, so it is hidden from assistive tech.
    expect(element.querySelector("logo-image")?.getAttribute("aria-hidden")).to.equal("true");
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
    element.querySelector("button")?.click();

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

  it("renders a native dialog trigger named after the person", async () => {
    // Mount a clickable chip with a job title.
    const element = await mountLitComponent("user-chip", {
      user: {
        name: "Margaret Hamilton",
        title: "Software Engineer",
        username: "margaret",
      },
      displayModal: true,
    });

    // The chip is a native button that announces the profile dialog.
    const trigger = element.querySelector("button");
    expect(trigger?.getAttribute("type")).to.equal("button");
    expect(trigger?.getAttribute("aria-haspopup")).to.equal("dialog");

    // Its content names it, so no role, tabindex or aria-label overrides it.
    expect(trigger?.hasAttribute("role")).to.equal(false);
    expect(trigger?.hasAttribute("tabindex")).to.equal(false);
    expect(trigger?.hasAttribute("aria-label")).to.equal(false);
    expect(trigger?.textContent).to.include("View profile:");
    expect(trigger?.textContent).to.include("Margaret Hamilton");
    expect(trigger?.textContent).to.include("Software Engineer");
  });

  it("renders a static card without a button or tabindex when the modal is off", async () => {
    // Mount a card and a compact chip without the modal.
    const card = await mountLitComponent("user-chip", {
      user: { name: "Radia Perlman", username: "radia" },
    });
    const featuredCard = await mountLitComponent("user-chip", {
      user: { name: "Grace Hopper", username: "grace" },
      featured: true,
    });
    const chip = await mountLitComponent("user-chip", {
      user: { name: "Ada Lovelace", username: "ada" },
      small: true,
    });

    // No variant is focusable, exposed as a control or pressable.
    for (const element of [card, featuredCard, chip]) {
      expect(element.querySelector("button")).to.equal(null);
      expect(element.querySelector("[tabindex], [role], [aria-label]")).to.equal(null);
      expect(element.textContent).to.not.include("View profile:");
      expect(element.firstElementChild?.className).to.not.include("phone:active:");
    }
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

  it("shows a phone-only chevron only on clickable cards", async () => {
    const clickable = await mountLitComponent("user-chip", {
      user: { name: "Grace Hopper", username: "grace" },
      displayModal: true,
    });
    const plain = await mountLitComponent("user-chip", {
      user: { name: "Radia Perlman", username: "radia" },
    });
    const small = await mountLitComponent("user-chip", {
      user: { name: "Ada Lovelace", username: "ada" },
      displayModal: true,
      small: true,
    });

    // The chevron is hidden off phones and from assistive technology.
    const chevron = clickable.querySelector(".icon-arrow-right");
    expect(chevron?.classList.contains("not-phone:hidden")).to.equal(true);
    expect(chevron?.classList.contains("bg-stone-400")).to.equal(true);
    expect(chevron?.getAttribute("aria-hidden")).to.equal("true");

    // Plain cards open nothing, and chips stay compact.
    expect(plain.querySelector(".icon-arrow-right")).to.equal(null);
    expect(small.querySelector(".icon-arrow-right")).to.equal(null);
  });

  it("tightens the default card on phones without touching its desktop tokens", async () => {
    const element = await mountLitComponent("user-chip", {
      user: { name: "Grace Hopper", title: "Rear Admiral", username: "grace" },
      displayModal: true,
    });

    const card = element.firstElementChild;
    const title = [...element.querySelectorAll("div")].find((node) => node.textContent === "Rear Admiral");

    // Verify the phone tokens sit beside the unchanged desktop ones.
    for (const token of ["px-4", "py-3", "gap-4", "phone:min-h-16", "phone:px-3", "phone:py-2.5", "phone:gap-3"]) {
      expect(card.classList.contains(token), token).to.equal(true);
    }
    expect(card.classList.contains("phone:active:border-primary-300")).to.equal(true);
    expect(title?.classList.contains("mt-3")).to.equal(true);
    expect(title?.classList.contains("phone:mt-0.5")).to.equal(true);
    expect(card.classList.contains("phone:[&>logo-image>div]:size-12")).to.equal(true);
    expect(element.querySelector("logo-image")?.getAttribute("size")).to.equal("size-15 md:size-18");
  });

  it("keeps the featured card's amber frame and larger avatar on phones", async () => {
    const element = await mountLitComponent("user-chip", {
      user: { name: "Radia Perlman", username: "radia" },
      displayModal: true,
      featured: true,
    });

    const card = element.firstElementChild;

    // Verify the shared phone layout keeps the featured look, with no extra star.
    expect(card.classList.contains("phone:px-3")).to.equal(true);
    expect(card.classList.contains("border-amber-200")).to.equal(true);
    expect(card.classList.contains("phone:active:border-amber-500")).to.equal(true);
    expect(card.classList.contains("phone:[&>logo-image>div]:size-12")).to.equal(false);
    expect(element.querySelector("logo-image")?.getAttribute("size")).to.equal("size-18 md:size-22");
    expect(element.querySelector(".icon-star")).to.equal(null);
  });

  it("extends the small chip's hit area on phones only", async () => {
    const element = await mountLitComponent("user-chip", {
      user: { name: "Grace Hopper", username: "grace" },
      displayModal: true,
      small: true,
    });

    const chip = element.firstElementChild;

    // Verify the hit area comes from a phone pseudo-element, which moves no layout.
    for (const token of ["phone:relative", "phone:after:absolute", "phone:after:inset-x-0", "phone:after:-inset-y-1.5"]) {
      expect(chip.classList.contains(token), token).to.equal(true);
    }
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
