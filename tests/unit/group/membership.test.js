import { expect } from "@open-wc/testing";

import "/static/js/group/membership.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import {
  dispatchHtmxAfterRequest,
  dispatchHtmxBeforeRequest,
} from "/tests/unit/test-utils/htmx.js";

// Render the component fixture.
const renderMembershipDom = () => {
  document.body.innerHTML = `
    <div id="membership-container">
      <button id="membership-checker"></button>
      <button id="loading-btn" class="hidden">Loading</button>
      <button id="signin-btn" class="hidden" data-path="/groups/test-group">Sign in</button>
      <button id="join-btn" class="hidden">Join</button>
      <button id="leave-btn" class="hidden">Leave</button>
    </div>
  `;

  return {
    checker: document.getElementById("membership-checker"),
    loadingButton: document.getElementById("loading-btn"),
    signinButton: document.getElementById("signin-btn"),
    joinButton: document.getElementById("join-btn"),
    leaveButton: document.getElementById("leave-btn"),
  };
};

describe("group membership", () => {
  const env = useDashboardTestEnv({
    path: "/groups/test-group",
    withHtmx: true,
    withScroll: true,
    withSwal: true,
    bodyDatasetKeysToClear: ["membershipListenersReady"],
  });

  it("shows the leave action after a successful membership check", () => {
    // Read controls after a successful membership join.
    const { checker, leaveButton, signinButton, joinButton } =
      renderMembershipDom();

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ is_member: true }),
    });

    // Verify shows the leave action after a successful membership check.
    expect(leaveButton.classList.contains("hidden")).to.equal(false);
    expect(signinButton.classList.contains("hidden")).to.equal(true);
    expect(joinButton.classList.contains("hidden")).to.equal(true);
  });

  it("falls back to the sign-in action when the membership response is invalid", () => {
    // Keep references to the fixture controls under assertion.
    const { checker, signinButton, joinButton, leaveButton } =
      renderMembershipDom();

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: "{invalid json}",
    });

    // Verify falls back to the sign-in action when the membership response.
    expect(signinButton.classList.contains("hidden")).to.equal(false);
    expect(joinButton.classList.contains("hidden")).to.equal(true);
    expect(leaveButton.classList.contains("hidden")).to.equal(true);
  });

  it("shows loading state before a join request and restores the button on failure", () => {
    // Render the membership fixture.
    const { joinButton, loadingButton } = renderMembershipDom();

    // Dispatch the HTMX before-request event.
    dispatchHtmxBeforeRequest(joinButton);

    // Verify shows loading state before a join request and restores the button.
    expect(joinButton.classList.contains("hidden")).to.equal(true);
    expect(loadingButton.classList.contains("hidden")).to.equal(false);

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(joinButton, {
      status: 500,
    });

    // Verify shows loading state before a join request and restores the button.
    expect(joinButton.classList.contains("hidden")).to.equal(false);
    expect(loadingButton.classList.contains("hidden")).to.equal(true);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "Something went wrong joining this group. Please try again later.",
      icon: "error",
    });
    expect(env.current.scrollToMock.calls).to.deep.equal([]);
  });

  it("shows sign-in info and confirms leave actions", async () => {
    // Render the membership fixture.
    const { signinButton, leaveButton } = renderMembershipDom();

    // Verify shows sign-in info and confirms leave.
    signinButton.click();

    // Assert the captured calls.
    expect(env.current.swal.calls[0].icon).to.equal("info");
    expect(env.current.swal.calls[0].html).to.include(
      "/log-in?next_url=%2Fgroups%2Ftest-group",
    );

    // Confirm the leave action.
    env.current.swal.setNextResult({ isConfirmed: true });
    leaveButton.click();
    await waitForMicrotask();

    // Assert the captured calls.
    expect(env.current.swal.calls[1]).to.include({
      text: "Are you sure you want to leave this group?",
      icon: "warning",
    });
    expect(env.current.htmx.triggerCalls).to.deep.equal([
      ["#leave-btn", "confirmed"],
    ]);
  });

  it("handles membership clicks after the page body is swapped", () => {
    // Prepare replacement body for handling membership clicks after the page body.
    const replacementBody = document.createElement("body");
    document.documentElement.replaceChild(replacementBody, document.body);
    const { signinButton } = renderMembershipDom();

    // Membership clicks still work after the page body is swapped.
    signinButton.click();

    // Verify membership clicks work after the page body is swapped.
    expect(env.current.swal.calls[0].icon).to.equal("info");
    expect(env.current.swal.calls[0].html).to.include(
      "/log-in?next_url=%2Fgroups%2Ftest-group",
    );
  });

  it("escapes the sign-in return path in membership alerts", () => {
    // Render the membership fixture with a path that has query delimiters.
    const { signinButton } = renderMembershipDom();
    signinButton.dataset.path = "/groups/test-group?tab=members&role=admin";

    // Open the membership sign-in alert.
    signinButton.click();

    // The sign-in link keeps the full return path inside the next_url value.
    expect(env.current.swal.calls[0].html).to.include(
      "/log-in?next_url=%2Fgroups%2Ftest-group%3Ftab%3Dmembers%26role%3Dadmin",
    );
  });

  it("closes the group actions menu when clicking outside it", () => {
    // Render the membership fixture.
    renderMembershipDom();
    document.body.insertAdjacentHTML(
      "beforeend",
      "<details data-group-actions-menu open><summary>More actions</summary></details>",
    );

    // Keep a reference to the group actions menu element.
    const actionsMenu = document.querySelector("[data-group-actions-menu]");
    document.body.click();

    // Verify closes the group actions menu when clicking outside it.
    expect(actionsMenu.open).to.equal(false);
  });

  it("emits membership-changed after a successful join request", () => {
    // Render the membership fixture.
    const { joinButton } = renderMembershipDom();
    let changedEvents = 0;
    document.body.addEventListener("membership-changed", () => {
      changedEvents += 1;
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(joinButton);

    // Joining emits membership-changed after the request succeeds.
    expect(changedEvents).to.equal(1);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "You have successfully joined this group.",
      icon: "success",
    });
  });

  it("emits membership-changed after leaving and restores the leave button on failure", () => {
    // Render the membership fixture.
    const { leaveButton, loadingButton } = renderMembershipDom();
    let changedEvents = 0;
    document.body.addEventListener("membership-changed", () => {
      changedEvents += 1;
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(leaveButton);

    // Leaving emits membership-changed and restores the leave button.
    expect(changedEvents).to.equal(1);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "You have successfully left this group.",
      icon: "success",
    });

    // Update fixture state before asserting the new state.
    leaveButton.classList.add("hidden");
    loadingButton.classList.remove("hidden");
    dispatchHtmxAfterRequest(leaveButton, {
      status: 500,
    });

    // The leave flow emits membership-changed and restores the button.
    expect(leaveButton.classList.contains("hidden")).to.equal(false);
    expect(loadingButton.classList.contains("hidden")).to.equal(true);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "Something went wrong leaving this group. Please try again later.",
      icon: "error",
    });
  });
});
