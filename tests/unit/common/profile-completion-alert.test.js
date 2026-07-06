import { expect } from "@open-wc/testing";

import {
  initializeLoginProfileCompletionPrompt,
  PROFILE_COMPLETION_URL,
  showLoginProfileCompletionAlert,
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
    sessionStorage.clear();
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
    expect(swal.calls[0].title).to.equal("Complete your profile");
    expect(swal.calls[0].text).to.equal(
      "Complete your profile so organizers and community members can learn more about you.",
    );
    expect(swal.calls[0].confirmButtonText).to.equal("Complete profile");
    expect(swal.calls[0].cancelButtonText).to.equal("Continue anyway");
    expect(swal.calls[0].position).to.equal("center");
    expect(swal.calls[0].backdrop).to.equal(true);
    expect(swal.calls[0].allowOutsideClick).to.equal(false);
    expect(swal.calls[0].allowEscapeKey).to.equal(false);
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
    expect(swal.calls[0].text).to.equal(
      "Complete your profile so organizers and community members can learn more about you.",
    );
    expect(swal.calls[0].confirmButtonText).to.equal("Complete profile");
    expect(swal.calls[0].cancelButtonText).to.equal("Maybe later");
    expect(swal.calls[0].position).to.equal("center");
    expect(swal.calls[0].backdrop).to.equal(true);
    expect(swal.calls[0].allowOutsideClick).to.equal(false);
    expect(swal.calls[0].allowEscapeKey).to.equal(false);
    expect(swal.calls[0].customClass.popup).to.include("ocg-profile-feedback-swal");
    expect(navigationCalls).to.deep.equal([PROFILE_COMPLETION_URL]);
  });

  it("shows a top-right profile completion prompt after login", async () => {
    // Render a signed-in header with an incomplete profile.
    document.body.innerHTML = `
      <button id="user-dropdown-button" data-logged-in="true" data-profile-complete="false" type="button"></button>
    `;
    const navigationCalls = [];

    // Show the login follow-up alert and resolve the mocked confirmation.
    const shown = showLoginProfileCompletionAlert({
      navigateTo: (url) => navigationCalls.push(url),
    });
    await waitForMicrotask();

    // Verify the alert keeps the success-toast placement and only one CTA.
    expect(shown).to.equal(true);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].title).to.equal("Complete your profile");
    expect(swal.calls[0].text).to.equal(
      "Complete your profile so organizers and community members can learn more about you.",
    );
    expect(swal.calls[0].confirmButtonText).to.equal("Complete profile");
    expect(swal.calls[0].showCancelButton).to.equal(false);
    expect(swal.calls[0].position).to.equal("top-end");
    expect(swal.calls[0].backdrop).to.equal(false);
    expect(swal.calls[0].timer).to.equal(5000);
    expect(navigationCalls).to.deep.equal([PROFILE_COMPLETION_URL]);
  });

  it("shows the login prompt only after a login attempt", () => {
    // Render the email login form and record a submit attempt.
    document.body.innerHTML = `
      <form action="/log-in?next_url=%2Fevents" method="post"></form>
    `;
    initializeLoginProfileCompletionPrompt();
    document.querySelector("form").dispatchEvent(new Event("submit", { bubbles: true }));

    // Render the next signed-in page with an incomplete profile.
    swal.setNextResult({ isConfirmed: false });
    document.body.innerHTML = `
      <button id="user-dropdown-button" data-logged-in="true" data-profile-complete="false" type="button"></button>
    `;
    initializeLoginProfileCompletionPrompt();

    // Verify the login-only prompt is shown once after the login attempt.
    expect(swal.calls).to.have.length(1);
    initializeLoginProfileCompletionPrompt();
    expect(swal.calls).to.have.length(1);
  });

  it("does not show the login prompt after login when the profile is complete", () => {
    // Render the OAuth login link and record a click attempt.
    document.body.innerHTML = `
      <a href="/log-in/oauth2/github?next_url=%2Fevents">GitHub</a>
    `;
    initializeLoginProfileCompletionPrompt();
    document.querySelector("a").dispatchEvent(new Event("click", { bubbles: true }));

    // Render the next signed-in page with a complete profile.
    document.body.innerHTML = `
      <button id="user-dropdown-button" data-logged-in="true" data-profile-complete="true" type="button"></button>
    `;
    initializeLoginProfileCompletionPrompt();

    // Verify the login-only prompt is consumed without showing an alert.
    expect(swal.calls).to.have.length(0);
  });
});
