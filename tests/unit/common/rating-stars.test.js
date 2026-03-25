import { expect } from "@open-wc/testing";

import "/static/js/common/rating-stars.js";

describe("rating-stars", () => {
  afterEach(() => {
    document.body.innerHTML = "";
  });

  it("renders the expected label and fractional star fill", async () => {
    const element = document.createElement("rating-stars");
    element.averageRating = 3.5;
    document.body.append(element);

    await element.updateComplete;

    const image = element.querySelector('[role="img"]');
    const fillWidths = Array.from(element.querySelectorAll(".absolute")).map((node) => node.style.width);

    expect(image?.getAttribute("aria-label")).to.equal("3.50 out of 5 stars");
    expect(fillWidths).to.deep.equal(["100%", "100%", "100%", "50%", "0%"]);
  });

  it("clamps out-of-range and invalid ratings", async () => {
    const element = document.createElement("rating-stars");
    document.body.append(element);

    element.averageRating = 12;
    await element.updateComplete;

    let image = element.querySelector('[role="img"]');
    expect(image?.getAttribute("aria-label")).to.equal("5.00 out of 5 stars");

    element.averageRating = Number.NaN;
    await element.updateComplete;

    image = element.querySelector('[role="img"]');
    expect(image?.getAttribute("aria-label")).to.equal("0.00 out of 5 stars");
  });
});
