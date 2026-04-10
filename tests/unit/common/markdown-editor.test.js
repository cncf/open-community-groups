import { expect } from "@open-wc/testing";

import "/static/js/common/markdown-editor.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

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
    const element = await mountLitComponent("markdown-editor", {
      content: "# Hello",
      mini: true,
      name: "description",
    });

    expect(latestEditor.options.initialValue).to.equal("# Hello");
    expect(latestEditor.options.element).to.equal(element.querySelector("textarea"));
    expect(element.querySelector("textarea").style.display).to.equal("block");
  });

  it("forwards editor changes through the onChange callback", async () => {
    const values = [];

    await mountLitComponent("markdown-editor", {
      onChange: (value) => values.push(value),
    });

    latestEditor._changeHandler();

    expect(values).to.deep.equal(["## Updated"]);
  });
});
