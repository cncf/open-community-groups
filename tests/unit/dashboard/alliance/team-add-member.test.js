import { expect } from "@open-wc/testing";

import "/static/js/dashboard/alliance/team-add-member.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest } from "/tests/unit/test-utils/htmx.js";
import {
  mountLitComponent,
  mountLitComponentWithAttributes,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("team-add-member", () => {
  const userSearchFieldPrototype =
    customElements.get("user-search-field").prototype;
  const originalFocusInput = userSearchFieldPrototype.focusInput;

  const env = useDashboardTestEnv({
    path: "/dashboard/alliance/team",
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
    // Call mount lit component with attributes.
    const element = await mountLitComponentWithAttributes("team-add-member", {
      attributes: {
        "selected-users": JSON.stringify([
          { user_id: 101, name: "Ada Lovelace" },
          { user_id: "202", name: "Grace Hopper" },
        ]),
        "role-options": JSON.stringify([
          { display_name: "Maintainer", alliance_role_id: "role-1" },
          { display_name: "Reviewer", group_role_id: "role-2" },
        ]),
      },
    });

    // Selected users and role options are parsed from attributes.
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
    // Call mount lit component.
    const element = await mountLitComponent("team-add-member", {
      canManageTeam: false,
    });

    // Read the disabled trigger for users without team permissions.
    const button = element.querySelector("button");

    // Verify renders a disabled trigger when the current user cannot manage the team.
    expect(button.disabled).to.equal(true);
    expect(button.title).to.equal("Your role cannot invite team members.");
    expect(element.querySelector("#team-add-form")).to.equal(null);
  });

  it("renders the configured disabled tooltip", async () => {
    // Prepare tooltip for rendering the configured disabled tooltip.
    const tooltip =
      "Only alliance admins and groups managers can manage this group's team.";
    const element = await mountLitComponentWithAttributes("team-add-member", {
      attributes: {
        "can-manage-team": "false",
        "disabled-tooltip": tooltip,
      },
    });

    // Read the rendered DOM state for rendering the configured disabled tooltip.
    const button = element.querySelector("button");

    // Verify renders the configured disabled tooltip.
    expect(button.disabled).to.equal(true);
    expect(button.title).to.equal(tooltip);
    expect(element.querySelector("#team-add-form")).to.equal(null);
  });

  it("opens the modal, locks body scroll, focuses the search field, and processes htmx", async () => {
    // Prepare focus calls for opening the modal, locks body scroll, focuses.
    let focusCalls = 0;
    userSearchFieldPrototype.focusInput = () => {
      focusCalls += 1;
    };

    // Call mount lit component with attributes.
    const element = await mountLitComponentWithAttributes("team-add-member", {
      attributes: {
        "role-options": JSON.stringify([
          { display_name: "Maintainer", alliance_role_id: "role-1" },
        ]),
      },
    });

    // Call open.
    element._open();
    await element.updateComplete;
    await Promise.resolve();

    // Read the modal, body, and focused search field after opening.
    const form = element.querySelector("#team-add-form");

    // Verify opens the modal, locks body scroll, focuses the search field.
    expect(element._isOpen).to.equal(true);
    expect(document.body.style.overflow).to.equal("hidden");
    expect(document.body.dataset.modalOpenCount).to.equal("1");
    expect(form).to.not.equal(null);
    expect(processCalls).to.deep.equal([form]);
    expect(focusCalls).to.equal(1);
  });

  it("allows the user search dropdown to overflow the modal", async () => {
    // Call mount lit component with attributes.
    const element = await mountLitComponentWithAttributes("team-add-member", {
      attributes: {
        "role-options": JSON.stringify([
          { display_name: "Maintainer", alliance_role_id: "role-1" },
        ]),
      },
    });

    // Call open.
    element._open();
    await element.updateComplete;

    // The user search dropdown can overflow the modal.
    expect(
      element
        .querySelector(".modal-card")
        .classList.contains("modal-overflow-visible"),
    ).to.equal(true);
    expect(
      element
        .querySelector(".modal-body")
        .classList.contains("modal-overflow-visible"),
    ).to.equal(true);
  });

  it("enables submit only after both a user and role have been selected", async () => {
    // Call mount lit component with attributes.
    const element = await mountLitComponentWithAttributes("team-add-member", {
      attributes: {
        "role-options": JSON.stringify([
          { display_name: "Maintainer", alliance_role_id: "role-1" },
        ]),
      },
    });

    // Call open.
    element._open();
    await element.updateComplete;

    // Read the selected user, role, and submit button.
    const userIdInput = element.querySelector("#team-add-user-id");
    const submitButton = element.querySelector("#team-add-submit");

    // Verify submit is still disabled with only a user selected.
    expect(submitButton.disabled).to.equal(true);

    // Call the user selection handler.
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

    // Verify submit stays disabled until a role is selected.
    expect(userIdInput.value).to.equal("user-7");
    expect(submitButton.disabled).to.equal(true);

    // Call on role changed.
    element._onRoleChanged({
      target: {
        value: "role-1",
      },
    });
    await element.updateComplete;

    // Verify submit is enabled once both selections are present.
    expect(element._selectedRole).to.equal("role-1");
    expect(submitButton.disabled).to.equal(false);
    expect(element.textContent).to.include("Ada Lovelace");
  });

  it("closes and resets the form after a successful htmx request", async () => {
    // Call mount lit component with attributes.
    const element = await mountLitComponentWithAttributes("team-add-member", {
      attributes: {
        "role-options": JSON.stringify([
          { display_name: "Maintainer", alliance_role_id: "role-1" },
        ]),
      },
    });

    // Call open.
    element._open();
    await element.updateComplete;

    // Select the user before choosing a role.
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

    // Read the form state after the successful HTMX response.
    const form = element.querySelector("#team-add-form");
    dispatchHtmxAfterRequest(form, {
      status: 204,
    });

    // Verify closes and resets the form after a successful HTMX request.
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
