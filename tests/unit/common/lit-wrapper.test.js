import { expect } from "@open-wc/testing";
import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

describe("lit-wrapper", () => {
  before(() => {
    if (!customElements.get("test-lit-wrapper")) {
      class TestLitWrapper extends LitWrapper {
        render() {
          return html`<span>content</span>`;
        }
      }

      customElements.define("test-lit-wrapper", TestLitWrapper);
    }
  });

  it("returns the element as its own render root", () => {
    const element = document.createElement("test-lit-wrapper");

    expect(element.createRenderRoot()).to.equal(element);
  });

  it("clears existing children before reusing the light-dom root", () => {
    const element = document.createElement("test-lit-wrapper");
    element.innerHTML = "<span>stale</span>";

    const root = element.createRenderRoot();

    expect(root).to.equal(element);
    expect(element.innerHTML).to.equal("");
  });
});
