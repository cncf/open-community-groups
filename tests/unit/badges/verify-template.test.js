import { expect } from "@open-wc/testing";

describe("badge verify template", () => {
  it("shows the result above the form on phones without moving it in the DOM", async () => {
    // Load the public verification template.
    const response = await fetch("/ocg-server/templates/badges/verify.html");

    expect(response.ok).to.equal(true);
    const template = await response.text();

    // Verify the form still comes first, so desktop keeps its order.
    expect(template.indexOf("<form")).to.be.lessThan(template.indexOf('aria-live="polite"'));
    expect(template).to.include('<div class="w-full phone:flex phone:flex-col-reverse">');

    // Verify an empty live region adds no gap.
    expect(template).to.include('<div class="mt-6 phone:mt-0 phone:has-[>*]:mb-3" aria-live="polite">');
  });

  it("flattens the result rows on phones", async () => {
    // Load the public verification template.
    const response = await fetch("/ocg-server/templates/badges/verify.html");

    expect(response.ok).to.equal(true);
    const template = await response.text();

    // Verify all three optional and fixed rows are covered.
    expect(template.match(/<div class="contents phone:block">/gu)).to.have.length(3);
    expect(template.match(/phone:mt-0\.5/gu)).to.have.length(3);
    expect(template).to.include('<div class="min-w-0 phone:contents">');
  });
});
