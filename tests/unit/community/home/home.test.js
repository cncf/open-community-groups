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
    // Prepare input for leaving the current page untouched when the search input.
    const input = document.createElement("input");
    input.id = "ts_query";
    input.value = "";
    document.body.append(input);

    // Empty search text keeps the current page unchanged.
    loadExplorePage();

    // Empty searches leave the current page unchanged.
    expect(window.location.pathname).to.equal("/");
  });

  it("redirects to explore with the text search query when the input is filled", () => {
    // Prepare assigned URLs for redirecting to explore with the text search query.
    const assignedUrls = [];
    const executeLoadExplorePage = new Function(
      "document",
      `const loadExplorePage = ${loadExplorePage.toString()}; return loadExplorePage();`,
    );

    // Search text redirects to the explore page.
    executeLoadExplorePage({
      getElementById(id) {
        if (id === "ts_query") {
          return { value: "cloud native" };
        }
        return null;
      },
      location: {
        assign(url) {
          assignedUrls.push(url);
        },
      },
    });

    // Submitted search text is included in the explore redirect.
    expect(assignedUrls).to.deep.equal(["/explore?ts_query=cloud%20native"]);
  });
});
