import { expect } from "@open-wc/testing";

import "/static/js/dashboard/user/session-proposal-modal.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest } from "/tests/unit/test-utils/htmx.js";
import {
  mountLitComponent,
  mountLitComponentWithAttributes,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("session-proposal-modal", () => {
  useDashboardTestEnv({
    path: "/dashboard/user/session-proposals",
    withHtmx: true,
    withSwal: true,
  });

  useMountedElementsCleanup("session-proposal-modal");

  it("opens in edit mode and syncs form endpoints and values", async () => {
    const element = await mountLitComponentWithAttributes("session-proposal-modal", {
      attributes: {
        "session-proposal-levels": JSON.stringify([
          { session_proposal_level_id: "level-1", display_name: "Beginner" },
        ]),
      },
    });

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

    dispatchHtmxAfterRequest(element.querySelector("#session-proposal-form"), {
      status: 204,
    });

    expect(element._isOpen).to.equal(false);
  });

  it("keeps the modal open after a failed htmx save request", async () => {
    const element = await mountLitComponent("session-proposal-modal");

    element.openCreate();
    await element.updateComplete;

    dispatchHtmxAfterRequest(element.querySelector("#session-proposal-form"), {
      status: 500,
    });

    expect(element._isOpen).to.equal(true);
  });

  it("toggles the editor to readonly and closes on escape", async () => {
    const element = await mountLitComponent("session-proposal-modal");

    element.openCreate();
    await element.updateComplete;

    const editor = element.querySelector("markdown-editor#session-proposal-description");
    const toolbar = document.createElement("div");
    toolbar.className = "editor-toolbar";
    const codeMirrorElement = document.createElement("div");
    codeMirrorElement.className = "CodeMirror";
    const codeMirrorCalls = [];
    codeMirrorElement.CodeMirror = {
      setOption(option, value) {
        codeMirrorCalls.push({ option, value });
      },
    };
    editor.append(toolbar, codeMirrorElement);

    element._setDescriptionReadOnly(true);
    await waitForMicrotask();

    expect(editor.disabled).to.equal(true);
    expect(toolbar.classList.contains("pointer-events-none")).to.equal(true);
    expect(codeMirrorElement.classList.contains("bg-stone-100")).to.equal(true);
    expect(codeMirrorCalls).to.deep.equal([{ option: "readOnly", value: "nocursor" }]);

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));

    expect(element._isOpen).to.equal(false);
  });

  it("locks co-speaker changes once a submitted proposal is being edited", async () => {
    const element = await mountLitComponent("session-proposal-modal", {
      currentUserId: "speaker-1",
    });

    element.openEdit({
      session_proposal_id: 12,
      title: "Systems thinking",
      has_submissions: true,
      co_speaker: { user_id: "speaker-2", username: "grace" },
    });
    await element.updateComplete;

    const coSpeakerSearch = element.querySelector("#session-proposal-co-speaker-search");

    expect(coSpeakerSearch.disabled).to.equal(true);
    expect(coSpeakerSearch.excludeUsernames).to.deep.equal(["grace"]);

    element._handleCoSpeakerSelected({
      detail: { user: { user_id: "speaker-3", username: "hedy" } },
    });
    element._clearCoSpeaker();

    expect(element._selectedCoSpeaker).to.deep.equal({ user_id: "speaker-2", username: "grace" });
  });

  it("removes the document keydown listener when disconnected", async () => {
    const originalRemoveEventListener = document.removeEventListener.bind(document);
    const removedListeners = [];

    document.removeEventListener = (type, listener, options) => {
      removedListeners.push({ type, listener, options });
      return originalRemoveEventListener(type, listener, options);
    };

    try {
      const element = await mountLitComponent("session-proposal-modal");
      const keydownListener = element._onKeydown;

      element.openCreate();
      await element.updateComplete;
      element.remove();

      expect(removedListeners.some(({ type, listener }) => type === "keydown" && listener === keydownListener)).to
        .equal(true);
    } finally {
      document.removeEventListener = originalRemoveEventListener;
    }
  });
});
