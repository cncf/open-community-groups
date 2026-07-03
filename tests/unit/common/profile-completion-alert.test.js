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
    document.body.innerHTML = `
      <section data-profile-complete="false">
        <button type="button">Attend event</button>
      </section>
    `;

    expect(shouldPromptForProfileCompletion(document.querySelector("button"))).to.equal(true);
  });

  it("does not prompt without an incomplete profile marker", () => {
    document.body.innerHTML = '<button type="button">Attend event</button>';

    expect(shouldPromptForProfileCompletion(document.querySelector("button"))).to.equal(false);
  });

  it("navigates to the profile when confirmed", async () => {
    document.body.innerHTML = `
      <section data-profile-complete="false">
        <button type="button">Submit session proposal</button>
      </section>
    `;
    const navigationCalls = [];

    const shown = showProfileCompletionAlert({
      trigger: document.querySelector("button"),
      navigateTo: (url) => navigationCalls.push(url),
    });
    await waitForMicrotask();

    expect(shown).to.equal(true);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].title).to.equal("Make your profile yours");
    expect(swal.calls[0].confirmButtonText).to.equal("Complete profile");
    expect(swal.calls[0].cancelButtonText).to.equal("Continue anyway");
    expect(navigationCalls).to.deep.equal([PROFILE_COMPLETION_URL]);
  });

  it("shows without controlling the original action when dismissed", () => {
    document.body.innerHTML = `
      <section data-profile-complete="false">
        <button type="button">Join waiting list</button>
      </section>
    `;
    swal.setNextResult({ isConfirmed: false });

    const shown = showProfileCompletionAlert({
      trigger: document.querySelector("button"),
    });

    expect(shown).to.equal(true);
  });

  it("shows action feedback with a profile completion CTA", async () => {
    document.body.innerHTML = `
      <section data-profile-complete="false">
        <button type="button">Attend event</button>
      </section>
    `;
    const navigationCalls = [];

    const shown = showProfileCompletionFeedbackAlert({
      trigger: document.querySelector("button"),
      message: "You have successfully registered for this event.",
      navigateTo: (url) => navigationCalls.push(url),
    });
    await waitForMicrotask();

    expect(shown).to.equal(true);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].title).to.equal("You have successfully registered for this event.");
    expect(swal.calls[0].confirmButtonText).to.equal("Complete profile");
    expect(swal.calls[0].cancelButtonText).to.equal("Maybe later");
    expect(navigationCalls).to.deep.equal([PROFILE_COMPLETION_URL]);
  });
});
