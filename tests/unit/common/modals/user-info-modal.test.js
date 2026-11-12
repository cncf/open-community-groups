import { expect, waitUntil } from "@open-wc/testing";

import "/static/js/common/modals/user-info-modal.js";
import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";
import { stubMatchMedia } from "/tests/unit/test-utils/media.js";

/** Close watcher double that records its instances. */
class FakeCloseWatcher extends EventTarget {
  static instances = [];

  destroyCount = 0;

  constructor() {
    super();
    FakeCloseWatcher.instances.push(this);
  }

  destroy() {
    this.destroyCount += 1;
  }
}

/**
 * Opens the profile through the document event.
 * @param {HTMLElement} element Modal element.
 * @param {object} [detail] Event detail.
 * @returns {Promise<void>} Resolves after Lit renders.
 */
const openProfile = async (element, detail = { name: "Grace Hopper", username: "grace" }) => {
  document.dispatchEvent(new CustomEvent("open-user-modal", { bubbles: true, detail }));
  await element.updateComplete;
};

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

  describe("bottom sheet", () => {
    const originalCloseWatcher = window.CloseWatcher;
    let media;
    let panelStyle;

    /**
     * Sets the phone query and lays the panel out, as the compiled CSS would.
     * @param {boolean} matches Phone query state.
     * @returns {void}
     */
    const useSheetFixture = (matches) => {
      media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: matches });
      panelStyle = document.createElement("style");
      panelStyle.textContent = ".sheet-panel { position: fixed; }";
      document.head.append(panelStyle);
    };

    beforeEach(() => {
      FakeCloseWatcher.instances = [];
      window.CloseWatcher = FakeCloseWatcher;
    });

    afterEach(() => {
      panelStyle?.remove();
      media?.restore();

      // Restore the original CloseWatcher after sheet tests.
      if (originalCloseWatcher) {
        window.CloseWatcher = originalCloseWatcher;
      } else {
        delete window.CloseWatcher;
      }
    });

    it("marks the panel, title row and body as a sheet", async () => {
      const element = await mountLitComponent("user-info-modal");

      await openProfile(element);

      // Verify the primitives sit beside the desktop modal classes.
      const panel = element.querySelector(".modal-card");
      expect(panel?.classList.contains("sheet-panel")).to.equal(true);
      expect(panel?.querySelector(".sheet-head.sheet-grab #user-info-modal-title")).to.not.equal(null);
      expect(panel?.querySelector(".modal-body")?.classList.contains("sheet-body")).to.equal(true);

      // The title stays in the head on phones, in full, and names the dialog.
      const title = element.querySelector("#user-info-modal-title");
      expect(title?.classList.contains("phone:sr-only")).to.equal(false);
      expect(title?.querySelector(".phone\\:inline")?.textContent).to.equal("User Information");
      expect(element.querySelector('[role="dialog"]')?.getAttribute("aria-labelledby")).to.equal(title?.id);

      // Phone sizes sit on the row, so logo-image's attributes stay as on desktop.
      const logo = element.querySelector("logo-image");
      expect(logo?.parentElement?.classList.contains("phone:[&>logo-image>div]:size-18")).to.equal(true);
      expect(logo?.getAttribute("size")).to.equal("size-16 sm:size-24");
      expect(logo?.getAttribute("font-size")).to.equal("text-xl sm:text-3xl");
    });

    it("keeps the placeholder and the social link size inside the sheet", async () => {
      const element = await mountLitComponent("user-info-modal");

      // A profile with no details shows the placeholder in the body.
      await openProfile(element);
      expect(element.querySelector(".sheet-body")?.textContent).to.include("Profile not completed");

      // A social link gets the 44px target.
      await openProfile(element, {
        name: "Grace Hopper",
        username: "grace",
        websiteUrl: "https://example.com",
      });
      const link = element.querySelector('a[aria-label="Website"]') ?? element.querySelector(".btn-secondary-anchor");
      expect(link?.classList.contains("phone:size-11")).to.equal(true);
    });

    it("shows the openprofile.dev link after the profile text on phones and in the title row elsewhere", async () => {
      const element = await mountLitComponent("user-info-modal");
      const provider = { linuxfoundation: { username: "ada-lf" } };

      /**
       * Returns the single phone link, after checking it and the title-row link.
       * @returns {HTMLAnchorElement} Phone link.
       */
      const getPhoneLink = () => {
        const headLink = element.querySelector('.sheet-head a[href*="openprofile.dev"]');
        expect(headLink?.classList.contains("btn-primary-outline-anchor")).to.equal(true);
        expect(headLink?.classList.contains("phone:hidden")).to.equal(true);

        const phoneLinks = element.querySelectorAll('.sheet-body a[href*="openprofile.dev"]');
        expect(phoneLinks).to.have.length(1);
        expect(phoneLinks[0].classList.contains("btn-primary-outline-anchor")).to.equal(true);
        expect(phoneLinks[0].classList.contains("pill-link")).to.equal(true);
        expect(phoneLinks[0].parentElement.classList.contains("not-phone:hidden")).to.equal(true);
        return phoneLinks[0];
      };

      // A bio is followed by the link.
      await openProfile(element, { bio: "Wrote the first program.", name: "Ada Lovelace", provider, username: "ada" });
      expect(getPhoneLink().parentElement.previousElementSibling?.textContent).to.include("Wrote the first program.");

      // Without a bio the link takes its place, above the social links.
      await openProfile(element, {
        name: "Ada Lovelace",
        provider,
        username: "ada",
        websiteUrl: "https://example.com",
      });
      expect(getPhoneLink().parentElement.nextElementSibling?.textContent).to.include("Connect");

      // An empty profile shows the link inside the placeholder.
      await openProfile(element, { name: "Ada Lovelace", provider, username: "ada" });
      expect(getPhoneLink().parentElement.parentElement?.textContent).to.include("Profile not completed");

      // A profile without a Linux Foundation account renders neither link.
      await openProfile(element, { name: "Grace Hopper", username: "grace" });
      expect(element.querySelector('a[href*="openprofile.dev"]')).to.equal(null);
    });

    it("binds gestures after Lit renders and closes through the real button", async () => {
      useSheetFixture(true);
      const element = await mountLitComponent("user-info-modal");

      await openProfile(element);
      const panel = element.querySelector(".sheet-panel");
      expect(panel.hasAttribute("data-sheet-drag")).to.equal(true);
      expect(FakeCloseWatcher.instances).to.have.length(1);

      // A close request runs the modal's own close path.
      FakeCloseWatcher.instances[0].dispatchEvent(new Event("close"));
      await element.updateComplete;

      // Verify the modal closed and the watcher is gone.
      expect(element._isOpen).to.equal(false);
      expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(1);
      expect(document.body.style.overflow).to.equal("");
    });

    it("keeps one watcher across badge updates and rebinds after a second open", async () => {
      useSheetFixture(true);
      window.fetch = async () =>
        new Response("[]", { headers: { "Content-Type": "application/json" } });
      const element = await mountLitComponent("user-info-modal");

      // The badge load re-renders the open sheet.
      await openProfile(element);
      await waitUntil(() => element._badgesState === "empty");
      await element.updateComplete;
      expect(FakeCloseWatcher.instances).to.have.length(1);

      // A second open event releases the gestures, so the update binds them again.
      await openProfile(element, { name: "Ada Lovelace", username: "ada" });
      expect(FakeCloseWatcher.instances).to.have.length(2);
      expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(1);
      expect(element.querySelector(".sheet-panel").hasAttribute("data-sheet-drag")).to.equal(true);
    });

    it("releases gestures when the element disconnects while open", async () => {
      useSheetFixture(true);
      const element = await mountLitComponent("user-info-modal");

      await openProfile(element);
      element.remove();

      // Verify nothing outlives the element.
      expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(1);
      expect(element._removeSheetGestures).to.equal(null);
    });

    it("adds no gestures under a false phone query", async () => {
      useSheetFixture(false);
      const element = await mountLitComponent("user-info-modal");

      await openProfile(element);

      // Verify the modal opens exactly as it does on desktop.
      expect(element.querySelector(".sheet-panel").hasAttribute("data-sheet-drag")).to.equal(false);
      expect(FakeCloseWatcher.instances).to.have.length(0);
    });

    describe("focus", () => {
      const LF_PROFILE = { name: "Grace Hopper", provider: { linuxfoundation: { username: "grace" } }, username: "grace" };

      /**
       * Opens the profile from a host element that renders the real control, as a chip does.
       * @param {HTMLElement} element Modal element.
       * @param {object} [detail] Event detail.
       * @returns {Promise<HTMLElement>} The focusable control inside the host.
       */
      const openFromChip = async (element, detail) => {
        const chip = document.createElement("div");
        chip.innerHTML = '<div role="button" tabindex="0">Grace</div>';
        document.body.append(chip);
        chip.dispatchEvent(new CustomEvent("open-user-modal", { bubbles: true, composed: true, detail }));
        await element.updateComplete;
        return chip.firstElementChild;
      };

      /**
       * Presses a key on the document.
       * @param {string} key Key name.
       * @returns {void}
       */
      const press = (key) => {
        document.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key }));
      };

      afterEach(() => {
        document.querySelectorAll('[role="button"]').forEach((control) => control.parentElement.remove());
      });

      it("moves focus to Close and returns it to the chip on close", async () => {
        useSheetFixture(true);
        const element = await mountLitComponent("user-info-modal");

        const control = await openFromChip(element, { name: "Grace Hopper", username: "grace" });
        const close = element.querySelector('[aria-label="Close modal"]');
        expect(document.activeElement).to.equal(close);

        // Close through the real button.
        close.click();
        await element.updateComplete;

        expect(document.activeElement).to.equal(control);
      });

      it("enters at Close when the head renders a link before it", async () => {
        useSheetFixture(true);
        const element = await mountLitComponent("user-info-modal");

        await openFromChip(element, LF_PROFILE);

        // Verify the link really comes first.
        const panel = element.querySelector(".sheet-panel");
        expect(panel.querySelector("a, button").getAttribute("href")).to.include("openprofile.dev");
        expect(document.activeElement).to.equal(element.querySelector('[aria-label="Close modal"]'));
      });

      it("wraps Tab and restores focus on Escape", async () => {
        useSheetFixture(true);
        const element = await mountLitComponent("user-info-modal");
        const control = await openFromChip(element, { name: "Grace Hopper", username: "grace" });
        const close = element.querySelector('[aria-label="Close modal"]');

        // Tab from outside the sheet comes back in.
        control.focus();
        press("Tab");
        expect(element.querySelector(".sheet-panel").contains(document.activeElement)).to.equal(true);
        expect(document.activeElement).to.equal(close);

        // Escape closes and returns focus.
        press("Escape");
        await element.updateComplete;
        expect(document.activeElement).to.equal(control);
      });

      it("keeps the first opener across a second open event", async () => {
        useSheetFixture(true);
        const element = await mountLitComponent("user-info-modal");
        const control = await openFromChip(element, { name: "Grace Hopper", username: "grace" });

        await openProfile(element, { name: "Ada Lovelace", username: "ada" });
        element.querySelector('[aria-label="Close modal"]').click();
        await element.updateComplete;

        expect(document.activeElement).to.equal(control);
      });

      it("leaves focus and Tab alone under a false phone query", async () => {
        useSheetFixture(false);
        const element = await mountLitComponent("user-info-modal");

        const control = await openFromChip(element, { name: "Grace Hopper", username: "grace" });
        control.focus();
        press("Tab");
        expect(document.activeElement).to.equal(control);

        // A close leaves focus where it is.
        document.body.focus();
        control.blur();
        press("Escape");
        await element.updateComplete;
        expect(document.activeElement).to.not.equal(control);
      });
    });

    describe("back-forward cache", () => {
      /** Builds a pageshow event for a restored page. */
      const restoredPageShow = () => {
        const event = new Event("pageshow");
        Object.defineProperty(event, "persisted", { value: true });
        return event;
      };

      it("closes on a restore, so the next open shows the sheet", async () => {
        useSheetFixture(true);
        const element = await mountLitComponent("user-info-modal");
        await openProfile(element);

        // The shared restore hides the dialog before or after this listener.
        element.querySelector('[role="dialog"]').classList.add("hidden");
        window.dispatchEvent(restoredPageShow());
        await element.updateComplete;

        // Verify nothing is left armed.
        expect(element._isOpen).to.equal(false);
        expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(1);
        expect(document.body.style.overflow).to.equal("");

        // Verify the next open shows a fresh dialog.
        await openProfile(element);
        expect(element.querySelector('[role="dialog"]').classList.contains("hidden")).to.equal(false);
      });

      it("keeps the modal open on a restore under a false phone query", async () => {
        useSheetFixture(false);
        const element = await mountLitComponent("user-info-modal");
        await openProfile(element);

        window.dispatchEvent(restoredPageShow());
        await element.updateComplete;

        // Verify only phones change.
        expect(element._isOpen).to.equal(true);
      });
    });
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
