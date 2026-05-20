import { expect } from "@open-wc/testing";

import "/static/js/common/rating-stars.js";

describe("rating-stars", () => {
  afterEach(() => {
    document.body.innerHTML = "";
  });

  it("renders the expected label and fractional star fill", async () => {
    // Create the rating-stars fixture element.
    const element = document.createElement("rating-stars");
    element.averageRating = 3.5;
    document.body.append(element);

    // Let the component finish rendering.
    await element.updateComplete;

    // Collect the image and fill widths elements.
    const image = element.querySelector('[role="img"]');
    const fillWidths = Array.from(element.querySelectorAll(".absolute")).map(
      (node) => node.style.width,
    );

    // Renders the expected label and fractional star fill.
    expect(image?.getAttribute("aria-label")).to.equal("3.50 out of 5 stars");
    expect(fillWidths).to.deep.equal(["100%", "100%", "100%", "50%", "0%"]);
  });

  it("clamps out-of-range and invalid ratings", async () => {
    // Create the rating-stars fixture element.
    const element = document.createElement("rating-stars");
    document.body.append(element);

    // Set up clamps out-of-range and invalid ratings.
    element.averageRating = 12;
    await element.updateComplete;

    // Track the value under test.
    let image = element.querySelector('[role="img"]');
    expect(image?.getAttribute("aria-label")).to.equal("5.00 out of 5 stars");

    // Set up clamps out-of-range and invalid ratings.
    element.averageRating = Number.NaN;
    await element.updateComplete;

    // Collect the controls used by the interaction.
    image = element.querySelector('[role="img"]');
    expect(image?.getAttribute("aria-label")).to.equal("0.00 out of 5 stars");
  });
});
