import { expect } from "@open-wc/testing";

import { positionTooltipPanel } from "/static/js/common/tooltip-panel.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("tooltip panel", () => {
  const originalVisualViewport = Object.getOwnPropertyDescriptor(window, "visualViewport");

  beforeEach(() => {
    resetDom();
    Object.defineProperty(window, "visualViewport", {
      configurable: true,
      value: {
        height: 768,
        offsetLeft: 0,
        offsetTop: 0,
        width: 1280,
      },
    });
  });

  afterEach(() => {
    resetDom();
    if (originalVisualViewport) {
      Object.defineProperty(window, "visualViewport", originalVisualViewport);
    } else {
      delete window.visualViewport;
    }
  });

  it("places a tall tooltip below a trigger near the top of the viewport", () => {
    // Render a tooltip relationship close to the top viewport edge.
    const { tooltip, trigger } = renderTooltipFixture();
    trigger.getBoundingClientRect = () => createRect(620, 12, 80, 24);
    tooltip.getBoundingClientRect = () => createRect(0, 0, 288, 400);

    // Position the tooltip using the shared viewport collision behavior.
    positionTooltipPanel(trigger, tooltip);

    // Keep the full panel below the trigger and inside the viewport width.
    expect(tooltip.style.position).to.equal("fixed");
    expect(tooltip.style.top).to.equal("40px");
    expect(tooltip.style.left).to.equal("516px");
    expect(tooltip.style.maxHeight).to.equal("712px");
  });

  it("keeps a tooltip above its trigger when there is enough room", () => {
    // Render a tooltip relationship with sufficient space above its trigger.
    const { tooltip, trigger } = renderTooltipFixture();
    trigger.getBoundingClientRect = () => createRect(620, 600, 80, 24);
    tooltip.getBoundingClientRect = () => createRect(0, 0, 288, 200);

    // Position the tooltip using the shared viewport collision behavior.
    positionTooltipPanel(trigger, tooltip);

    // Preserve above-trigger placement without crossing the viewport edge.
    expect(tooltip.style.top).to.equal("396px");
    expect(tooltip.style.left).to.equal("516px");
    expect(tooltip.style.maxHeight).to.equal("580px");
  });

  it("clamps a wide tooltip to the horizontal viewport padding", () => {
    // Render a tooltip relationship beside the right viewport edge.
    const { tooltip, trigger } = renderTooltipFixture();
    trigger.getBoundingClientRect = () => createRect(1260, 600, 20, 24);
    tooltip.getBoundingClientRect = () => createRect(0, 0, 288, 200);

    // Position the tooltip using the shared viewport collision behavior.
    positionTooltipPanel(trigger, tooltip);

    // Keep the tooltip within the right edge padding.
    expect(tooltip.style.left).to.equal("976px");
  });

  it("limits tooltip height when neither vertical side can fit its content", () => {
    // Render a tall tooltip around the center of the viewport.
    const { tooltip, trigger } = renderTooltipFixture();
    trigger.getBoundingClientRect = () => createRect(620, 360, 80, 24);
    tooltip.getBoundingClientRect = () => createRect(0, 0, 288, 700);

    // Position the tooltip using the larger available side.
    positionTooltipPanel(trigger, tooltip);

    // Keep the tooltip within the bottom viewport padding and make it scrollable.
    expect(tooltip.style.top).to.equal("388px");
    expect(tooltip.style.maxHeight).to.equal("364px");
    expect(tooltip.style.overflowY).to.equal("auto");
  });
});

const createRect = (left, top, width, height) => ({
  bottom: top + height,
  height,
  left,
  right: left + width,
  top,
  width,
  x: left,
  y: top,
});

const renderTooltipFixture = () => {
  document.body.innerHTML = `
    <button aria-describedby="tooltip-panel">Details</button>
    <span id="tooltip-panel" data-tooltip-panel role="tooltip">Tooltip content</span>
  `;

  return {
    tooltip: document.getElementById("tooltip-panel"),
    trigger: document.querySelector("button"),
  };
};
