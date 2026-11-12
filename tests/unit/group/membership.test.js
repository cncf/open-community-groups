import { expect } from "@open-wc/testing";

import "/static/js/group/membership.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import {
  dispatchHtmxAfterRequest,
  dispatchHtmxBeforeRequest,
  dispatchHtmxLoad,
} from "/tests/unit/test-utils/htmx.js";

// Render the component fixture. The hidden rule matches the app styles, so a
// hidden button loses focus as it does in the browser.
const renderMembershipDom = () => {
  document.body.innerHTML = `
    <style>.hidden { display: none; }</style>
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

// Start a membership action from its focused button and let the browser apply
// the hidden state, as it does while the request is in flight.
const startFocusedAction = async (button) => {
  button.classList.remove("hidden");
  button.focus();
  dispatchHtmxBeforeRequest(button);
  button.getBoundingClientRect();
  await waitForMicrotask();
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

  it("shows the sign-in action without a membership check when logged out", async () => {
    // Render the loading fixture below a user menu that reports a logged-out visitor.
    const { loadingButton, signinButton, joinButton } = renderMembershipDom();
    loadingButton.classList.remove("hidden");
    document.body.insertAdjacentHTML(
      "afterbegin",
      '<button id="user-dropdown-button" data-logged-in="false"></button>',
    );

    // Initialize the container, as HTMX does after loading it.
    dispatchHtmxLoad();
    await waitForMicrotask();

    // Verify the sign-in action replaces the loading state with no response.
    expect(signinButton.classList.contains("hidden")).to.equal(false);
    expect(loadingButton.classList.contains("hidden")).to.equal(true);
    expect(joinButton.classList.contains("hidden")).to.equal(true);
  });

  it("keeps the loading state for logged-in users until the membership check answers", async () => {
    // Render the loading fixture below a user menu that reports a logged-in user.
    const { loadingButton, signinButton } = renderMembershipDom();
    loadingButton.classList.remove("hidden");
    document.body.insertAdjacentHTML(
      "afterbegin",
      '<button id="user-dropdown-button" data-logged-in="true"></button>',
    );

    // Initialize the container, as HTMX does after loading it.
    dispatchHtmxLoad();
    await waitForMicrotask();

    // Verify the container still waits for the membership response.
    expect(loadingButton.classList.contains("hidden")).to.equal(false);
    expect(signinButton.classList.contains("hidden")).to.equal(true);
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

    // Start a second leave request that fails.
    dispatchHtmxBeforeRequest(leaveButton);
    expect(leaveButton.classList.contains("hidden")).to.equal(true);
    expect(loadingButton.classList.contains("hidden")).to.equal(false);
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

  it("focuses the leave action after a successful join and re-check", async () => {
    // Start a join request from the focused join action.
    const { checker, joinButton, leaveButton } = renderMembershipDom();
    await startFocusedAction(joinButton);

    // Complete the join and the membership re-check it triggers.
    dispatchHtmxAfterRequest(joinButton);
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ is_member: true }),
    });
    await waitForMicrotask();

    // Focus lands on the leave action that now applies.
    expect(document.activeElement.id).to.equal(leaveButton.id);
  });

  it("focuses the join action after leaving", async () => {
    // Start a leave request from the focused leave action.
    const { checker, joinButton, leaveButton } = renderMembershipDom();
    await startFocusedAction(leaveButton);

    // Complete the leave and the membership re-check it triggers.
    dispatchHtmxAfterRequest(leaveButton);
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ is_member: false }),
    });
    await waitForMicrotask();

    // Focus lands on the join action that now applies.
    expect(document.activeElement.id).to.equal(joinButton.id);
  });

  it("returns focus to the restored action after a failed join or leave", async () => {
    // Fail a join request started from the focused join action.
    const { joinButton, leaveButton } = renderMembershipDom();
    await startFocusedAction(joinButton);
    expect(document.activeElement.id).not.to.equal(joinButton.id);
    dispatchHtmxAfterRequest(joinButton, { status: 500 });
    await waitForMicrotask();

    // Focus returns to the restored join action.
    expect(document.activeElement.id).to.equal(joinButton.id);

    // Fail a leave request started from the focused leave action.
    joinButton.classList.add("hidden");
    await startFocusedAction(leaveButton);
    expect(document.activeElement.id).not.to.equal(leaveButton.id);
    dispatchHtmxAfterRequest(leaveButton, { status: 500 });
    await waitForMicrotask();

    // Focus returns to the restored leave action.
    expect(document.activeElement.id).to.equal(leaveButton.id);
  });

  it("waits for an open alert to close before moving focus", async () => {
    // Render an open alert container that stays visible until removed.
    const { checker, joinButton, leaveButton } = renderMembershipDom();
    const alertContainer = document.createElement("div");
    alertContainer.className = "swal2-container";
    document.body.append(alertContainer);
    globalThis.Swal.isVisible = () => alertContainer.isConnected;

    // Join and re-check while the result alert is open.
    await startFocusedAction(joinButton);
    dispatchHtmxAfterRequest(joinButton);
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ is_member: true }),
    });
    await waitForMicrotask();

    // Focus stays put while the alert is open.
    expect(document.activeElement.id).not.to.equal(leaveButton.id);

    // Closing the alert moves focus to the leave action.
    alertContainer.remove();
    await waitForMicrotask();
    expect(document.activeElement.id).to.equal(leaveButton.id);
  });

  it("does not move focus on the initial membership check", async () => {
    // Resolve the initial membership check without a pending action.
    const { checker, joinButton } = renderMembershipDom();
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ is_member: false }),
    });
    await waitForMicrotask();

    // The join action shows without taking focus.
    expect(joinButton.classList.contains("hidden")).to.equal(false);
    expect(document.activeElement.id).not.to.equal(joinButton.id);
  });

  it("keeps focus where the user moved it during the request", async () => {
    // Render another control the user can move focus to.
    const { checker, joinButton } = renderMembershipDom();
    document.body.insertAdjacentHTML("beforeend", '<button id="other-control" type="button">Other</button>');
    const otherControl = document.getElementById("other-control");

    // Start a join request, then move focus elsewhere before it settles.
    await startFocusedAction(joinButton);
    otherControl.focus();
    dispatchHtmxAfterRequest(joinButton);
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ is_member: true }),
    });
    await waitForMicrotask();

    // Focus stays on the control the user chose.
    expect(document.activeElement.id).to.equal(otherControl.id);
  });
});
