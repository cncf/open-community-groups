import { expect } from "@open-wc/testing";

import "/static/js/group/membership.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import {
  dispatchHtmxAfterRequest,
  dispatchHtmxBeforeRequest,
} from "/tests/unit/test-utils/htmx.js";

// Render the fixture to check it covers the current behavior.
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
    // Read fixture controls to check it shows the leave action after a successful.
    const { checker, leaveButton, signinButton, joinButton } =
      renderMembershipDom();

    // Dispatch the HTMX after request event to check it shows the leave action.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ is_member: true }),
    });

    // Confirm it shows the leave action after a successful membership check.
    expect(leaveButton.classList.contains("hidden")).to.equal(false);
    expect(signinButton.classList.contains("hidden")).to.equal(true);
    expect(joinButton.classList.contains("hidden")).to.equal(true);
  });

  it("falls back to the sign-in action when the membership response is invalid", () => {
    // Read fixture controls to check it falls back to the sign-in action.
    const { checker, signinButton, joinButton, leaveButton } =
      renderMembershipDom();

    // Dispatch the HTMX after request event to check it falls back to the sign-in action.
    dispatchHtmxAfterRequest(checker, {
      responseText: "{invalid json}",
    });

    // Confirm it falls back to the sign-in action when the membership response.
    expect(signinButton.classList.contains("hidden")).to.equal(false);
    expect(joinButton.classList.contains("hidden")).to.equal(true);
    expect(leaveButton.classList.contains("hidden")).to.equal(true);
  });

  it("shows loading state before a join request and restores the button on failure", () => {
    // Render the fixture to check it shows loading state before a join request.
    const { joinButton, loadingButton } = renderMembershipDom();

    // Dispatch the HTMX before request event to check it shows loading state.
    dispatchHtmxBeforeRequest(joinButton);

    // Confirm it shows loading state before a join request and restores the button.
    expect(joinButton.classList.contains("hidden")).to.equal(true);
    expect(loadingButton.classList.contains("hidden")).to.equal(false);

    // Dispatch the HTMX after request event to check it shows loading state.
    dispatchHtmxAfterRequest(joinButton, {
      status: 500,
    });

    // Confirm it shows loading state before a join request and restores the button.
    expect(joinButton.classList.contains("hidden")).to.equal(false);
    expect(loadingButton.classList.contains("hidden")).to.equal(true);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "Something went wrong joining this group. Please try again later.",
      icon: "error",
    });
    expect(env.current.scrollToMock.calls).to.deep.equal([]);
  });

  it("shows sign-in info and confirms leave actions", async () => {
    // Render the fixture to check it shows sign-in info and confirms leave actions.
    const { signinButton, leaveButton } = renderMembershipDom();

    // Trigger the user interaction to check it shows sign-in info and confirms leave.
    signinButton.click();

    // Confirm it shows sign-in info and confirms leave actions.
    expect(env.current.swal.calls[0].icon).to.equal("info");
    expect(env.current.swal.calls[0].html).to.include(
      "/log-in?next_url=/groups/test-group",
    );

    // Exercise the flow to check it shows sign-in info and confirms leave actions.
    env.current.swal.setNextResult({ isConfirmed: true });
    leaveButton.click();
    await waitForMicrotask();

    // Confirm it shows sign-in info and confirms leave actions.
    expect(env.current.swal.calls[1]).to.include({
      text: "Are you sure you want to leave this group?",
      icon: "warning",
    });
    expect(env.current.htmx.triggerCalls).to.deep.equal([
      ["#leave-btn", "confirmed"],
    ]);
  });

  it("handles membership clicks after the page body is swapped", () => {
    // Prepare replacement body to check it handles membership clicks after the page body.
    const replacementBody = document.createElement("body");
    document.documentElement.replaceChild(replacementBody, document.body);
    const { signinButton } = renderMembershipDom();

    // Trigger the user interaction to check it handles membership clicks after the page.
    signinButton.click();

    // Confirm it handles membership clicks after the page body is swapped.
    expect(env.current.swal.calls[0].icon).to.equal("info");
    expect(env.current.swal.calls[0].html).to.include(
      "/log-in?next_url=/groups/test-group",
    );
  });

  it("closes the group actions menu when clicking outside it", () => {
    // Render the fixture to check it closes the group actions menu when clicking outside.
    renderMembershipDom();
    document.body.insertAdjacentHTML(
      "beforeend",
      "<details data-group-actions-menu open><summary>More actions</summary></details>",
    );

    // Read the group actions menu element to check it closes the group actions menu.
    const actionsMenu = document.querySelector("[data-group-actions-menu]");
    document.body.click();

    // Confirm it closes the group actions menu when clicking outside it.
    expect(actionsMenu.open).to.equal(false);
  });

  it("emits membership-changed after a successful join request", () => {
    // Render the fixture to check it emits membership-changed after a successful join.
    const { joinButton } = renderMembershipDom();
    let changedEvents = 0;
    document.body.addEventListener("membership-changed", () => {
      changedEvents += 1;
    });

    // Dispatch the HTMX after request event to check it emits membership-changed.
    dispatchHtmxAfterRequest(joinButton);

    // Confirm it emits membership-changed after a successful join request.
    expect(changedEvents).to.equal(1);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "You have successfully joined this group.",
      icon: "success",
    });
  });

  it("emits membership-changed after leaving and restores the leave button on failure", () => {
    // Render the fixture to check it emits membership-changed after leaving and restores.
    const { leaveButton, loadingButton } = renderMembershipDom();
    let changedEvents = 0;
    document.body.addEventListener("membership-changed", () => {
      changedEvents += 1;
    });

    // Dispatch the HTMX after request event to check it emits membership-changed.
    dispatchHtmxAfterRequest(leaveButton);

    // Confirm it emits membership-changed after leaving and restores the leave button.
    expect(changedEvents).to.equal(1);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "You have successfully left this group.",
      icon: "success",
    });

    // Update fixture state to check it emits membership-changed after leaving.
    leaveButton.classList.add("hidden");
    loadingButton.classList.remove("hidden");
    dispatchHtmxAfterRequest(leaveButton, {
      status: 500,
    });

    // Confirm it emits membership-changed after leaving and restores the leave button.
    expect(leaveButton.classList.contains("hidden")).to.equal(false);
    expect(loadingButton.classList.contains("hidden")).to.equal(true);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "Something went wrong leaving this group. Please try again later.",
      icon: "error",
    });
  });
});
