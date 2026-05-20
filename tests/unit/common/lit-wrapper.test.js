import { expect } from "@open-wc/testing";
import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
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
    // Create the test-lit-wrapper fixture element.
    const element = document.createElement("test-lit-wrapper");

    // Returned the element as its own render root.
    expect(element.createRenderRoot()).to.equal(element);
  });

  it("clears restored light-dom markup before the first render", async () => {
    // Create the test-lit-wrapper fixture element.
    const element = document.createElement("test-lit-wrapper");
    element.innerHTML = "<span>stale</span>";
    document.body.append(element);

    // Let the component finish rendering.
    await element.updateComplete;

    // Collect the rendered spans element.
    const renderedSpans = element.querySelectorAll("span");

    // The rendered text shows the scenario data.
    expect(renderedSpans).to.have.length(1);
    expect(renderedSpans[0]?.textContent).to.equal("content");
  });

  it("does not clear its own rendered content on reconnect", async () => {
    // Create the test-lit-wrapper fixture element.
    const element = document.createElement("test-lit-wrapper");
    document.body.append(element);

    // Let the component finish rendering.
    await element.updateComplete;

    // Reconnect the fixture element.
    element.remove();
    document.body.append(element);

    // Let the component finish rendering.
    await element.updateComplete;

    // Collect the rendered spans element.
    const renderedSpans = element.querySelectorAll("span");

    // No clear its own rendered content on reconnect.
    expect(renderedSpans).to.have.length(1);
    expect(renderedSpans[0]?.textContent).to.equal("content");
  });
});
