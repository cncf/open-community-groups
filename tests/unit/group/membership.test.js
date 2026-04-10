import { expect } from "@open-wc/testing";

import "/static/js/group/membership.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest, dispatchHtmxBeforeRequest } from "/tests/unit/test-utils/htmx.js";

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
    const { checker, leaveButton, signinButton, joinButton } = renderMembershipDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ is_member: true }),
    });

    expect(leaveButton.classList.contains("hidden")).to.equal(false);
    expect(signinButton.classList.contains("hidden")).to.equal(true);
    expect(joinButton.classList.contains("hidden")).to.equal(true);
  });

  it("falls back to the sign-in action when the membership response is invalid", () => {
    const { checker, signinButton, joinButton, leaveButton } = renderMembershipDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: "{invalid json}",
    });

    expect(signinButton.classList.contains("hidden")).to.equal(false);
    expect(joinButton.classList.contains("hidden")).to.equal(true);
    expect(leaveButton.classList.contains("hidden")).to.equal(true);
  });

  it("shows loading state before a join request and restores the button on failure", () => {
    const { joinButton, loadingButton } = renderMembershipDom();

    dispatchHtmxBeforeRequest(joinButton);

    expect(joinButton.classList.contains("hidden")).to.equal(true);
    expect(loadingButton.classList.contains("hidden")).to.equal(false);

    dispatchHtmxAfterRequest(joinButton, {
      status: 500,
    });

    expect(joinButton.classList.contains("hidden")).to.equal(false);
    expect(loadingButton.classList.contains("hidden")).to.equal(true);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "Something went wrong joining this group. Please try again later.",
      icon: "error",
    });
    expect(env.current.scrollToMock.calls).to.deep.equal([]);
  });

  it("shows sign-in info and confirms leave actions", async () => {
    const { signinButton, leaveButton } = renderMembershipDom();

    signinButton.click();

    expect(env.current.swal.calls[0].icon).to.equal("info");
    expect(env.current.swal.calls[0].html).to.include("/log-in?next_url=/groups/test-group");

    env.current.swal.setNextResult({ isConfirmed: true });
    leaveButton.click();
    await waitForMicrotask();

    expect(env.current.swal.calls[1]).to.include({
      text: "Are you sure you want to leave this group?",
      icon: "warning",
    });
    expect(env.current.htmx.triggerCalls).to.deep.equal([["#leave-btn", "confirmed"]]);
  });

  it("emits membership-changed after a successful join request", () => {
    const { joinButton } = renderMembershipDom();
    let changedEvents = 0;
    document.body.addEventListener("membership-changed", () => {
      changedEvents += 1;
    });

    dispatchHtmxAfterRequest(joinButton);

    expect(changedEvents).to.equal(1);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "You have successfully joined this group.",
      icon: "success",
    });
  });

  it("emits membership-changed after leaving and restores the leave button on failure", () => {
    const { leaveButton, loadingButton } = renderMembershipDom();
    let changedEvents = 0;
    document.body.addEventListener("membership-changed", () => {
      changedEvents += 1;
    });

    dispatchHtmxAfterRequest(leaveButton);

    expect(changedEvents).to.equal(1);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "You have successfully left this group.",
      icon: "success",
    });

    leaveButton.classList.add("hidden");
    loadingButton.classList.remove("hidden");
    dispatchHtmxAfterRequest(leaveButton, {
      status: 500,
    });

    expect(leaveButton.classList.contains("hidden")).to.equal(false);
    expect(loadingButton.classList.contains("hidden")).to.equal(true);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "Something went wrong leaving this group. Please try again later.",
      icon: "error",
    });
  });
});
