import { expect } from "@open-wc/testing";

import "/static/js/common/markdown-editor.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("markdown-editor", () => {
  const originalEasyMde = globalThis.EasyMDE;
  let latestEditor;

  useMountedElementsCleanup("markdown-editor");

  beforeEach(() => {
    latestEditor = null;
    globalThis.EasyMDE = class {
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
        latestEditor = this;
        this.codemirror = {
          on: (eventName, handler) => {
            if (eventName === "change") {
              this._changeHandler = handler;
            }
          },
        };
      }

      value() {
        return "## Updated";
      }
    };
  });

  afterEach(() => {
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
});
