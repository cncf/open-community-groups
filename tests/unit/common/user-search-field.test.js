import { expect } from "@open-wc/testing";

import "/static/js/common/user-search-field.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("user-search-field", () => {
  let fetchMock;

  beforeEach(() => {
    fetchMock = mockFetch();
  });

  afterEach(() => {
    fetchMock.restore();
    removeMountedElements("user-search-field");
    resetDom();
  });

  it("searches users and excludes configured usernames", async () => {
    fetchMock.setImpl(async () => ({
      ok: true,
      async json() {
        return [
          { user_id: "1", username: "ada", name: "Ada Lovelace" },
          { user_id: "2", username: "grace", name: "Grace Hopper" },
        ];
      },
    }));

    const element = await mountLitComponent("user-search-field", {
      excludeUsernames: ["grace"],
    });

    await element._performSearch("a");

    expect(element._searchResults).to.deep.equal([{ user_id: "1", username: "ada", name: "Ada Lovelace" }]);
  });

  it("emits the selected user and clears the search state", async () => {
    const element = await mountLitComponent("user-search-field");
    const received = [];

    element.addEventListener("user-selected", (event) => {
      received.push(event.detail.user);
    });

    element._searchQuery = "ada";
    element._searchResults = [{ user_id: "1", username: "ada" }];
    element._selectUser({ user_id: "1", username: "ada" });

    expect(received).to.deep.equal([{ user_id: "1", username: "ada" }]);
    expect(element._searchQuery).to.equal("");
    expect(element._searchResults).to.deep.equal([]);
  });

  it("clears stale results after a failed search request", async () => {
    fetchMock.setImpl(async () => ({
      ok: false,
      status: 500,
    }));

    const element = await mountLitComponent("user-search-field");
    element._searchResults = [{ user_id: "9", username: "stale" }];
    element._isSearching = true;

    await element._performSearch("ada");

    expect(element._searchResults).to.deep.equal([]);
    expect(element._isSearching).to.equal(false);
  });

  it("does not search or emit selections while disabled", async () => {
    const element = await mountLitComponent("user-search-field", {
      disabled: true,
      searchDelay: 0,
    });
    const received = [];

    element.addEventListener("user-selected", (event) => {
      received.push(event.detail.user);
    });

    element._handleSearchInput({
      target: { value: "ada" },
    });
    await waitForMicrotask();
    element._selectUser({ user_id: "1", username: "ada" });

    expect(fetchMock.calls).to.have.length(0);
    expect(received).to.deep.equal([]);
    expect(element._searchQuery).to.equal("");
  });
});
