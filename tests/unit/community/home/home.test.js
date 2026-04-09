import { expect } from "@open-wc/testing";

import { loadExplorePage } from "/static/js/community/home/home.js";
import { resetDom, setLocationPath } from "/tests/unit/test-utils/dom.js";

describe("community home", () => {
  beforeEach(() => {
    resetDom();
    setLocationPath("/");
  });

  afterEach(() => {
    resetDom();
    setLocationPath("/");
  });

  it("leaves the current page untouched when the search input is empty", () => {
    const input = document.createElement("input");
    input.id = "ts_query";
    input.value = "";
    document.body.append(input);

    loadExplorePage();

    expect(window.location.pathname).to.equal("/");
  });
});
