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

  it("redirects to explore with the text search query when the input is filled", () => {
    const assignedUrls = [];
    const executeLoadExplorePage = new Function(
      "document",
      `const loadExplorePage = ${loadExplorePage.toString()}; return loadExplorePage();`,
    );

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

    expect(assignedUrls).to.deep.equal(["/explore?ts_query=cloud%20native"]);
  });
});
