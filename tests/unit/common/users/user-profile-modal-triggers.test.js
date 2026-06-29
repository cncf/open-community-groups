import { expect } from "@open-wc/testing";

import "/static/js/common/users/user-profile-modal-triggers.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("user profile modal triggers", () => {
  afterEach(() => {
    resetDom();
  });

  it("dispatches the shared user modal event from a delegated trigger", () => {
    // Render a dashboard-style profile trigger.
    const userProfile = JSON.stringify({
      name: "Ada Lovelace",
      username: "ada",
      title: "Mathematician",
      company: "Analytical Engines",
      bio: "First programmer",
      photo_url: "https://example.com/ada.png",
      github_url: "https://github.com/ada",
      website_url: "https://example.com/ada",
      provider: { github: { username: "ada-gh" } },
    });
    document.body.innerHTML = `
      <button
        type="button"
        data-user-profile-modal
        data-user-profile='${userProfile}'
      >
        Ada Lovelace
      </button>
    `;

    // Capture the delegated modal event.
    let eventDetail = null;
    document.addEventListener(
      "open-user-modal",
      (event) => {
        eventDetail = event.detail;
      },
      { once: true },
    );

    // Click through the delegated profile trigger.
    document.querySelector("[data-user-profile-modal]")?.click();

    // The event detail matches the user-info-modal contract.
    expect(eventDetail).to.deep.equal({
      name: "Ada Lovelace",
      username: "ada",
      imageUrl: "https://example.com/ada.png",
      jobTitle: "Mathematician",
      company: "Analytical Engines",
      bio: "First programmer",
      bioIsHtml: false,
      blueskyUrl: undefined,
      facebookUrl: undefined,
      githubUrl: "https://github.com/ada",
      linkedinUrl: undefined,
      provider: { github: { username: "ada-gh" } },
      twitterUrl: undefined,
      websiteUrl: "https://example.com/ada",
    });
  });

  it("ignores malformed profile payloads", () => {
    // Render a malformed trigger payload.
    document.body.innerHTML = `
      <button type="button" data-user-profile-modal data-user-profile="{bad json}">
        Broken
      </button>
    `;
    const opened = [];
    const handleOpen = () => opened.push("opened");
    document.addEventListener("open-user-modal", handleOpen);

    // Click the malformed trigger.
    document.querySelector("[data-user-profile-modal]")?.click();
    document.removeEventListener("open-user-modal", handleOpen);

    // Invalid JSON does not open the modal.
    expect(opened).to.deep.equal([]);
  });
});
