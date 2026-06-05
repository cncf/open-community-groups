import { expect } from "@open-wc/testing";

import { getLocationSearchKeyAction } from "/static/js/common/location-search-keyboard.js";

describe("location search keyboard", () => {
  it("searches or hides when enter is pressed without results", () => {
    // Enter starts a search when the query is long enough.
    expect(
      getLocationSearchKeyAction({
        event: { key: "Enter" },
        resultsCount: 0,
        highlightedIndex: -1,
        query: "Málaga",
      }),
    ).to.deep.equal({
      action: "search",
      highlightedIndex: -1,
      preventDefault: true,
    });

    // Short queries hide the dropdown instead of searching.
    expect(
      getLocationSearchKeyAction({
        event: { key: "Enter" },
        resultsCount: 0,
        highlightedIndex: -1,
        query: "Má",
      }).action,
    ).to.equal("hide");
  });

  it("moves the highlighted result within bounds", () => {
    // Arrow keys clamp the highlighted index to the available results.
    expect(
      getLocationSearchKeyAction({
        event: { key: "ArrowDown" },
        resultsCount: 2,
        highlightedIndex: 1,
        query: "",
      }).highlightedIndex,
    ).to.equal(1);
    expect(
      getLocationSearchKeyAction({
        event: { key: "ArrowUp" },
        resultsCount: 2,
        highlightedIndex: 0,
        query: "",
      }).highlightedIndex,
    ).to.equal(0);
  });

  it("returns clear and select actions for Escape and Enter with results", () => {
    // Escape clears the current result list.
    expect(
      getLocationSearchKeyAction({
        event: { key: "Escape" },
        resultsCount: 2,
        highlightedIndex: 1,
        query: "",
      }).action,
    ).to.equal("clear");

    // Enter selects the currently highlighted result.
    expect(
      getLocationSearchKeyAction({
        event: { key: "Enter" },
        resultsCount: 2,
        highlightedIndex: 1,
        query: "",
      }).action,
    ).to.equal("select");
  });
});
