import { expect } from "@open-wc/testing";

import "/static/js/dashboard/alliance/alliance-selector.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx, mockSwal } from "/tests/unit/test-utils/globals.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("alliance-selector", () => {
  let htmx;
  let swal;

  useMountedElementsCleanup("alliance-selector");

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
    return mountLitComponent("alliance-selector", {
      alliances: [
        { alliance_id: "1", display_name: "Goup", name: "goup" },
        { alliance_id: "2", display_name: "OpenSSF", name: "openssf" },
        { alliance_id: "3", display_name: "LF Europe", name: "lf-europe" },
      ],
      selectedAllianceId: "1",
      selectEndpoint: "/dashboard/alliance",
      ...properties,
    });
  };

  it("renders the selected alliance label", async () => {
    // Render the selector fixture.
    const element = await renderSelector();

    // Read the rendered DOM state for rendering the selected alliance label.
    const button = element.querySelector("#alliance-selector-button");

    // Verify renders the selected alliance label.
    expect(button?.textContent).to.include("Goup");
    expect(element._findSelectedAlliance()).to.deep.equal({
      alliance_id: "1",
      display_name: "Goup",
      name: "goup",
    });
  });

  it("filters alliances from the debounced search query", async () => {
    // Render the selector fixture.
    const element = await renderSelector();

    // Call handle search input.
    element._handleSearchInput({
      target: {
        value: "open",
      },
    });

    // Verify filters alliances from the debounced search query.
    await new Promise((resolve) => setTimeout(resolve, 250));

    // Assert the element state.
    expect(element._combobox.query).to.equal("open");
    expect(element._filteredAlliances).to.deep.equal([
      { alliance_id: "2", display_name: "OpenSSF", name: "openssf" },
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
    element._handleAllianceClick = async (_event, alliance) => {
      handledSelections.push(alliance.alliance_id);
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

    // Select the highlighted alliance with Enter.
    element.selectedAllianceId = "3";
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

  it("persists the selected alliance and keeps the selector usable", async () => {
    // Render the selector fixture.
    const element = await renderSelector({
      selectedAllianceId: "3",
    });

    // Prepare event for persisting the selected alliance and keeps the selector.
    const event = {
      prevented: false,
      preventDefault() {
        this.prevented = true;
      },
    };

    // Select a different alliance from the selector.
    element._combobox.isOpen = true;
    await element._handleAllianceClick(event, {
      alliance_id: "2",
      display_name: "OpenSSF",
      name: "openssf",
    });

    // The selected alliance is persisted without disabling the selector.
    expect(htmx.ajaxCalls).to.deep.equal([
      [
        "PUT",
        "/dashboard/alliance/2/select",
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
      selectedAllianceId: "3",
    });
    const event = {
      preventDefault() {},
    };

    // Select a different alliance from the selector.
    element._combobox.isOpen = true;
    await element._handleAllianceClick(event, {
      alliance_id: "2",
      display_name: "OpenSSF",
      name: "openssf",
    });

    // The failed selection leaves the selector usable and reports the error.
    expect(element._isSubmitting).to.equal(false);
    expect(element._combobox.isOpen).to.equal(false);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0]).to.include({
      text: "Something went wrong selecting the alliance. Please try again later.",
      icon: "error",
    });
  });
});
