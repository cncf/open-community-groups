import { expect } from "@open-wc/testing";

import "/static/js/dashboard/community/community-selector.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx } from "/tests/unit/test-utils/globals.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

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
    const element = await renderSelector();

    const button = element.querySelector("#community-selector-button");

    expect(button?.textContent).to.include("CNCF");
    expect(element._findSelectedCommunity()).to.deep.equal({
      community_id: "1",
      display_name: "CNCF",
      name: "cncf",
    });
  });

  it("filters communities from the debounced search query", async () => {
    const element = await renderSelector();

    element._handleSearchInput({
      target: {
        value: "open",
      },
    });

    await new Promise((resolve) => setTimeout(resolve, 250));

    expect(element._query).to.equal("open");
    expect(element._filteredCommunities).to.deep.equal([
      { community_id: "2", display_name: "OpenSSF", name: "openssf" },
    ]);
  });

  it("supports keyboard navigation and closes on escape", async () => {
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

    element._isOpen = true;
    element._handleCommunityClick = async (_event, community) => {
      handledSelections.push(community.community_id);
    };

    event.key = "ArrowDown";
    element._handleKeydown(event);
    expect(element._activeIndex).to.equal(0);

    event.key = "ArrowDown";
    element._handleKeydown(event);
    expect(element._activeIndex).to.equal(1);

    event.key = "ArrowUp";
    element._handleKeydown(event);
    expect(element._activeIndex).to.equal(0);

    event.key = "Enter";
    element._handleKeydown(event);
    expect(handledSelections).to.deep.equal([]);

    element.selectedCommunityId = "3";
    element._activeIndex = 1;
    event.key = "Enter";
    element._handleKeydown(event);
    expect(handledSelections).to.deep.equal(["2"]);

    event.key = "Escape";
    element._handleKeydown(event);
    expect(element._isOpen).to.equal(false);
    expect(element._activeIndex).to.equal(null);
    expect(event.preventDefaultCalls).to.equal(6);
  });

  it("persists the selected community and keeps the selector usable", async () => {
    const element = await renderSelector({
      selectedCommunityId: "3",
    });

    const event = {
      prevented: false,
      preventDefault() {
        this.prevented = true;
      },
    };

    element._isOpen = true;
    await element._handleCommunityClick(event, {
      community_id: "2",
      display_name: "OpenSSF",
      name: "openssf",
    });

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
