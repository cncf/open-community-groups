import { expect } from "@open-wc/testing";

import {
  PROFILE_COMPLETION_URL,
  showProfileCompletionAlert,
  showProfileCompletionFeedbackAlert,
  shouldPromptForProfileCompletion,
} from "/static/js/common/profile-completion-alert.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("profile completion alert", () => {
  let swal;

  beforeEach(() => {
    swal = mockSwal();
  });

  afterEach(() => {
    swal.restore();
    resetDom();
  });

  it("prompts when the action belongs to an incomplete profile flow", () => {
    // Render an action inside an incomplete profile marker.
    document.body.innerHTML = `
      <section data-profile-complete="false">
        <button type="button">Attend event</button>
      </section>
    `;

    // Verify the action is eligible for the profile completion prompt.
    expect(shouldPromptForProfileCompletion(document.querySelector("button"))).to.equal(true);
  });

  it("prompts when formatted profile state is incomplete", () => {
    // Render the formatted marker shape produced by template formatting.
    document.body.innerHTML = `
      <section data-profile-complete="
        false
      ">
        <button type="button">Attend event</button>
      </section>
    `;

    // Verify formatted marker whitespace does not suppress the prompt.
    expect(shouldPromptForProfileCompletion(document.querySelector("button"))).to.equal(true);
  });

  it("prompts signed-in public pages when the header profile is incomplete", () => {
    // Render a public page action with profile state from the user header.
    document.body.innerHTML = `
      <button id="user-dropdown-button" data-logged-in="true" data-profile-complete="false" type="button"></button>
      <section data-profile-complete="true">
        <button type="button">Attend event</button>
      </section>
    `;

    // Verify the signed-in header profile state takes precedence.
    expect(shouldPromptForProfileCompletion(document.querySelector("section button"))).to.equal(true);
  });

  it("does not prompt signed-in public pages when the header profile is complete", () => {
    // Render a stale public page marker with a complete profile in the header.
    document.body.innerHTML = `
      <button id="user-dropdown-button" data-logged-in="true" data-profile-complete="true" type="button"></button>
      <section data-profile-complete="false">
        <button type="button">Attend event</button>
      </section>
    `;

    // Verify the proper header profile state suppresses the prompt.
    expect(shouldPromptForProfileCompletion(document.querySelector("section button"))).to.equal(false);
  });

  it("does not prompt without an incomplete profile marker", () => {
    // Render an action without profile completion metadata.
    document.body.innerHTML = '<button type="button">Attend event</button>';

    // Verify plain actions are ignored by the profile completion prompt.
    expect(shouldPromptForProfileCompletion(document.querySelector("button"))).to.equal(false);
  });

  it("navigates to the profile when confirmed", async () => {
    // Render a profile-aware action and collect navigation requests.
    document.body.innerHTML = `
      <section data-profile-complete="false">
        <button type="button">Submit session proposal</button>
      </section>
    `;
    const navigationCalls = [];

    // Show the alert and resolve the mocked confirmation.
    const shown = showProfileCompletionAlert({
      trigger: document.querySelector("button"),
      navigateTo: (url) => navigationCalls.push(url),
    });
    await waitForMicrotask();

    // Verify the alert content and profile navigation target.
    expect(shown).to.equal(true);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].title).to.equal("Make your profile yours");
    expect(swal.calls[0].confirmButtonText).to.equal("Complete profile");
    expect(swal.calls[0].cancelButtonText).to.equal("Continue anyway");
    expect(swal.calls[0].position).to.equal("top-end");
    expect(swal.calls[0].backdrop).to.equal(false);
    expect(navigationCalls).to.deep.equal([PROFILE_COMPLETION_URL]);
  });

  it("shows without controlling the original action when dismissed", () => {
    // Render an incomplete profile action with a dismissed alert result.
    document.body.innerHTML = `
      <section data-profile-complete="false">
        <button type="button">Join waiting list</button>
      </section>
    `;
    swal.setNextResult({ isConfirmed: false });

    // Show the prompt without blocking the original action path.
    const shown = showProfileCompletionAlert({
      trigger: document.querySelector("button"),
    });

    // Verify the prompt is shown even when the CTA is dismissed.
    expect(shown).to.equal(true);
  });

  it("shows action feedback with a profile completion CTA", async () => {
    // Render a profile-aware action and collect CTA navigation requests.
    document.body.innerHTML = `
      <section data-profile-complete="false">
        <button type="button">Attend event</button>
      </section>
    `;
    const navigationCalls = [];

    // Show combined action feedback and profile completion CTA.
    const shown = showProfileCompletionFeedbackAlert({
      trigger: document.querySelector("button"),
      message: "You have successfully registered for this event.",
      navigateTo: (url) => navigationCalls.push(url),
    });
    await waitForMicrotask();

    // Verify the combined alert content and profile navigation target.
    expect(shown).to.equal(true);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].title).to.equal("You have successfully registered for this event.");
    expect(swal.calls[0].confirmButtonText).to.equal("Complete profile");
    expect(swal.calls[0].cancelButtonText).to.equal("Maybe later");
    expect(swal.calls[0].position).to.equal("top-end");
    expect(swal.calls[0].backdrop).to.equal(false);
    expect(navigationCalls).to.deep.equal([PROFILE_COMPLETION_URL]);
  });
});
