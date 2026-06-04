import { expect } from "@open-wc/testing";

import "/static/js/common/timezone-selector.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("timezone-selector", () => {
  useMountedElementsCleanup("timezone-selector");

  beforeEach(() => {
    resetDom();
  });

  // Render the selector with defaults shared by the timezone scenarios.
  const renderSelector = async ({
    name = "timezone",
    value = "",
    timezones = [],
    required = false,
    disabled = false,
  } = {}) => {
    return mountLitComponent("timezone-selector", {
      name,
      value,
      timezones,
      required,
      disabled,
    });
  };

  it("renders the selected timezone and hidden input state", async () => {
    // Render the selector fixture.
    const element = await renderSelector({
      name: "event_timezone",
      value: "Europe/Madrid",
      timezones: ["Europe/Madrid", "UTC"],
      required: true,
    });

    // Collect the input and button elements.
    const input = element.querySelector('input[name="event_timezone"]');
    const button = element.querySelector("#timezone-selector-button");

    // The selected timezone is mirrored into the hidden input and button.
    expect(input?.value).to.equal("Europe/Madrid");
    expect(input?.required).to.equal(true);
    expect(button?.textContent).to.include("Europe/Madrid");
  });

  it("filters available timezones from the current query", async () => {
    // Render the selector fixture.
    const element = await renderSelector({
      timezones: ["Europe/Madrid", "UTC", "America/New_York"],
    });

    // Search query filtering keeps only matching timezones.
    element._query = "new";
    await element.updateComplete;

    // The filtered list contains the matching timezone.
    expect(element._filteredTimezones).to.deep.equal(["America/New_York"]);
  });

  it("updates the value and emits change when a timezone is selected", async () => {
    // Render the selector fixture.
    const element = await renderSelector({
      value: "UTC",
      timezones: ["UTC", "Europe/Madrid"],
    });

    // Track selection prevention and emitted change events.
    let prevented = false;
    let changed = 0;

    // Count change events emitted by timezone selection.
    element.addEventListener("change", () => {
      changed += 1;
    });

    // Select a different timezone from the dropdown.
    element._handleTimezoneClick(
      {
        preventDefault() {
          prevented = true;
        },
      },
      "Europe/Madrid",
    );
    await element.updateComplete;

    // The selected timezone updates value, closes the menu, and emits change.
    expect(prevented).to.equal(true);
    expect(changed).to.equal(1);
    expect(element.value).to.equal("Europe/Madrid");
    expect(element._isOpen).to.equal(false);
  });

  it("does not update when the timezone is already selected or disabled", async () => {
    // Render the selector fixture.
    const selectedElement = await renderSelector({
      value: "UTC",
      timezones: ["UTC", "Europe/Madrid"],
    });

    // Track changes for selecting the already-active timezone.
    let selectedChangeCount = 0;
    selectedElement.addEventListener("change", () => {
      selectedChangeCount += 1;
    });

    // Selecting the active timezone keeps value and change count unchanged.
    selectedElement._handleTimezoneClick(
      {
        preventDefault() {},
      },
      "UTC",
    );

    // The active timezone remains selected without emitting change.
    expect(selectedElement.value).to.equal("UTC");
    expect(selectedChangeCount).to.equal(0);
    expect(selectedElement._isSelected("UTC")).to.equal(true);

    // Render the selector fixture.
    const disabledElement = await renderSelector({
      value: "UTC",
      timezones: ["UTC", "Europe/Madrid"],
      disabled: true,
    });

    // Track changes for a disabled selector.
    let disabledChangeCount = 0;
    disabledElement.addEventListener("change", () => {
      disabledChangeCount += 1;
    });

    // Disabled selectors ignore timezone clicks.
    disabledElement._handleTimezoneClick(
      {
        preventDefault() {},
      },
      "Europe/Madrid",
    );

    // Disabled selectors keep the current value without emitting change.
    expect(disabledElement.value).to.equal("UTC");
    expect(disabledChangeCount).to.equal(0);
  });
});
