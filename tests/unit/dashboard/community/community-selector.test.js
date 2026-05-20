import { expect } from "@open-wc/testing";

import "/static/js/dashboard/community/community-selector.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx } from "/tests/unit/test-utils/globals.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("community-selector", () => {
  let htmx;

  useMountedElementsCleanup("community-selector");

  beforeEach(() => {
    resetDom();
    htmx = mockHtmx();
  });

  afterEach(() => {
    htmx.restore();
  });

  // Render the fixture to check it covers the current behavior.
  const renderSelector = async (properties = {}) => {
    return mountLitComponent("community-selector", {
      communities: [
        { community_id: "1", display_name: "CNCF", name: "cncf" },
        { community_id: "2", display_name: "OpenSSF", name: "openssf" },
        { community_id: "3", display_name: "LF Europe", name: "lf-europe" },
      ],
      selectedCommunityId: "1",
      selectEndpoint: "/dashboard/community",
      ...properties,
    });
  };

  it("renders the selected community label", async () => {
    // Render the fixture to check it renders the selected community label.
    const element = await renderSelector();

    // Read the DOM to check it renders the selected community label.
    const button = element.querySelector("#community-selector-button");

    // Confirm it renders the selected community label.
    expect(button?.textContent).to.include("CNCF");
    expect(element._findSelectedCommunity()).to.deep.equal({
      community_id: "1",
      display_name: "CNCF",
      name: "cncf",
    });
  });

  it("filters communities from the debounced search query", async () => {
    // Render the fixture to check it filters communities from the debounced search query.
    const element = await renderSelector();

    // Run component methods to check it filters communities from the debounced search.
    element._handleSearchInput({
      target: {
        value: "open",
      },
    });

    // Exercise the flow to check it filters communities from the debounced search query.
    await new Promise((resolve) => setTimeout(resolve, 250));

    // Confirm it filters communities from the debounced search query.
    expect(element._query).to.equal("open");
    expect(element._filteredCommunities).to.deep.equal([
      { community_id: "2", display_name: "OpenSSF", name: "openssf" },
    ]);
  });

  it("supports keyboard navigation and closes on escape", async () => {
    // Render the fixture to check it supports keyboard navigation and closes on escape.
    const element = await renderSelector();
    const handledSelections = [];
    const event = {
      key: "",
      defaultPrevented: false,
      preventDefaultCalls: 0,
      preventDefault() {
        this.preventDefaultCalls += 1;
      },
    };

    // Run component methods to check it supports keyboard navigation and closes.
    element._isOpen = true;
    element._handleCommunityClick = async (_event, community) => {
      handledSelections.push(community.community_id);
    };

    // Exercise the flow to check it supports keyboard navigation and closes on escape.
    event.key = "ArrowDown";
    element._handleKeydown(event);
    expect(element._activeIndex).to.equal(0);

    // Exercise the flow to check it supports keyboard navigation and closes on escape.
    event.key = "ArrowDown";
    element._handleKeydown(event);
    expect(element._activeIndex).to.equal(1);

    // Exercise the flow to check it supports keyboard navigation and closes on escape.
    event.key = "ArrowUp";
    element._handleKeydown(event);
    expect(element._activeIndex).to.equal(0);

    // Exercise the flow to check it supports keyboard navigation and closes on escape.
    event.key = "Enter";
    element._handleKeydown(event);
    expect(handledSelections).to.deep.equal([]);

    // Exercise the flow to check it supports keyboard navigation and closes on escape.
    element.selectedCommunityId = "3";
    element._activeIndex = 1;
    event.key = "Enter";
    element._handleKeydown(event);
    expect(handledSelections).to.deep.equal(["2"]);

    // Exercise the flow to check it supports keyboard navigation and closes on escape.
    event.key = "Escape";
    element._handleKeydown(event);
    expect(element._isOpen).to.equal(false);
    expect(element._activeIndex).to.equal(null);
    expect(event.preventDefaultCalls).to.equal(6);
  });

  it("persists the selected community and keeps the selector usable", async () => {
    // Render the fixture to check it persists the selected community and keeps.
    const element = await renderSelector({
      selectedCommunityId: "3",
    });

    // Prepare event to check it persists the selected community and keeps the selector.
    const event = {
      prevented: false,
      preventDefault() {
        this.prevented = true;
      },
    };

    // Run component methods to check it persists the selected community and keeps.
    element._isOpen = true;
    await element._handleCommunityClick(event, {
      community_id: "2",
      display_name: "OpenSSF",
      name: "openssf",
    });

    // Confirm it persists the selected community and keeps the selector usable.
    expect(htmx.ajaxCalls).to.deep.equal([
      [
        "PUT",
        "/dashboard/community/2/select",
        {
          target: "body",
          indicator: "#dashboard-spinner",
        },
      ],
    ]);
    expect(event.prevented).to.equal(true);
    expect(element._isOpen).to.equal(false);
    expect(element._isSubmitting).to.equal(false);
  });
});
