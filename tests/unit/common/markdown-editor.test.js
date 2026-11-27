import { expect } from "@open-wc/testing";

import "/static/js/common/markdown-editor.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("markdown-editor", () => {
  const originalEasyMde = globalThis.EasyMDE;
  let MockEasyMde;
  let latestEditor;

  useMountedElementsCleanup("markdown-editor");

  beforeEach(() => {
    latestEditor = null;
    MockEasyMde = class {
      static drawHorizontalRule = () => {};
      static drawLink = () => {};
      static drawTable = () => {};
      static redo = () => {};
      static toggleBlockquote = () => {};
      static toggleBold = () => {};
      static toggleCheckList = () => {};
      static toggleHeadingSmaller = () => {};
      static toggleItalic = () => {};
      static toggleOrderedList = () => {};
      static togglePreview = () => {};
      static toggleUnorderedList = () => {};
      static undo = () => {};

      constructor(options) {
        this.options = options;
        this._changeHandler = null;
        this.elementTabIndexAtInit = options.element.tabIndex;
        this.focused = false;
        this.selectionCalls = [];
        this.setOptionCalls = [];
        latestEditor = this;

        const container = document.createElement("div");
        container.className = "EasyMDEContainer";
        const toolbar = document.createElement("div");
        toolbar.className = "editor-toolbar";
        const boldButton = document.createElement("button");
        boldButton.type = "button";
        boldButton.className = "bold";
        toolbar.append(boldButton);
        container.append(toolbar);
        options.element.insertAdjacentElement("afterend", container);

        this.codemirror = {
          focus: () => {
            this.focused = true;
          },
          on: (eventName, handler) => {
            if (eventName === "change") {
              this._changeHandler = handler;
            }
          },
          posFromIndex: (index) => ({ ch: index, line: 0 }),
          setOption: (name, value) => {
            this.setOptionCalls.push({ name, value });
          },
          setSelection: (anchor, head) => {
            this.selectionCalls.push({ anchor, head });
          },
        };
      }

      value() {
        return "## Updated";
      }
    };
    globalThis.EasyMDE = MockEasyMde;
  });

  afterEach(() => {
    document.head
      .querySelectorAll(
        'script[src*="easymde.v2.21.0.min.js"], link[href*="easymde.v2.21.0.min.css"], link[href^="/static/css/styles"]',
      )
      .forEach((node) => node.remove());
    if (originalEasyMde) {
      globalThis.EasyMDE = originalEasyMde;
    } else {
      delete globalThis.EasyMDE;
    }
  });

  it("initializes EasyMDE with the provided content", async () => {
    // Render the markdown-editor fixture.
    const element = await mountLitComponent("markdown-editor", {
      content: "# Hello",
      mini: true,
      name: "description",
    });

    // The EasyMDE editor receives the provided content and textarea element.
    expect(latestEditor.options.initialValue).to.equal("# Hello");
    expect(latestEditor.options.element).to.equal(
      element.querySelector("textarea"),
    );
    expect(element.querySelector("textarea").style.display).to.equal("block");
  });

  it("keeps the validation textarea out of the tab order and accessibility tree", async () => {
    // Render the markdown-editor fixture.
    const element = await mountLitComponent("markdown-editor", { name: "description" });

    // Only the EasyMDE editor is exposed; the textarea carries the value and validation.
    const textarea = element.querySelector("textarea");
    expect(textarea.getAttribute("aria-hidden")).to.equal("true");
    expect(textarea.tabIndex).to.equal(-1);
  });

  it("keeps the EasyMDE input in the tab order", async () => {
    // Render the markdown-editor fixture.
    await mountLitComponent("markdown-editor", { name: "description" });

    // CodeMirror copies a non-zero textarea tabindex onto its input, so it must be 0 at init.
    expect(latestEditor.elementTabIndexAtInit).to.equal(0);
  });

  it("renders single line breaks in the preview like the server does", async () => {
    // Render the markdown-editor fixture.
    await mountLitComponent("markdown-editor");

    // The preview treats single line breaks as soft breaks.
    expect(latestEditor.options.renderingConfig).to.deep.equal({
      singleLineBreaks: false,
    });
  });

  it("forwards editor changes through the onChange callback", async () => {
    // Track values emitted from the EasyMDE change handler.
    const values = [];

    // Render the markdown-editor fixture.
    await mountLitComponent("markdown-editor", {
      onChange: (value) => values.push(value),
    });

    // Assert the EasyMDE change handler.
    latestEditor._changeHandler();

    // The markdown editor forwards the updated EasyMDE value.
    expect(values).to.deep.equal(["## Updated"]);
  });

  it("applies the optional input id to the textarea", async () => {
    // Render the markdown-editor fixture with a labelable input id.
    const element = await mountLitComponent("markdown-editor", {
      inputId: "description-input",
    });

    // The textarea receives the id without requiring the host id to match.
    expect(element.querySelector("textarea")?.id).to.equal("description-input");
  });

  it("disables external CDN downloads and renders local inline SVG toolbar icons", async () => {
    // Render the markdown-editor fixture.
    await mountLitComponent("markdown-editor");

    // Verify Font Awesome CDN injection and CodeMirror CDN spellcheck are disabled.
    expect(latestEditor.options.autoDownloadFontAwesome).to.equal(false);
    expect(latestEditor.options.spellChecker).to.equal(false);

    // Verify every toolbar button uses a local inline SVG icon and an EasyMDE action.
    const buttons = latestEditor.options.toolbar.filter((item) => typeof item === "object");
    expect(buttons.map((button) => button.name)).to.deep.equal([
      "bold",
      "italic",
      "heading",
      "quote",
      "unordered-list",
      "ordered-list",
      "check-list",
      "link",
      "table",
      "horizontal-rule",
      "preview",
      "undo",
      "redo",
    ]);
    for (const button of buttons) {
      expect(typeof button.action, button.name).to.equal("function");
      expect(button.className, button.name).to.equal(undefined);
      expect(button.icon, button.name).to.include("<svg ");
      expect(button.icon, button.name).to.include('aria-hidden="true"');
      expect(button.icon, button.name).to.include("</svg>");
    }
  });

  it("lazy-loads EasyMDE CSS before styles.css and JS, preserving pending textarea updates and reactive disabled state", async () => {
    // Place an app stylesheet in head and start without EasyMDE loaded.
    const appStylesheet = document.createElement("link");
    appStylesheet.rel = "stylesheet";
    appStylesheet.href = "/static/css/styles.12345678.css";
    document.head.append(appStylesheet);
    delete globalThis.EasyMDE;

    // Mount the editor and verify the textarea stays visible and accessible while assets load.
    const element = await mountLitComponent("markdown-editor", {
      content: "Initial",
      name: "description",
    });
    expect(latestEditor).to.equal(null);

    const textarea = element.querySelector("textarea");
    expect(textarea.hasAttribute("aria-hidden")).to.equal(false);
    expect(textarea.tabIndex).to.equal(0);
    expect(textarea.classList.contains("opacity-0")).to.equal(false);

    const link = document.head.querySelector(
      'link[rel="stylesheet"][href="/static/vendor/css/easymde.v2.21.0.min.css"]',
    );
    const script = document.head.querySelector(
      'script[src="/static/vendor/js/easymde.v2.21.0.min.js"]',
    );
    expect(link).not.to.equal(null);
    expect(link.nextElementSibling).to.equal(appStylesheet);
    expect(script).not.to.equal(null);

    textarea.value = "Updated while loading";
    element.disabled = true;

    // Complete asset loading and verify EasyMDE picks up the latest value and read-only state.
    globalThis.EasyMDE = MockEasyMde;
    link.onload();
    script.onload();
    await waitForMicrotask();
    await waitForMicrotask();

    const toolbarButton = element.querySelector(".editor-toolbar button");
    expect(latestEditor).not.to.equal(null);
    expect(latestEditor.options.initialValue).to.equal("Updated while loading");
    expect(latestEditor.setOptionCalls).to.deep.equal([{ name: "readOnly", value: "nocursor" }]);
    expect(toolbarButton.disabled).to.equal(true);
    expect(textarea.getAttribute("aria-hidden")).to.equal("true");
    expect(textarea.tabIndex).to.equal(-1);

    // Re-enabling the editor reactively unlocks CodeMirror and toolbar buttons.
    element.disabled = false;
    await element.updateComplete;
    expect(latestEditor.setOptionCalls).to.deep.equal([
      { name: "readOnly", value: "nocursor" },
      { name: "readOnly", value: false },
    ]);
    expect(toolbarButton.disabled).to.equal(false);
  });

  it("skips EasyMDE initialization while disconnected and initializes if reconnected later", async () => {
    // Mount without EasyMDE loaded, then disconnect the element before assets resolve.
    delete globalThis.EasyMDE;
    const element = await mountLitComponent("markdown-editor", {
      content: "Ephemeral",
      name: "description",
    });
    const link = document.head.querySelector(
      'link[rel="stylesheet"][href="/static/vendor/css/easymde.v2.21.0.min.css"]',
    );
    const script = document.head.querySelector(
      'script[src="/static/vendor/js/easymde.v2.21.0.min.js"]',
    );
    element.remove();

    // Complete loading after removal and verify EasyMDE is not instantiated while detached.
    globalThis.EasyMDE = MockEasyMde;
    link.onload();
    script.onload();
    await waitForMicrotask();
    await waitForMicrotask();

    expect(latestEditor).to.equal(null);

    // Reattach the element and verify EasyMDE initializes once connected again.
    document.body.append(element);
    expect(latestEditor).not.to.equal(null);
    expect(latestEditor.options.initialValue).to.equal("Ephemeral");
  });

  it("transfers focus and caret selection to CodeMirror when the user focused the fallback textarea while loading", async () => {
    // Mount without EasyMDE loaded, focus the visible textarea, and position the caret.
    delete globalThis.EasyMDE;
    const element = await mountLitComponent("markdown-editor", {
      content: "Hello world",
      name: "description",
    });
    const textarea = element.querySelector("textarea");
    textarea.focus();
    textarea.setSelectionRange(2, 5);
    expect(document.activeElement).to.equal(textarea);

    // Finish loading EasyMDE and verify focus and selection transfer to CodeMirror.
    const link = document.head.querySelector(
      'link[rel="stylesheet"][href="/static/vendor/css/easymde.v2.21.0.min.css"]',
    );
    const script = document.head.querySelector(
      'script[src="/static/vendor/js/easymde.v2.21.0.min.js"]',
    );
    globalThis.EasyMDE = MockEasyMde;
    link.onload();
    script.onload();
    await waitForMicrotask();
    await waitForMicrotask();

    expect(latestEditor.focused).to.equal(true);
    expect(latestEditor.selectionCalls).to.deep.equal([
      { anchor: { ch: 2, line: 0 }, head: { ch: 5, line: 0 } },
    ]);
  });

  it("keeps the fallback textarea usable, labeled, and forwarding onChange when EasyMDE assets fail to load", async () => {
    // Suppress expected error logging during the simulated asset failure.
    const originalConsoleError = console.error;
    console.error = () => {};

    try {
      // Mount a host-for label and editor without EasyMDE, then fail both asset loads.
      delete globalThis.EasyMDE;
      const label = document.createElement("label");
      label.htmlFor = "description";
      label.textContent = "Description *";
      document.body.append(label);

      const changes = [];
      const element = await mountLitComponent("markdown-editor", {
        content: "Fallback body",
        id: "description",
        name: "description",
        onChange: (value) => changes.push(value),
      });
      const link = document.head.querySelector(
        'link[rel="stylesheet"][href="/static/vendor/css/easymde.v2.21.0.min.css"]',
      );
      const script = document.head.querySelector(
        'script[src="/static/vendor/js/easymde.v2.21.0.min.js"]',
      );
      link.onerror();
      script.onerror();
      await waitForMicrotask();
      await waitForMicrotask();

      // Verify the textarea stays visible, labeled, keyboard accessible, and forwards input updates.
      const textarea = element.querySelector("textarea");
      expect(latestEditor).to.equal(null);
      expect(textarea.value).to.equal("Fallback body");
      expect(textarea.getAttribute("aria-label")).to.equal("Description *");
      expect(textarea.hasAttribute("aria-hidden")).to.equal(false);
      expect(textarea.tabIndex).to.equal(0);
      expect(textarea.classList.contains("opacity-0")).to.equal(false);
      expect(textarea.classList.contains("input-primary")).to.equal(true);

      textarea.value = "Typed into fallback";
      textarea.dispatchEvent(new Event("input", { bubbles: true }));
      expect(changes).to.deep.equal(["Typed into fallback"]);
    } finally {
      console.error = originalConsoleError;
    }
  });

  it("initializes normally after an earlier full asset load failure", async () => {
    // Verify the previous full failure did not poison stylesheet readiness for subsequent editors.
    const element = await mountLitComponent("markdown-editor", {
      content: "Recovered",
      name: "description",
    });

    expect(latestEditor).not.to.equal(null);
    expect(latestEditor.options.initialValue).to.equal("Recovered");
    expect(element.querySelector("textarea").getAttribute("aria-hidden")).to.equal("true");
  });
});
