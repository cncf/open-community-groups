import { expect } from "@open-wc/testing";

import "/static/js/common/timezone-selector.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";

describe("timezone-selector", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    removeMountedElements("timezone-selector");
    resetDom();
  });

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
    const element = await renderSelector({
      name: "event_timezone",
      value: "Europe/Madrid",
      timezones: ["Europe/Madrid", "UTC"],
      required: true,
    });

    const input = element.querySelector('input[name="event_timezone"]');
    const button = element.querySelector("#timezone-selector-button");

    expect(input?.value).to.equal("Europe/Madrid");
    expect(input?.required).to.equal(true);
    expect(button?.textContent).to.include("Europe/Madrid");
  });

  it("filters available timezones from the current query", async () => {
    const element = await renderSelector({
      timezones: ["Europe/Madrid", "UTC", "America/New_York"],
    });

    element._query = "new";
    await element.updateComplete;

    expect(element._filteredTimezones).to.deep.equal(["America/New_York"]);
  });

  it("updates the value and emits change when a timezone is selected", async () => {
    const element = await renderSelector({
      value: "UTC",
      timezones: ["UTC", "Europe/Madrid"],
    });

    let prevented = false;
    let changed = 0;

    element.addEventListener("change", () => {
      changed += 1;
    });

    element._handleTimezoneClick(
      {
        preventDefault() {
          prevented = true;
        },
      },
      "Europe/Madrid",
    );
    await element.updateComplete;

    expect(prevented).to.equal(true);
    expect(changed).to.equal(1);
    expect(element.value).to.equal("Europe/Madrid");
    expect(element._isOpen).to.equal(false);
  });

  it("does not update when the timezone is already selected or disabled", async () => {
    const selectedElement = await renderSelector({
      value: "UTC",
      timezones: ["UTC", "Europe/Madrid"],
    });

    let selectedChangeCount = 0;
    selectedElement.addEventListener("change", () => {
      selectedChangeCount += 1;
    });

    selectedElement._handleTimezoneClick(
      {
        preventDefault() {},
      },
      "UTC",
    );

    expect(selectedElement.value).to.equal("UTC");
    expect(selectedChangeCount).to.equal(0);
    expect(selectedElement._isSelected("UTC")).to.equal(true);

    const disabledElement = await renderSelector({
      value: "UTC",
      timezones: ["UTC", "Europe/Madrid"],
      disabled: true,
    });

    let disabledChangeCount = 0;
    disabledElement.addEventListener("change", () => {
      disabledChangeCount += 1;
    });

    disabledElement._handleTimezoneClick(
      {
        preventDefault() {},
      },
      "Europe/Madrid",
    );

    expect(disabledElement.value).to.equal("UTC");
    expect(disabledChangeCount).to.equal(0);
  });
});
