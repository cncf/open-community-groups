import { expect } from "@open-wc/testing";
import { html } from "/static/vendor/js/lit-all.v3.3.2.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

describe("lit-wrapper", () => {
  afterEach(() => {
    document.body.innerHTML = "";
  });

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

  it("clears restored light-dom markup before the first render", async () => {
    const element = document.createElement("test-lit-wrapper");
    element.innerHTML = "<span>stale</span>";
    document.body.append(element);

    await element.updateComplete;

    const renderedSpans = element.querySelectorAll("span");

    expect(renderedSpans).to.have.length(1);
    expect(renderedSpans[0]?.textContent).to.equal("content");
  });

  it("does not clear its own rendered content on reconnect", async () => {
    const element = document.createElement("test-lit-wrapper");
    document.body.append(element);

    await element.updateComplete;

    element.remove();
    document.body.append(element);

    await element.updateComplete;

    const renderedSpans = element.querySelectorAll("span");

    expect(renderedSpans).to.have.length(1);
    expect(renderedSpans[0]?.textContent).to.equal("content");
  });
});
