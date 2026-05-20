import { expect } from "@open-wc/testing";

import "/static/js/common/svg-spinner.js";

describe("svg-spinner", () => {
  afterEach(() => {
    document.body.innerHTML = "";
  });

  it("renders the default loading state", async () => {
    // Create the svg-spinner fixture element.
    const element = document.createElement("svg-spinner");
    document.body.append(element);

    // Let the component finish rendering.
    await element.updateComplete;

    // Collect the status, paths, and screen reader label elements.
    const status = element.querySelector('[role="status"]');
    const paths = element.querySelectorAll("path");
    const screenReaderLabel = element.querySelector(".sr-only");

    // The rendered text shows the scenario data.
    expect(status?.getAttribute("aria-label")).to.equal("Loading...");
    expect(status?.className).to.include("size-5");
    expect(paths[0]?.getAttribute("fill")).to.equal("#e5e7eb");
    expect(paths[1]?.getAttribute("fill")).to.equal("var(--color-primary-500)");
    expect(screenReaderLabel?.textContent).to.equal("Loading...");
  });

  it("applies explicit size, label, and colors", async () => {
    // Create the svg-spinner fixture element.
    const element = document.createElement("svg-spinner");
    element.size = "size-8";
    element.label = "Fetching data";
    element.accentColor = "#123456";
    element.backgroundColor = "#abcdef";
    document.body.append(element);

    // Let the component finish rendering.
    await element.updateComplete;

    // Collect the status, paths, and screen reader label elements.
    const status = element.querySelector('[role="status"]');
    const paths = element.querySelectorAll("path");
    const screenReaderLabel = element.querySelector(".sr-only");

    // The rendered text shows the scenario data.
    expect(status?.getAttribute("aria-label")).to.equal("Fetching data");
    expect(status?.className).to.include("size-8");
    expect(paths[0]?.getAttribute("fill")).to.equal("#abcdef");
    expect(paths[1]?.getAttribute("fill")).to.equal("#123456");
    expect(screenReaderLabel?.textContent).to.equal("Fetching data");
  });
});
