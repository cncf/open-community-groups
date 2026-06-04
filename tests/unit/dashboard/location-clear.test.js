import { expect } from "@open-wc/testing";

import { initializeLocationClearButton } from "/static/js/dashboard/location-clear.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";

describe("dashboard location clear", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  const renderLocationClearControls = () => {
    document.body.innerHTML = `
      <button id="clear-location-fields" type="button"></button>
      <div id="group-location-search"></div>
    `;
  };

  it("clears the location search field once when initialized repeatedly", () => {
    // Prepare the location clear controls.
    renderLocationClearControls();
    const locationSearchField = document.getElementById("group-location-search");
    let clearCount = 0;
    locationSearchField.clearLocationFields = () => {
      clearCount += 1;
    };

    // Initialize repeatedly to verify duplicate click handlers are guarded.
    initializeLocationClearButton();
    initializeLocationClearButton();
    document.getElementById("clear-location-fields").click();

    // Verify the location field clear method runs once.
    expect(clearCount).to.equal(1);
  });

  it("initializes swapped location clear controls on htmx load", () => {
    // Prepare the location clear controls as swapped dashboard content.
    renderLocationClearControls();
    const locationSearchField = document.getElementById("group-location-search");
    let clearCount = 0;
    locationSearchField.clearLocationFields = () => {
      clearCount += 1;
    };

    // Dispatch the lifecycle event used by swapped dashboard content.
    dispatchHtmxLoad(document.body);
    document.getElementById("clear-location-fields").click();

    // Verify the swapped controls clear the location field.
    expect(clearCount).to.equal(1);
  });
});
