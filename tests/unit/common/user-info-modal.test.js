import { expect } from "@open-wc/testing";

import "/static/js/common/user-info-modal.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("user-info-modal", () => {
  useMountedElementsCleanup("user-info-modal");

  it("renders nothing while closed", async () => {
    const element = await mountLitComponent("user-info-modal");

    expect(element.children.length).to.equal(0);
  });

  it("opens when an open-user-modal event is dispatched", async () => {
    const element = await mountLitComponent("user-info-modal");

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

    expect(element._isOpen).to.equal(true);
    expect(element.querySelector('[role="dialog"]')).to.not.equal(null);
    expect(element.textContent).to.include("Grace Hopper");
    expect(element.textContent).to.include("Rear Admiral at US Navy");
    expect(document.body.style.overflow).to.equal("hidden");
  });

  it("renders social links and the openprofile.dev link when available", async () => {
    const element = await mountLitComponent("user-info-modal");

    document.dispatchEvent(
      new CustomEvent("open-user-modal", {
        bubbles: true,
        detail: {
          name: "Ada Lovelace",
          username: "ada",
          websiteUrl: "https://example.com",
          linkedinUrl: "https://linkedin.com/in/ada",
          provider: {
            linuxfoundation: {
              username: "ada-lf",
            },
          },
        },
      }),
    );
    await element.updateComplete;

    const links = element._getSocialLinks();

    expect(links).to.deep.equal([
      { url: "https://example.com", icon: "website", label: "Website" },
      { url: "https://linkedin.com/in/ada", icon: "linkedin", label: "LinkedIn" },
    ]);
    expect(element.querySelector('a[href="https://openprofile.dev/profile/ada-lf"]')).to.not.equal(null);
    expect(element.querySelector('a[aria-label="Website"]')).to.not.equal(null);
    expect(element.querySelector('a[aria-label="LinkedIn"]')).to.not.equal(null);
  });

  it("shows the profile placeholder when the user has no bio or social links", async () => {
    const element = await mountLitComponent("user-info-modal");

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

    expect(element.textContent).to.include("Profile not completed");
    expect(element.textContent).to.include("This user hasn’t finished setting up their profile yet.");
  });

  it("closes from escape and overlay interactions", async () => {
    const element = await mountLitComponent("user-info-modal");

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

    element._handleKeydown({
      key: "Escape",
      preventDefault() {},
    });
    await element.updateComplete;

    expect(element._isOpen).to.equal(false);
    expect(document.body.style.overflow).to.equal("");

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

    expect(element._isOpen).to.equal(false);
  });
});
