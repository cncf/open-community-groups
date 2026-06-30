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
      provider: { linuxfoundation: { username: "ada-lf" } },
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
      provider: { linuxfoundation: { username: "ada-lf" } },
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

  it("does not dispatch duplicate modal events from initialized fragments", () => {
    // Render an HTMX-style fragment with a profile trigger.
    document.body.innerHTML = `
      <div id="fragment">
        <button
          type="button"
          data-user-profile-modal
          data-user-profile='{"name":"Grace Hopper","username":"grace"}'
        >
          Grace Hopper
        </button>
      </div>
    `;
    const fragment = document.querySelector("#fragment");
    const opened = [];
    document.addEventListener("open-user-modal", (event) => {
      opened.push(event.detail.name);
    });

    // Initialize the fragment as an HTMX-loaded root and click its trigger.
    fragment.dispatchEvent(
      new CustomEvent("htmx:load", {
        detail: {},
        bubbles: true,
      }),
    );
    fragment.querySelector("[data-user-profile-modal]")?.click();

    // The fragment listener handles the click once before the document listener.
    expect(document.querySelectorAll("user-info-modal").length).to.equal(1);
    expect(opened).to.deep.equal(["Grace Hopper"]);
  });
});
