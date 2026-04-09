import { expect } from "@open-wc/testing";

import "/static/js/dashboard/community/team-add-member.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { setupDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";

describe("team-add-member", () => {
  const userSearchFieldPrototype = customElements.get("user-search-field").prototype;
  const originalFocusInput = userSearchFieldPrototype.focusInput;

  let env;
  let processCalls;

  beforeEach(() => {
    env = setupDashboardTestEnv({
      path: "/dashboard/community/team",
      withHtmx: true,
      withSwal: true,
    });

    processCalls = [];
    globalThis.htmx.process = (form) => {
      processCalls.push(form);
    };
  });

  afterEach(() => {
    userSearchFieldPrototype.focusInput = originalFocusInput;
    removeMountedElements("team-add-member");
    resetDom();
    env.restore();
  });

  const renderWithAttributes = async (attributes = {}) => {
    const element = document.createElement("team-add-member");

    Object.entries(attributes).forEach(([name, value]) => {
      element.setAttribute(name, value);
    });

    document.body.append(element);
    await element.updateComplete;

    return element;
  };

  it("parses selected users and role options from attributes", async () => {
    const element = await renderWithAttributes({
      "selected-users": JSON.stringify([
        { user_id: 101, name: "Ada Lovelace" },
        { user_id: "202", name: "Grace Hopper" },
      ]),
      "role-options": JSON.stringify([
        { display_name: "Maintainer", community_role_id: "role-1" },
        { display_name: "Reviewer", group_role_id: "role-2" },
      ]),
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

    const element = await renderWithAttributes({
      "role-options": JSON.stringify([{ display_name: "Maintainer", community_role_id: "role-1" }]),
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

  it("enables submit only after both a user and role have been selected", async () => {
    const element = await renderWithAttributes({
      "role-options": JSON.stringify([{ display_name: "Maintainer", community_role_id: "role-1" }]),
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
    const element = await renderWithAttributes({
      "role-options": JSON.stringify([{ display_name: "Maintainer", community_role_id: "role-1" }]),
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
    form.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          xhr: {
            status: 204,
          },
        },
      }),
    );

    expect(element._isOpen).to.equal(false);
    expect(element._selectedUser).to.equal(null);
    expect(element._selectedRole).to.equal("");
    expect(document.body.style.overflow).to.equal("");
    expect(document.body.dataset.modalOpenCount).to.equal("0");
    expect(env.swal.calls).to.have.length(1);
    expect(env.swal.calls[0]).to.include({
      text: "Invitation sent to the selected user.",
      icon: "success",
    });
  });
});
