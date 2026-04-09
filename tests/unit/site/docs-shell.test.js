import { expect } from "@open-wc/testing";

import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("site docs shell", () => {
  afterEach(() => {
    resetDom();
  });

  it("loads safely when the docs root is not present", async () => {
    await import(`/static/js/site/docs-shell.js?test=${Date.now()}`);

    expect(document.querySelector(".ocg-docs-root")).to.equal(null);
  });
});
