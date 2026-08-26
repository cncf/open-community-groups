import { expect, waitUntil } from "@open-wc/testing";

import "/static/js/common/modals/user-info-modal.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("user-info-modal", () => {
  useMountedElementsCleanup("user-info-modal");
  let originalFetch;

  beforeEach(() => {
    originalFetch = window.fetch;
    window.fetch = async () => new Response("[]", { headers: { "Content-Type": "application/json" } });
  });

  afterEach(() => {
    window.fetch = originalFetch;
  });

  it("renders nothing while closed", async () => {
    // Mount the modal without opening it.
    const element = await mountLitComponent("user-info-modal");

    // The closed modal has no light DOM content.
    expect(element.children.length).to.equal(0);
  });

  it("opens when an open-user-modal event is dispatched", async () => {
    // Mount the modal before dispatching the document event.
    const element = await mountLitComponent("user-info-modal");

    // Dispatch the open-user-modal event.
    document.dispatchEvent(
      new CustomEvent("open-user-modal", {
        bubbles: true,
        detail: {
          name: "Grace Hopper",
          username: "grace",
          imageUrl: "https://example.com/grace.png",
          jobTitle: "Rear Admiral",
          company: "US Navy",
          bio: "Compiler pioneer",
        },
      }),
    );
    await element.updateComplete;

    // The modal renders the user details from the event payload.
    expect(element._isOpen).to.equal(true);
    expect(element.querySelector('[role="dialog"]')).to.not.equal(null);
    expect(element.querySelector(".modal-panel").classList.contains("max-w-3xl")).to.equal(true);
    expect(element.textContent).to.include("Grace Hopper");
    expect(element.textContent).to.include("Rear Admiral at US Navy");
    expect(document.body.style.overflow).to.equal("hidden");
  });

  it("renders social links and the openprofile.dev link when available", async () => {
    // Render the user-info-modal fixture.
    const element = await mountLitComponent("user-info-modal");

    // Dispatch the open-user-modal event.
    document.dispatchEvent(
      new CustomEvent("open-user-modal", {
        bubbles: true,
        detail: {
          name: "Ada Lovelace",
          username: "ada",
          websiteUrl: "https://example.com",
          linkedinUrl: "https://linkedin.com/in/ada",
          githubUrl: "https://github.com/ada",
          provider: {
            linuxfoundation: {
              username: "ada-lf",
            },
          },
        },
      }),
    );
    await element.updateComplete;

    // Read normalized social links after opening the profile modal.
    const links = element._getSocialLinks();

    // Social links include the supported profile URLs.
    expect(links).to.deep.equal([
      { url: "https://example.com/", icon: "website", label: "Website" },
      {
        url: "https://linkedin.com/in/ada",
        icon: "linkedin",
        label: "LinkedIn",
      },
      { url: "https://github.com/ada", icon: "github", label: "GitHub" },
    ]);
    expect(element.querySelector('a[href="https://openprofile.dev/profile/ada-lf"]')).to.not.equal(null);
    expect(element.querySelector('a[aria-label="Website"]')).to.not.equal(null);
    expect(element.querySelector('a[aria-label="LinkedIn"]')).to.not.equal(null);
    expect(element.querySelector('a[aria-label="GitHub"]')).to.not.equal(null);
  });

  it("omits social links with unsafe URL schemes", async () => {
    // Mount the modal before dispatching profile data.
    const element = await mountLitComponent("user-info-modal");

    // Open the modal with one unsafe and one valid social URL.
    document.dispatchEvent(
      new CustomEvent("open-user-modal", {
        detail: {
          name: "Ada Lovelace",
          username: "ada",
          websiteUrl: "javascript:alert(1)",
          githubUrl: "https://github.com/ada",
        },
      }),
    );
    await element.updateComplete;

    // Verify only the valid social link is rendered.
    expect(element.querySelector('a[aria-label="Website"]')).to.equal(null);
    expect(element.querySelector('a[aria-label="GitHub"]')).to.not.equal(null);
  });

  it("shows the profile placeholder when the user has no bio or social links", async () => {
    // Render the user-info-modal fixture.
    const element = await mountLitComponent("user-info-modal");

    // Dispatch the open-user-modal event.
    document.dispatchEvent(
      new CustomEvent("open-user-modal", {
        bubbles: true,
        detail: {
          name: "Margaret Hamilton",
          username: "margaret",
          bio: "   ",
        },
      }),
    );
    await element.updateComplete;

    // The rendered text shows the scenario data.
    expect(element.textContent).to.include("Profile not completed");
    expect(element.textContent).to.include("This user hasn’t finished setting up their profile yet.");
  });

  it("closes from escape and overlay interactions", async () => {
    // Render the user-info-modal fixture.
    const element = await mountLitComponent("user-info-modal");

    // Dispatch the open-user-modal event.
    document.dispatchEvent(
      new CustomEvent("open-user-modal", {
        bubbles: true,
        detail: {
          name: "Radia Perlman",
          username: "radia",
        },
      }),
    );
    await element.updateComplete;

    // Escape closes the modal and restores body scrolling.
    element._handleKeydown({
      key: "Escape",
      preventDefault() {},
    });
    await element.updateComplete;

    // The modal is closed after Escape.
    expect(element._isOpen).to.equal(false);
    expect(document.body.style.overflow).to.equal("");

    // Reopen the modal before checking the overlay close path.
    document.dispatchEvent(
      new CustomEvent("open-user-modal", {
        bubbles: true,
        detail: {
          name: "Radia Perlman",
          username: "radia",
        },
      }),
    );
    await element.updateComplete;

    // Overlay clicks close the reopened modal.
    element._handleOutsideClick({
      target: {
        classList: {
          contains(value) {
            return value === "modal-overlay";
          },
        },
      },
    });
    await element.updateComplete;

    // The modal is closed after the overlay interaction.
    expect(element._isOpen).to.equal(false);
  });

  it("lazily renders active listed badges with accessible links and image text", async () => {
    let requestUrl = "";
    window.fetch = async (url) => {
      requestUrl = String(url);
      return new Response(
        JSON.stringify([
          {
            awarded_at: "2024-01-01T00:00:00Z",
            group_id: "00000000-0000-0000-0000-000000000001",
            snapshot: {
              criteria: "Attend",
              image_file_name: "participant.png",
              issuer: {
                community_id: "00000000-0000-0000-0000-000000000002",
                community_name: "Cloud Native",
                group_id: "00000000-0000-0000-0000-000000000001",
                group_name: "Kubernetes Group",
              },
              name: "Participant",
            },
            user_badge_id: "00000000-0000-0000-0000-000000000003",
          },
          {
            awarded_at: "2024-01-02T00:00:00Z",
            group_id: "00000000-0000-0000-0000-000000000004",
            snapshot: {
              criteria: "Contribute",
              image_file_name: "group.png",
              issuer: {
                group_id: "00000000-0000-0000-0000-000000000004",
                group_name: "Solo Group",
              },
              name: "Contributor",
            },
            user_badge_id: "00000000-0000-0000-0000-000000000005",
          },
        ]),
        { headers: { "Content-Type": "application/json" } },
      );
    };
    const element = await mountLitComponent("user-info-modal");

    document.dispatchEvent(
      new CustomEvent("open-user-modal", {
        detail: { name: "Ada", username: "ada" },
      }),
    );
    await waitUntil(() => element._badgesState === "ready", "profile badges should load");
    await element.updateComplete;

    expect(requestUrl).to.equal("/users/ada/badges");
    const badgeSection = element.querySelector("#profile-badges-title").closest("section");
    expect(badgeSection.classList.contains("border-t")).to.equal(true);
    const link = element.querySelector('a[href="/badges/credentials/00000000-0000-0000-0000-000000000003"]');
    expect(link.getAttribute("aria-label")).to.equal("View Participant badge credential");
    expect(link.querySelector("img").getAttribute("alt")).to.equal("Participant badge artwork");
    expect(link.classList.contains("size-16")).to.equal(true);
    expect(link.classList.contains("sm:size-24")).to.equal(true);
    const badgeDetails = link.querySelector('[role="tooltip"]');
    expect(link.getAttribute("aria-describedby")).to.equal(badgeDetails.id);
    expect(badgeDetails.classList.contains("group-hover:visible")).to.equal(true);
    expect(badgeDetails.classList.contains("group-focus-visible:visible")).to.equal(true);
    expect(badgeDetails.classList.contains("w-72")).to.equal(true);
    expect(badgeDetails.textContent).to.include("Participant");
    expect(badgeDetails.textContent).to.include("Kubernetes Group");
    expect(badgeDetails.textContent).to.include("Cloud Native");
    const groupOnlyDetails = element
      .querySelector('a[href="/badges/credentials/00000000-0000-0000-0000-000000000005"]')
      .querySelector('[role="tooltip"]');
    expect(groupOnlyDetails.textContent).to.include("Solo Group");
    expect(groupOnlyDetails.textContent).to.not.include("·");
    const tooltipPointer = badgeDetails.querySelector('[aria-hidden="true"].rotate-45');
    expect(tooltipPointer).to.not.equal(null);

    element._userData = { ...element._userData, websiteUrl: "https://example.com" };
    await element.updateComplete;

    expect(
      element.querySelector("#profile-badges-title").closest("section").classList.contains("border-t"),
    ).to.equal(false);
  });

  it("omits the badge section when no badges are listed", async () => {
    window.fetch = async () => new Response("[]", { headers: { "Content-Type": "application/json" } });
    const element = await mountLitComponent("user-info-modal");

    document.dispatchEvent(
      new CustomEvent("open-user-modal", {
        detail: { name: "Ada", username: "ada" },
      }),
    );
    await Promise.resolve();
    await Promise.resolve();
    await element.updateComplete;

    expect(element.querySelector("#profile-badges-title")).to.equal(null);
  });

  it("shows a recoverable state when profile badges cannot be loaded", async () => {
    window.fetch = async () => new Response("Unavailable", { status: 503 });
    const element = await mountLitComponent("user-info-modal");

    document.dispatchEvent(
      new CustomEvent("open-user-modal", {
        detail: { name: "Ada", username: "ada" },
      }),
    );
    await waitUntil(() => element._badgesState === "error", "profile badge failure should render");
    await element.updateComplete;

    expect(element.textContent).to.include("Profile badges are temporarily unavailable");
    expect(element.querySelector('[role="status"]')).to.not.equal(null);
  });

  it("ignores an older badge response after opening a user without lookup context", async () => {
    let resolveBadges;
    window.fetch = () =>
      new Promise((resolve) => {
        resolveBadges = resolve;
      });
    const element = await mountLitComponent("user-info-modal");

    document.dispatchEvent(
      new CustomEvent("open-user-modal", {
        detail: { name: "Ada", username: "ada" },
      }),
    );
    await waitUntil(() => Boolean(resolveBadges), "the first profile badge request should start");
    document.dispatchEvent(new CustomEvent("open-user-modal", { detail: { name: "Anonymous" } }));
    resolveBadges(
      new Response(JSON.stringify([{ user_badge_id: "stale", snapshot: { name: "Stale" } }]), {
        headers: { "Content-Type": "application/json" },
      }),
    );
    await Promise.resolve();
    await Promise.resolve();
    await element.updateComplete;

    expect(element._badgesState).to.equal("empty");
    expect(element._badges).to.deep.equal([]);
  });
});
