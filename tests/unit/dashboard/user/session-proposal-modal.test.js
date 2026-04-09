import { expect } from "@open-wc/testing";

import "/static/js/dashboard/user/session-proposal-modal.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { setupDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";

describe("session-proposal-modal", () => {
  let env;

  beforeEach(() => {
    env = setupDashboardTestEnv({
      path: "/dashboard/user/session-proposals",
      withHtmx: true,
      withSwal: true,
    });
  });

  afterEach(() => {
    removeMountedElements("session-proposal-modal");
    resetDom();
    env.restore();
  });

  it("opens in edit mode and syncs form endpoints and values", async () => {
    const element = document.createElement("session-proposal-modal");
    element.setAttribute(
      "session-proposal-levels",
      JSON.stringify([{ session_proposal_level_id: "level-1", display_name: "Beginner" }]),
    );
    document.body.append(element);
    await element.updateComplete;

    element.openEdit({
      session_proposal_id: 7,
      title: "Platform Engineering",
      session_proposal_level_id: "level-1",
      duration_minutes: 45,
      description: "Abstract",
    });
    await element.updateComplete;

    expect(element._buildUpdateEndpoint()).to.equal("/dashboard/user/session-proposals/7");
    expect(element.querySelector("#session-proposal-form").getAttribute("hx-put")).to.equal(
      "/dashboard/user/session-proposals/7",
    );
    expect(element.querySelector("#session-proposal-title").value).to.equal("Platform Engineering");
    expect(element.querySelector("#session-proposal-level").value).to.equal("level-1");
    expect(element.querySelector("#session-proposal-duration").value).to.equal("45");
  });

  it("closes after a successful htmx save request", async () => {
    const element = await mountLitComponent("session-proposal-modal");

    element.openCreate();
    await element.updateComplete;

    element.querySelector("#session-proposal-form").dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          xhr: { status: 204 },
        },
      }),
    );

    expect(element._isOpen).to.equal(false);
  });
});
