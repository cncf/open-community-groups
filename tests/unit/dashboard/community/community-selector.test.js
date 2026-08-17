import { expect } from "@open-wc/testing";

import "/static/js/dashboard/community/community-selector.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx, mockSwal } from "/tests/unit/test-utils/globals.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("community-selector", () => {
  let htmx;
  let swal;

  useMountedElementsCleanup("community-selector");

  beforeEach(() => {
    resetDom();
    htmx = mockHtmx();
    swal = mockSwal();
  });

  afterEach(() => {
    swal.restore();
    htmx.restore();
  });

  // Render the component fixture.
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
    // Render the selector fixture.
    const element = await renderSelector();

    // Read the rendered DOM state for rendering the selected community label.
    const button = element.querySelector("#community-selector-button");
    const list = element.querySelector("#community-selector-list");
    const option = element.querySelector("#community-option-1");
    const searchInput = element.querySelector("#community-search-input");

    // Verify the default ids and semantic option class remain unchanged.
    expect(button?.textContent).to.include("CNCF");
    expect(list).to.exist;
    expect(option?.classList.contains("community-button")).to.equal(true);
    expect(searchInput).to.exist;
    expect(element._findSelectedCommunity()).to.deep.equal({
      community_id: "1",
      display_name: "CNCF",
      name: "cncf",
    });
  });

  it("namespaces DOM ids and focuses the prefixed search input", async () => {
    // Render the selector with a mobile id prefix.
    const element = await renderSelector();
    element.setAttribute("id-prefix", "mobile-community");
    await element.updateComplete;

    // Read the namespaced controls and open the selector.
    const button = element.querySelector("#mobile-community-selector-button");
    const list = element.querySelector("#mobile-community-selector-list");
    const option = element.querySelector("#mobile-community-option-1");
    const searchInput = element.querySelector("#mobile-community-search-input");
    button.click();
    await element.updateComplete;

    // Verify every id is namespaced while the option class and focus behavior remain stable.
    expect(element.querySelector("#community-selector-button")).to.equal(null);
    expect(list).to.exist;
    expect(option?.classList.contains("community-button")).to.equal(true);
    expect(document.activeElement).to.equal(searchInput);
  });

  it("filters communities from the debounced search query", async () => {
    // Render the selector fixture.
    const element = await renderSelector();

    // Call handle search input.
    element._handleSearchInput({
      target: {
        value: "open",
      },
    });

    // Verify filters communities from the debounced search query.
    await new Promise((resolve) => setTimeout(resolve, 250));

    // Assert the element state.
    expect(element._combobox.query).to.equal("open");
    expect(element._filteredCommunities).to.deep.equal([
      { community_id: "2", display_name: "OpenSSF", name: "openssf" },
    ]);
  });

  it("supports keyboard navigation and closes on escape", async () => {
    // Render the selector fixture.
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

    // Open the selector with two keyboard options.
    element._combobox.isOpen = true;
    element._handleCommunityClick = async (_event, community) => {
      handledSelections.push(community.community_id);
    };

    // Move to the first option.
    event.key = "ArrowDown";
    element._combobox._handleKeydown(event);
    expect(element._combobox.activeIndex).to.equal(0);

    // Move to the next option.
    event.key = "ArrowDown";
    element._combobox._handleKeydown(event);
    expect(element._combobox.activeIndex).to.equal(1);

    // Press ArrowUp.
    event.key = "ArrowUp";
    element._combobox._handleKeydown(event);
    expect(element._combobox.activeIndex).to.equal(0);

    // Press Enter.
    event.key = "Enter";
    element._combobox._handleKeydown(event);
    expect(handledSelections).to.deep.equal([]);

    // Select the highlighted community with Enter.
    element.selectedCommunityId = "3";
    element._combobox.activeIndex = 1;
    event.key = "Enter";
    element._combobox._handleKeydown(event);
    expect(handledSelections).to.deep.equal(["2"]);

    // Press Escape.
    event.key = "Escape";
    element._combobox._handleKeydown(event);
    expect(element._combobox.isOpen).to.equal(false);
    expect(element._combobox.activeIndex).to.equal(null);
    expect(event.preventDefaultCalls).to.equal(6);
  });

  it("persists the selected community and keeps the selector usable", async () => {
    // Render the selector fixture.
    const element = await renderSelector({
      selectedCommunityId: "3",
    });

    // Prepare event for persisting the selected community and keeps the selector.
    const event = {
      prevented: false,
      preventDefault() {
        this.prevented = true;
      },
    };

    // Select a different community from the selector.
    element._combobox.isOpen = true;
    await element._handleCommunityClick(event, {
      community_id: "2",
      display_name: "OpenSSF",
      name: "openssf",
    });

    // The selected community is persisted without disabling the selector.
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
    expect(element._combobox.isOpen).to.equal(false);
    expect(element._isSubmitting).to.equal(false);
  });

  it("shows an error and keeps the selector usable when selection fails", async () => {
    // Replace the HTMX mock with a failing selection request.
    htmx.restore();
    htmx = mockHtmx({
      ajaxImpl: async () => {
        throw new Error("Selection failed");
      },
    });

    // Render the selector fixture.
    const element = await renderSelector({
      selectedCommunityId: "3",
    });
    const event = {
      preventDefault() {},
    };

    // Select a different community from the selector.
    element._combobox.isOpen = true;
    await element._handleCommunityClick(event, {
      community_id: "2",
      display_name: "OpenSSF",
      name: "openssf",
    });

    // The failed selection leaves the selector usable and reports the error.
    expect(element._isSubmitting).to.equal(false);
    expect(element._combobox.isOpen).to.equal(false);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0]).to.include({
      text: "Something went wrong selecting the community. Please try again later.",
      icon: "error",
    });
  });
});
