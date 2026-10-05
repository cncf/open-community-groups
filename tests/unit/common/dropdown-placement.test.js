import { expect } from "@open-wc/testing";

import {
  DropdownPlacementController,
  getVisibleVerticalBounds,
  placeDropdown,
} from "/static/js/common/dropdown-placement.js";
import { waitForAnimationFrames } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

// Height of the anchor input rendered by the fixture.
const ANCHOR_HEIGHT = 40;

// Height of the clipping container that holds the fixture.
const CONTAINER_HEIGHT = 400;

// Gap between the anchor and the dropdown, set through the dropdown margin.
const DROPDOWN_GAP = 4;

// Stylesheet max height applied to the dropdown.
const DROPDOWN_MAX_HEIGHT = 320;

// Space kept between the dropdown and the visible edge.
const VISIBLE_GAP = 8;

describe("dropdown placement", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("keeps the template placement when the dropdown fits below its anchor", () => {
    // Render a short dropdown near the top of the viewport.
    const { anchor, dropdown } = renderDropdownFixture({ anchorTop: 20, optionCount: 3 });

    // Fit the dropdown.
    placeDropdown(anchor, dropdown);

    // No inline placement is needed.
    expect(dropdown.style.insetBlockStart).to.equal("");
    expect(dropdown.style.insetBlockEnd).to.equal("");
    expect(dropdown.style.maxHeight).to.equal("");
  });

  it("caps the dropdown height to the space left below its anchor", () => {
    // Render a long dropdown with more room below than above its anchor.
    const { anchor, dropdown } = renderDropdownFixture({ anchorTop: 100, optionCount: 20 });

    // Fit the dropdown.
    placeDropdown(anchor, dropdown);

    // The dropdown stays below and ends at the visible gap.
    expect(dropdown.style.insetBlockEnd).to.equal("");
    expect(dropdown.style.maxHeight).to.equal(
      `${CONTAINER_HEIGHT - VISIBLE_GAP - (100 + ANCHOR_HEIGHT + DROPDOWN_GAP)}px`,
    );
    expect(dropdown.getBoundingClientRect().bottom).to.equal(CONTAINER_HEIGHT - VISIBLE_GAP);
  });

  it("opens above its anchor when there is more room above", () => {
    // Render a long dropdown whose anchor sits near the bottom of the container.
    const { anchor, dropdown } = renderDropdownFixture({ anchorTop: 340, optionCount: 20 });

    // Fit the dropdown.
    placeDropdown(anchor, dropdown);

    // The dropdown ends just above the anchor with its stylesheet height.
    const dropdownBounds = dropdown.getBoundingClientRect();
    expect(dropdown.style.insetBlockStart).to.equal("auto");
    expect(dropdown.style.maxHeight).to.equal("");
    expect(dropdownBounds.bottom).to.equal(340 - DROPDOWN_GAP);
    expect(dropdownBounds.height).to.equal(DROPDOWN_MAX_HEIGHT);
  });

  it("caps an upward dropdown to the space left above its anchor", () => {
    // Render a long dropdown with limited room on both sides of its anchor.
    const { anchor, dropdown } = renderDropdownFixture({ anchorTop: 200, optionCount: 20 });

    // Fit the dropdown.
    placeDropdown(anchor, dropdown);

    // The dropdown opens upward and stops at the visible gap.
    const dropdownBounds = dropdown.getBoundingClientRect();
    expect(dropdown.style.insetBlockStart).to.equal("auto");
    expect(dropdown.style.maxHeight).to.equal(`${200 - DROPDOWN_GAP - VISIBLE_GAP}px`);
    expect(dropdownBounds.top).to.equal(VISIBLE_GAP);
    expect(dropdownBounds.bottom).to.equal(200 - DROPDOWN_GAP);
  });

  it("keeps the dropdown scroll position when refitting", () => {
    // Render a long dropdown and scroll its options.
    const { anchor, dropdown } = renderDropdownFixture({ anchorTop: 340, optionCount: 20 });
    placeDropdown(anchor, dropdown);
    dropdown.scrollTop = dropdown.scrollHeight;
    const scrollTop = dropdown.scrollTop;

    // Refit the dropdown after a render.
    placeDropdown(anchor, dropdown);

    // The options stay scrolled to the same position.
    expect(scrollTop).to.be.greaterThan(0);
    expect(dropdown.scrollTop).to.equal(scrollTop);
  });

  it("limits the visible bounds to clipping ancestors", () => {
    // Render an element inside a scrolling container.
    document.body.innerHTML = `
      <div id="scroller" style="overflow: auto">
        <span id="target">Target</span>
      </div>
    `;
    const scroller = document.getElementById("scroller");
    scroller.getBoundingClientRect = () => ({ top: 100, bottom: 300 });

    // The bounds use the container edges with the requested gap.
    expect(getVisibleVerticalBounds(document.getElementById("target"), 4)).to.deep.equal({
      top: 104,
      bottom: 296,
    });
  });

  describe("controller", () => {
    let controller;
    let fixture;

    beforeEach(() => {
      fixture = renderDropdownFixture({ anchorTop: 340, optionCount: 20 });
      const host = {
        addController(addedController) {
          this.controller = addedController;
        },
      };
      controller = new DropdownPlacementController(host, {
        getAnchor: () => document.getElementById("anchor"),
        getDropdown: () => document.getElementById("dropdown"),
      });
    });

    afterEach(() => {
      controller.hostDisconnected();
    });

    it("fits the rendered dropdown after each host update", () => {
      // Run the host update hook.
      controller.hostUpdated();

      // The dropdown is fitted above its anchor.
      expect(fixture.dropdown.style.insetBlockStart).to.equal("auto");
    });

    it("refits the dropdown when the viewport is resized while it is visible", async () => {
      // Fit the dropdown and then move its anchor to the top of the viewport.
      controller.hostUpdated();
      fixture.spacer.style.height = "0px";

      // Notify the controller about a viewport change.
      window.dispatchEvent(new Event("resize"));
      await waitForAnimationFrames();

      // The dropdown returns below its anchor.
      expect(fixture.dropdown.style.insetBlockStart).to.equal("");
    });

    it("refits the dropdown when an ancestor scrolls while it is visible", async () => {
      // Fit the dropdown and then move its anchor to the top of the container.
      controller.hostUpdated();
      fixture.spacer.style.height = "0px";

      // Notify the controller about an ancestor scroll.
      fixture.spacer.parentElement.dispatchEvent(new Event("scroll"));
      await waitForAnimationFrames();

      // The dropdown returns below its anchor.
      expect(fixture.dropdown.style.insetBlockStart).to.equal("");
    });

    it("refits only once for a burst of viewport changes", async () => {
      // Fit the dropdown and count later placement reads.
      controller.hostUpdated();
      let fits = 0;
      const originalUpdate = controller.update.bind(controller);
      controller.update = () => {
        fits += 1;
        originalUpdate();
      };

      // Notify the controller about several changes within one frame.
      window.dispatchEvent(new Event("resize"));
      document.dispatchEvent(new Event("scroll"));
      window.dispatchEvent(new Event("resize"));
      await waitForAnimationFrames();

      // The refits are coalesced into a single placement pass.
      expect(fits).to.equal(1);
    });

    it("stops refitting once the dropdown is hidden or the host disconnects", async () => {
      // Fit the dropdown and hide it on the next host update.
      controller.hostUpdated();
      fixture.dropdown.style.display = "none";
      controller.hostUpdated();

      // Viewport changes are ignored while the dropdown is hidden.
      fixture.dropdown.style.display = "";
      fixture.spacer.style.height = "0px";
      window.dispatchEvent(new Event("resize"));
      await waitForAnimationFrames();
      expect(fixture.dropdown.style.insetBlockStart).to.equal("auto");

      // Viewport changes are ignored after the host disconnects.
      fixture.spacer.style.height = "340px";
      controller.hostUpdated();
      controller.hostDisconnected();
      fixture.spacer.style.height = "0px";
      window.dispatchEvent(new Event("resize"));
      await waitForAnimationFrames();
      expect(fixture.dropdown.style.insetBlockStart).to.equal("auto");
    });

    it("ignores scrolling inside the dropdown", async () => {
      // Fit the dropdown and track later placement changes.
      controller.hostUpdated();
      fixture.dropdown.style.insetBlockStart = "";

      // Scroll the dropdown options.
      fixture.dropdown.dispatchEvent(new Event("scroll"));
      await waitForAnimationFrames();

      // The dropdown is not refitted.
      expect(fixture.dropdown.style.insetBlockStart).to.equal("");
    });
  });
});

/**
 * Renders an anchored dropdown inside a fixed clipping container.
 * @param {object} options Fixture options.
 * @param {number} options.anchorTop - Anchor top offset from the container top.
 * @param {number} options.optionCount - Number of 40px options in the dropdown.
 * @returns {{ anchor: HTMLElement, dropdown: HTMLElement, spacer: HTMLElement }} Fixture elements.
 */
const renderDropdownFixture = ({ anchorTop, optionCount }) => {
  document.body.innerHTML = `
    <style>
      #dropdown {
        position: absolute;
        top: ${ANCHOR_HEIGHT}px;
        left: 0;
        right: 0;
        margin-top: ${DROPDOWN_GAP}px;
        max-height: ${DROPDOWN_MAX_HEIGHT}px;
        overflow-y: auto;
      }
    </style>
    <div style="position: fixed; top: 0; left: 0; width: 300px; height: ${CONTAINER_HEIGHT}px; overflow-y: auto">
      <div id="spacer" style="height: ${anchorTop}px"></div>
      <div style="position: relative">
        <input id="anchor" style="display: block; box-sizing: border-box; height: ${ANCHOR_HEIGHT}px" />
        <p style="margin: 0; height: 24px">Helper text</p>
        <div id="dropdown">
          ${Array.from({ length: optionCount }, (_, index) => `<div style="height: 40px">Option ${index + 1}</div>`).join("")}
        </div>
      </div>
    </div>
  `;

  return {
    anchor: document.getElementById("anchor"),
    dropdown: document.getElementById("dropdown"),
    spacer: document.getElementById("spacer"),
  };
};
