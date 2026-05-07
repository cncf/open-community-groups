import { expect } from "@open-wc/testing";

import "/static/js/dashboard/community/team-add-member.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest } from "/tests/unit/test-utils/htmx.js";
import {
  mountLitComponent,
  mountLitComponentWithAttributes,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("team-add-member", () => {
  const userSearchFieldPrototype = customElements.get("user-search-field").prototype;
  const originalFocusInput = userSearchFieldPrototype.focusInput;

  const env = useDashboardTestEnv({
    path: "/dashboard/community/team",
    withHtmx: true,
    withSwal: true,
  });

  useMountedElementsCleanup("team-add-member");

  let processCalls;

  beforeEach(() => {
    processCalls = [];
    globalThis.htmx.process = (form) => {
      processCalls.push(form);
    };
  });

  afterEach(() => {
    userSearchFieldPrototype.focusInput = originalFocusInput;
  });

  it("parses selected users and role options from attributes", async () => {
    const element = await mountLitComponentWithAttributes("team-add-member", {
      attributes: {
        "selected-users": JSON.stringify([
          { user_id: 101, name: "Ada Lovelace" },
          { user_id: "202", name: "Grace Hopper" },
        ]),
        "role-options": JSON.stringify([
          { display_name: "Maintainer", community_role_id: "role-1" },
          { display_name: "Reviewer", group_role_id: "role-2" },
        ]),
      },
    });

    expect(element.selectedUsers).to.deep.equal([
      { user_id: 101, name: "Ada Lovelace" },
      { user_id: "202", name: "Grace Hopper" },
    ]);
    expect(element.disabledUserIds).to.deep.equal(["101", "202"]);
    expect(element.roleOptions).to.deep.equal([
      { label: "Maintainer", value: "role-1" },
      { label: "Reviewer", value: "role-2" },
    ]);
  });

  it("renders a disabled trigger when the current user cannot manage the team", async () => {
    const element = await mountLitComponent("team-add-member", {
      canManageTeam: false,
    });

    const button = element.querySelector("button");

    expect(button.disabled).to.equal(true);
    expect(button.title).to.equal("Your role cannot invite team members.");
    expect(element.querySelector("#team-add-form")).to.equal(null);
  });

  it("opens the modal, locks body scroll, focuses the search field, and processes htmx", async () => {
    let focusCalls = 0;
    userSearchFieldPrototype.focusInput = () => {
      focusCalls += 1;
    };

    const element = await mountLitComponentWithAttributes("team-add-member", {
      attributes: {
        "role-options": JSON.stringify([{ display_name: "Maintainer", community_role_id: "role-1" }]),
      },
    });

    element._open();
    await element.updateComplete;
    await Promise.resolve();

    const form = element.querySelector("#team-add-form");

    expect(element._isOpen).to.equal(true);
    expect(document.body.style.overflow).to.equal("hidden");
    expect(document.body.dataset.modalOpenCount).to.equal("1");
    expect(form).to.not.equal(null);
    expect(processCalls).to.deep.equal([form]);
    expect(focusCalls).to.equal(1);
  });

  it("allows the user search dropdown to overflow the modal", async () => {
    const element = await mountLitComponentWithAttributes("team-add-member", {
      attributes: {
        "role-options": JSON.stringify([{ display_name: "Maintainer", community_role_id: "role-1" }]),
      },
    });

    element._open();
    await element.updateComplete;

    expect(element.querySelector(".modal-card").classList.contains("modal-overflow-visible")).to.equal(true);
    expect(element.querySelector(".modal-body").classList.contains("modal-overflow-visible")).to.equal(true);
  });

  it("enables submit only after both a user and role have been selected", async () => {
    const element = await mountLitComponentWithAttributes("team-add-member", {
      attributes: {
        "role-options": JSON.stringify([{ display_name: "Maintainer", community_role_id: "role-1" }]),
      },
    });

    element._open();
    await element.updateComplete;

    const userIdInput = element.querySelector("#team-add-user-id");
    const submitButton = element.querySelector("#team-add-submit");

    expect(submitButton.disabled).to.equal(true);

    element._onUserSelected({
      detail: {
        user: {
          user_id: "user-7",
          name: "Ada Lovelace",
          username: "ada",
        },
      },
    });
    await element.updateComplete;

    expect(userIdInput.value).to.equal("user-7");
    expect(submitButton.disabled).to.equal(true);

    element._onRoleChanged({
      target: {
        value: "role-1",
      },
    });
    await element.updateComplete;

    expect(element._selectedRole).to.equal("role-1");
    expect(submitButton.disabled).to.equal(false);
    expect(element.textContent).to.include("Ada Lovelace");
  });

  it("closes and resets the form after a successful htmx request", async () => {
    const element = await mountLitComponentWithAttributes("team-add-member", {
      attributes: {
        "role-options": JSON.stringify([{ display_name: "Maintainer", community_role_id: "role-1" }]),
      },
    });

    element._open();
    await element.updateComplete;

    element._onUserSelected({
      detail: {
        user: {
          user_id: "user-8",
          name: "Grace Hopper",
          username: "grace",
        },
      },
    });
    element._onRoleChanged({
      target: {
        value: "role-1",
      },
    });
    await element.updateComplete;

    const form = element.querySelector("#team-add-form");
    dispatchHtmxAfterRequest(form, {
      status: 204,
    });

    expect(element._isOpen).to.equal(false);
    expect(element._selectedUser).to.equal(null);
    expect(element._selectedRole).to.equal("");
    expect(document.body.style.overflow).to.equal("");
    expect(document.body.dataset.modalOpenCount).to.equal("0");
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0]).to.include({
      text: "Invitation sent to the selected user.",
      icon: "success",
    });
  });
});
