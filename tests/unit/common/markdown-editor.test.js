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
      constructor(options) {
        this.options = options;
        this._changeHandler = null;
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

  it("forwards editor changes through the onChange callback", async () => {
    // Track values emitted from the EasyMDE change handler.
    const values = [];

    // Render the markdown-editor fixture.
    await mountLitComponent("markdown-editor", {
      onChange: (value) => values.push(value),
    });

    // Trigger the EasyMDE change handler.
    latestEditor._changeHandler();

    // The markdown editor forwards the updated EasyMDE value.
    expect(values).to.deep.equal(["## Updated"]);
  });
});
