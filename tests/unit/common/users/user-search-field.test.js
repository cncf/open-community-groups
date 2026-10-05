import { expect } from "@open-wc/testing";

import { focusUserSearchField } from "/static/js/common/users/user-search-field.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { renderViewportBottomLayout } from "/tests/unit/test-utils/dom.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("user-search-field", () => {
  useMountedElementsCleanup("user-search-field");

  let fetchMock;
  let originalSetTimeout;
  let originalClearTimeout;

  beforeEach(() => {
    fetchMock = mockFetch();
    originalSetTimeout = window.setTimeout;
    originalClearTimeout = window.clearTimeout;
  });

  afterEach(() => {
    fetchMock.restore();
    window.setTimeout = originalSetTimeout;
    window.clearTimeout = originalClearTimeout;
  });

  it("focuses user search fields inside a root", () => {
    // Build a root with a user search field.
    const root = document.createElement("section");
    const field = document.createElement("user-search-field");
    let focusCount = 0;
    field.focusInput = () => {
      focusCount += 1;
    };
    root.append(field);

    // The helper focuses the field and returns it.
    expect(focusUserSearchField(root)).to.equal(field);
    expect(focusCount).to.equal(1);
    expect(focusUserSearchField(document.createElement("section"))).to.equal(null);
  });

  it("searches users and excludes configured usernames", async () => {
    // Mock the fetch response.
    fetchMock.setImpl(async () => ({
      ok: true,
      async json() {
        return [
          { user_id: "1", username: "ada", name: "Ada Lovelace" },
          { user_id: "2", username: "grace", name: "Grace Hopper" },
        ];
      },
    }));

    // Render the user-search-field fixture.
    const element = await mountLitComponent("user-search-field", {
      excludeUsernames: ["grace"],
    });

    // Search for the requested value.
    await element._performSearch("a");

    // Searches users and excludes configured usernames.
    expect(fetchMock.calls[0][1].headers.get("X-OCG-Fetch")).to.equal("true");
    expect(element._searchResults).to.deep.equal([
      { user_id: "1", username: "ada", name: "Ada Lovelace" },
    ]);
  });

  it("emits the selected user and clears the search state", async () => {
    // Render the user-search-field fixture.
    const element = await mountLitComponent("user-search-field");
    const received = [];
    const queries = [];

    // Listen for the emitted event.
    element.addEventListener("user-selected", (event) => {
      received.push(event.detail.user);
    });
    element.addEventListener("user-search-query-changed", (event) => {
      queries.push(event.detail.query);
    });

    // Select a search result and reset the search state.
    element._searchQuery = "ada";
    element._searchResults = [{ user_id: "1", username: "ada" }];
    element._selectUser({ user_id: "1", username: "ada" });

    // The selected user is emitted and the search state is cleared.
    expect(received).to.deep.equal([{ user_id: "1", username: "ada" }]);
    expect(queries).to.deep.equal([]);
    expect(element._searchQuery).to.equal("");
    expect(element._searchResults).to.deep.equal([]);
  });

  it("emits query changes while typing and clearing", async () => {
    // Mount a search field and capture query-change events.
    const element = await mountLitComponent("user-search-field");
    const queries = [];

    // Listen for the user-search-query-changed event.
    element.addEventListener("user-search-query-changed", (event) => {
      queries.push(event.detail.query);
    });

    // Type a search query into the component.
    element._handleSearchInput({ target: { value: "ada@example.com" } });
    element.clearSearch({ refocus: false });

    // Assert the emitted payload.
    expect(queries).to.deep.equal(["ada@example.com", ""]);
  });

  it("renders an opt-in email action for valid email queries with no matches", async () => {
    // Mount a search field with the email action enabled.
    const element = await mountLitComponent("user-search-field", {
      emailActionEnabled: true,
      emailActionText: "Invite by email",
    });
    const selectedEmails = [];

    // Listen for the email-action-selected event.
    element.addEventListener("email-action-selected", (event) => {
      selectedEmails.push(event.detail.email);
    });

    // Seed the current search query.
    element._searchQuery = "ada@example.com";
    element._searchResults = [];
    await element.updateComplete;

    // Verify renders an opt-in email action for valid email queries with no matches.
    expect(element.textContent).to.contain("ada@example.com");
    expect(element.textContent).to.contain("Invite by email");
    expect(element.textContent).not.to.contain("No users found");
    expect(element.querySelector(".icon-add-circle")).to.exist;

    // Click Invite by email ada@example.com.
    element.querySelector("button[aria-label='Invite by email ada@example.com']")?.click();

    // Assert the emitted payload.
    expect(selectedEmails).to.deep.equal(["ada@example.com"]);
  });

  it("keeps the default no-results message when the email action is not enabled", async () => {
    // Mount a search field without the email action enabled.
    const element = await mountLitComponent("user-search-field");

    // Seed the current search query.
    element._searchQuery = "ada@example.com";
    element._searchResults = [];
    await element.updateComplete;

    // Assert the expected copy is rendered.
    expect(element.textContent).to.contain('No users found for "ada@example.com"');
  });

  it("clears stale results after a failed search request", async () => {
    // Mock a failed search response.
    fetchMock.setImpl(async () => ({
      ok: false,
      status: 500,
    }));

    // Render the user-search-field fixture.
    const element = await mountLitComponent("user-search-field");
    element._searchResults = [{ user_id: "9", username: "stale" }];
    element._isSearching = true;

    // Search while stale results are present.
    await element._performSearch("ada");

    // Failed searches clear stale results and loading state.
    expect(element._searchResults).to.deep.equal([]);
    expect(element._isSearching).to.equal(false);
  });

  it("does not search or emit selections while disabled", async () => {
    // Render the user-search-field fixture.
    const element = await mountLitComponent("user-search-field", {
      disabled: true,
      searchDelay: 0,
    });
    const received = [];

    // Track any selection events emitted while disabled.
    element.addEventListener("user-selected", (event) => {
      received.push(event.detail.user);
    });

    // Type and select while the field is disabled.
    element._handleSearchInput({
      target: { value: "ada" },
    });
    await waitForMicrotask();
    element._selectUser({ user_id: "1", username: "ada" });

    // Disabled fields neither search nor emit selections.
    expect(fetchMock.calls).to.have.length(0);
    expect(received).to.deep.equal([]);
    expect(element._searchQuery).to.equal("");
  });

  it("cancels the previous debounced search when a new query is typed", async () => {
    // Track scheduled searches so cancellation can be inspected.
    const scheduledCallbacks = new Map();
    let nextTimerId = 0;

    // Replace timers with controllable debounced callbacks.
    window.setTimeout = (callback) => {
      nextTimerId += 1;
      scheduledCallbacks.set(nextTimerId, callback);
      return nextTimerId;
    };
    window.clearTimeout = (timerId) => {
      scheduledCallbacks.delete(timerId);
    };

    // Mock the fetch response.
    fetchMock.setImpl(async () => ({
      ok: true,
      async json() {
        return [{ user_id: "2", username: "grace", name: "Grace Hopper" }];
      },
    }));

    // Render the user-search-field fixture.
    const element = await mountLitComponent("user-search-field", {
      searchDelay: 25,
    });

    // Type a second query before the first debounce runs.
    element._handleSearchInput({ target: { value: "ada" } });
    element._handleSearchInput({ target: { value: "grace" } });

    // Only the latest debounced search remains scheduled.
    expect(scheduledCallbacks.size).to.equal(1);

    // Run the remaining debounced search callback.
    const [pendingSearch] = scheduledCallbacks.values();
    await pendingSearch();

    // The request uses the latest query only.
    expect(fetchMock.calls).to.have.length(1);
    expect(fetchMock.calls[0][0]).to.equal(
      "/dashboard/group/users/search?q=grace",
    );
  });

  it("shows a minimum length hint without searching one-character queries", async () => {
    // Render the user-search-field fixture.
    const element = await mountLitComponent("user-search-field", {
      searchDelay: 0,
    });

    // Type a single character.
    element._handleSearchInput({ target: { value: "a" } });
    await waitForMicrotask();
    await element.updateComplete;

    // The hint is shown and no request is sent.
    expect(fetchMock.calls).to.have.length(0);
    expect(element._isSearching).to.equal(false);
    expect(element.textContent).to.contain("Type at least 2 characters");
    expect(element.textContent).not.to.contain("No users found");
  });

  it("counts a single emoji as one character when checking the minimum length", async () => {
    // Render the user-search-field fixture.
    const element = await mountLitComponent("user-search-field", {
      searchDelay: 0,
    });

    // Type a single supplementary-plane character.
    element._handleSearchInput({ target: { value: "😀" } });
    await waitForMicrotask();
    await element.updateComplete;

    // The hint is shown and no request is sent.
    expect(fetchMock.calls).to.have.length(0);
    expect(element.textContent).to.contain("Type at least 2 characters");
  });

  it("treats whitespace-only queries as empty", async () => {
    // Render the user-search-field fixture.
    const element = await mountLitComponent("user-search-field", {
      searchDelay: 0,
    });

    // Type only whitespace.
    element._handleSearchInput({ target: { value: "   " } });
    await waitForMicrotask();
    await element.updateComplete;

    // The query is empty, no dropdown is rendered and no request is sent.
    expect(fetchMock.calls).to.have.length(0);
    expect(element._searchQuery).to.equal("");
    expect(element.textContent).not.to.contain("Type at least 2 characters");
  });

  it("searches two-character queries after the debounce", async () => {
    // Replace timers with controllable debounced callbacks.
    const scheduledCallbacks = useControlledTimers();

    // Mock the fetch response.
    fetchMock.setImpl(async () => ({
      ok: true,
      async json() {
        return [{ user_id: "1", username: "ada", name: "Ada Lovelace" }];
      },
    }));

    // Render the user-search-field fixture and type two characters.
    const element = await mountLitComponent("user-search-field", {
      searchDelay: 25,
    });
    element._handleSearchInput({ target: { value: "ad" } });

    // No request is sent before the debounce runs.
    expect(fetchMock.calls).to.have.length(0);
    expect(element._isSearching).to.equal(true);

    // Run the debounced search callback.
    const [pendingSearch] = scheduledCallbacks.values();
    await pendingSearch();

    // The request is sent and its results are applied.
    expect(fetchMock.calls).to.have.length(1);
    expect(fetchMock.calls[0][0]).to.equal("/dashboard/group/users/search?q=ad");
    expect(element._searchResults).to.deep.equal([
      { user_id: "1", username: "ada", name: "Ada Lovelace" },
    ]);
    expect(element._isSearching).to.equal(false);
  });

  it("ignores a pending response after the query becomes too short", async () => {
    // Replace timers and keep search responses pending.
    const scheduledCallbacks = useControlledTimers();
    const pendingResponses = deferFetchResponses(fetchMock);

    // Render the user-search-field fixture and start searching for "ab".
    const element = await mountLitComponent("user-search-field", {
      searchDelay: 25,
    });
    element._handleSearchInput({ target: { value: "ab" } });
    const [pendingSearch] = scheduledCallbacks.values();
    const searchDone = pendingSearch();

    // Shorten the query to one character, then resolve the "ab" response.
    element._handleSearchInput({ target: { value: "a" } });
    pendingResponses[0].resolve([{ user_id: "1", username: "ab-user" }]);
    await searchDone;

    // The stale response is aborted and ignored.
    expect(pendingResponses[0].signal.aborted).to.equal(true);
    expect(element._searchResults).to.deep.equal([]);
    expect(element._isSearching).to.equal(false);
  });

  it("keeps the latest results when an older response resolves last", async () => {
    // Replace timers and keep search responses pending.
    const scheduledCallbacks = useControlledTimers();
    const pendingResponses = deferFetchResponses(fetchMock);

    // Render the user-search-field fixture and start searching for "ab".
    const element = await mountLitComponent("user-search-field", {
      searchDelay: 25,
    });
    element._handleSearchInput({ target: { value: "ab" } });
    const firstSearchDone = [...scheduledCallbacks.values()].at(-1)();

    // Start searching for "abc" while "ab" is still pending.
    element._handleSearchInput({ target: { value: "abc" } });
    const secondSearchDone = [...scheduledCallbacks.values()].at(-1)();

    // Resolve "abc" first.
    pendingResponses[1].resolve([{ user_id: "2", username: "abc-user" }]);
    await secondSearchDone;
    expect(element._searchResults).to.deep.equal([{ user_id: "2", username: "abc-user" }]);
    expect(element._isSearching).to.equal(false);

    // Resolve "ab" last.
    pendingResponses[0].resolve([{ user_id: "1", username: "ab-user" }]);
    await firstSearchDone;

    // The latest results and loading state remain.
    expect(pendingResponses[0].signal.aborted).to.equal(true);
    expect(element._searchResults).to.deep.equal([{ user_id: "2", username: "abc-user" }]);
    expect(element._isSearching).to.equal(false);
  });

  it("aborts in-flight searches when clearing the query", async () => {
    // Keep search responses pending.
    const pendingResponses = deferFetchResponses(fetchMock);

    // Render the user-search-field fixture and start a search.
    const element = await mountLitComponent("user-search-field");
    element._searchQuery = "ada";
    element._isSearching = true;
    const searchDone = element._performSearch("ada");

    // Clear the query, then resolve the pending response.
    element.clearSearch({ refocus: false });
    pendingResponses[0].resolve([{ user_id: "1", username: "ada" }]);
    await searchDone;

    // The request is aborted and its results are ignored.
    expect(pendingResponses[0].signal.aborted).to.equal(true);
    expect(element._searchResults).to.deep.equal([]);
    expect(element._isSearching).to.equal(false);
  });

  it("aborts in-flight searches on disconnect", async () => {
    // Keep search responses pending.
    const pendingResponses = deferFetchResponses(fetchMock);

    // Render the user-search-field fixture and start a search.
    const element = await mountLitComponent("user-search-field");
    const searchDone = element._performSearch("ada");

    // Remove the field, then resolve the pending response.
    element.remove();
    pendingResponses[0].resolve([{ user_id: "1", username: "ada" }]);
    await searchDone;

    // The request is aborted and its results are ignored.
    expect(pendingResponses[0].signal.aborted).to.equal(true);
    expect(element._searchResults).to.deep.equal([]);
  });

  it("clears the dropdown when clicking outside the component", async () => {
    // Render the user-search-field fixture.
    const element = await mountLitComponent("user-search-field");

    // Seed visible search results before the outside click.
    element._searchQuery = "ada";
    element._searchResults = [{ user_id: "1", username: "ada" }];
    element._isSearching = true;

    // Handle outside pointer events and hide the search results.
    element._handleOutsidePointer({
      target: document.body,
    });

    // Outside clicks clear the query, results, and loading state.
    expect(element._searchQuery).to.equal("");
    expect(element._searchResults).to.deep.equal([]);
    expect(element._isSearching).to.equal(false);
  });

  it("keeps focus on the outside target when clicking outside the component", async () => {
    // Render a search field next to a focusable control the user points at.
    const element = await mountLitComponent("user-search-field");
    const outsideButton = document.createElement("button");
    outsideButton.type = "button";
    outsideButton.textContent = "Outside";
    document.body.append(outsideButton);

    try {
      // Focus the outside control as a pointer press would, then clear from outside.
      outsideButton.focus();
      element._searchQuery = "ada";
      element._handleOutsidePointer({
        target: outsideButton,
      });
      await element.updateComplete;
      await waitForMicrotask();

      // The query clears without pulling focus back into the search input.
      expect(element._searchQuery).to.equal("");
      expect(document.activeElement).to.equal(outsideButton);
    } finally {
      outsideButton.remove();
    }
  });

  it("can keep the query when clicking outside the component", async () => {
    // Mount a search field that persists the query on outside clicks.
    const element = await mountLitComponent("user-search-field", {
      persistQueryOnOutside: true,
    });

    // Seed the current search query.
    element._searchQuery = "ada@example.com";
    element._searchResults = [];

    // Click outside the search field.
    element._handleOutsidePointer({
      target: document.body,
    });

    // Assert that the outside click preserved the query.
    expect(element._searchQuery).to.equal("ada@example.com");
  });

  it("clears pending debounce timers and removes the outside-pointer listener on disconnect", async () => {
    // Track listener removal and cleared debounce timers.
    const originalDocumentRemoveEventListener =
      document.removeEventListener.bind(document);
    const removedListeners = [];
    const clearedTimerIds = [];

    // Replace cleanup APIs with observable test doubles.
    document.removeEventListener = (type, listener, options) => {
      removedListeners.push({ type, listener, options });
      return originalDocumentRemoveEventListener(type, listener, options);
    };
    window.clearTimeout = (timerId) => {
      clearedTimerIds.push(timerId);
    };

    // Execute the async scenario and restore mocked globals afterward.
    try {
      const element = await mountLitComponent("user-search-field");
      const outsidePointerHandler = element._outsidePointerHandler;

      // Remove the field and clear pending search work.
      element._searchTimeoutId = 123;
      element.remove();

      // Disconnect clears the pending timer and removes the pointer listener.
      expect(clearedTimerIds).to.deep.equal([123]);
      expect(
        removedListeners.some(
          ({ type, listener }) =>
            type === "pointerdown" && listener === outsidePointerHandler,
        ),
      ).to.equal(true);
    } finally {
      document.removeEventListener = originalDocumentRemoveEventListener;
    }
  });

  it("opens the results above the search input near the viewport bottom", async () => {
    // Render the component near the bottom of the viewport.
    renderViewportBottomLayout(80);
    const element = await mountLitComponent("user-search-field");

    // Show a long list of search results.
    element._searchQuery = "user";
    element._searchResults = Array.from({ length: 12 }, (_, index) => ({
      user_id: `${index}`,
      username: `user${index}`,
      name: `User ${index}`,
    }));
    await element.updateComplete;

    // The results open upward and stay inside the viewport.
    const input = element.querySelector("[data-user-search-input]");
    const dropdownBounds = element.querySelector("[data-user-search-dropdown]").getBoundingClientRect();
    expect(dropdownBounds.height).to.be.greaterThan(0);
    expect(dropdownBounds.bottom).to.be.at.most(input.getBoundingClientRect().top);
    expect(dropdownBounds.top).to.be.at.least(0);
  });
});

/**
 * Keeps mocked fetch responses pending until the test resolves them.
 * @param {Object} fetchMock Fetch mock returned by mockFetch.
 * @returns {Array<Object>} Pending responses with their signal and resolver.
 */
const deferFetchResponses = (fetchMock) => {
  const pendingResponses = [];
  fetchMock.setImpl(
    (_url, init) =>
      new Promise((resolveResponse) => {
        pendingResponses.push({
          signal: init.signal,
          resolve(users) {
            resolveResponse({
              ok: true,
              async json() {
                return users;
              },
            });
          },
        });
      }),
  );
  return pendingResponses;
};

/**
 * Replaces window timers with callbacks that tests run explicitly.
 * @returns {Map<number, Function>} Scheduled callbacks by timer id.
 */
const useControlledTimers = () => {
  const scheduledCallbacks = new Map();
  let nextTimerId = 0;
  window.setTimeout = (callback) => {
    nextTimerId += 1;
    scheduledCallbacks.set(nextTimerId, callback);
    return nextTimerId;
  };
  window.clearTimeout = (timerId) => {
    scheduledCallbacks.delete(timerId);
  };
  return scheduledCallbacks;
};
