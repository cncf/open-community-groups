import { expect } from "@open-wc/testing";

import { positionTooltipPanel } from "/static/js/common/tooltip-panel.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

const DISMISSED_ATTRIBUTE = "data-tooltip-dismissed";

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

  it("resets the translate property so utility translations can't shift the panel", () => {
    // Render a tooltip relationship and position it.
    const { tooltip, trigger } = renderTooltipFixture();
    tooltip.style.translate = "-50% 0";
    positionTooltipPanel(trigger, tooltip);

    // Keep the computed left offset as the panel's real position.
    expect(tooltip.style.translate).to.equal("none");
    expect(tooltip.style.transform).to.equal("none");
  });

  it("repositions the focused tooltip on scroll when another trigger is hovered", () => {
    // Render two tooltip relationships, focus the first and hover the second.
    document.body.innerHTML = `
      <button id="focused-trigger" aria-describedby="focused-panel">Focused</button>
      <span id="focused-panel" data-tooltip-panel role="tooltip">Focused content</span>
      <button id="hovered-trigger" aria-describedby="hovered-panel">Hovered</button>
      <span id="hovered-panel" data-tooltip-panel role="tooltip">Hovered content</span>
    `;
    const focusedTrigger = document.getElementById("focused-trigger");
    const focusedPanel = document.getElementById("focused-panel");
    const hoveredTrigger = document.getElementById("hovered-trigger");
    const hoveredPanel = document.getElementById("hovered-panel");
    focusedTrigger.focus();
    dispatchPointerEvent(hoveredTrigger, "pointerover");

    // Move the focused trigger, then scroll.
    focusedTrigger.getBoundingClientRect = () => createRect(620, 600, 80, 24);
    focusedPanel.getBoundingClientRect = () => createRect(0, 0, 288, 200);
    hoveredTrigger.getBoundingClientRect = () => createRect(20, 600, 80, 24);
    hoveredPanel.getBoundingClientRect = () => createRect(0, 0, 288, 200);
    window.dispatchEvent(new Event("scroll"));

    // Verify the focused panel follows its trigger, not only the hovered one.
    expect(focusedPanel.style.top).to.equal("396px");
    expect(focusedPanel.style.left).to.equal("516px");
    expect(hoveredPanel.style.top).to.equal("396px");
    expect(hoveredPanel.style.left).to.equal("16px");

    // Clear the module's tracked tooltip state.
    focusedTrigger.blur();
    document.dispatchEvent(new Event("htmx:beforeHistorySave"));
  });

  it("keeps the scroll offset of a height-limited tooltip when it is repositioned", () => {
    // Render a panel that only fits at the full viewport height and clamp it.
    const { tooltip, trigger } = renderScrollableTooltipFixture();
    trigger.getBoundingClientRect = () => createRect(620, 360, 80, 24);
    positionTooltipPanel(trigger, tooltip);
    expect(tooltip.style.maxHeight).to.equal("364px");

    // Scroll the panel, then position it again.
    tooltip.scrollTop = 100;
    positionTooltipPanel(trigger, tooltip);

    // Verify the reader's place in the panel survives the full-height measurement.
    expect(tooltip.scrollTop).to.equal(100);
  });

  it("ignores scroll events from inside a tooltip panel", () => {
    // Render a clamped panel, track it through its focused trigger and scroll it.
    const { tooltip, trigger } = renderScrollableTooltipFixture();
    trigger.getBoundingClientRect = () => createRect(620, 360, 80, 24);
    trigger.focus();
    tooltip.scrollTop = 100;
    const top = tooltip.style.top;

    // Move the trigger and scroll inside the panel only.
    trigger.getBoundingClientRect = () => createRect(620, 300, 80, 24);
    tooltip.dispatchEvent(new Event("scroll"));

    // Verify the panel was not repositioned and kept its scroll offset.
    expect(tooltip.style.top).to.equal(top);
    expect(tooltip.scrollTop).to.equal(100);

    // Clear the module's tracked tooltip state.
    trigger.blur();
    document.dispatchEvent(new Event("htmx:beforeHistorySave"));
  });
});

describe("tooltip interaction", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    document.activeElement?.blur?.();
    // Clear the module's hovered and active tooltip state between cases.
    document.dispatchEvent(new Event("htmx:beforeHistorySave"));
    resetDom();
  });

  it("focuses a clicked dashboard trigger without dismissing it", () => {
    // Render a dashboard badge trigger.
    const { trigger, wrapper } = renderDashboardBadgesFixture();

    // Click the trigger; a synthetic click doesn't focus buttons natively.
    trigger.click();

    // Verify the enhancement moved focus to the trigger.
    expect(document.activeElement).to.equal(trigger);
    expect(wrapper.hasAttribute(DISMISSED_ATTRIBUTE)).to.equal(false);
    expectNoDisclosureState();
  });

  it("keeps a tapped trigger focused through the Chromium tap order", () => {
    // Render a dashboard badge trigger.
    const { trigger, wrapper } = renderDashboardBadgesFixture();

    // Replay the touch sequence: pointerdown, native focus, then click.
    dispatchPointerEvent(trigger, "pointerdown", { pointerType: "touch" });
    trigger.focus();
    trigger.click();

    // Verify the tap didn't toggle the tooltip closed.
    expect(document.activeElement).to.equal(trigger);
    expect(wrapper.hasAttribute(DISMISSED_ATTRIBUTE)).to.equal(false);
    expectNoDisclosureState();
  });

  it("keeps a hovered trigger open when it is clicked", () => {
    // Render a dashboard badge trigger and hover it.
    const { trigger, wrapper } = renderDashboardBadgesFixture();
    dispatchPointerEvent(trigger, "pointerover");

    // Click the hovered trigger twice.
    trigger.click();
    trigger.click();

    // Verify clicks never close the tooltip.
    expect(document.activeElement).to.equal(trigger);
    expect(wrapper.hasAttribute(DISMISSED_ATTRIBUTE)).to.equal(false);
    expectNoDisclosureState();
  });

  it("dismisses the focused trigger on Escape without moving focus", () => {
    // Render a dashboard badge trigger and focus it.
    const { trigger, wrapper } = renderDashboardBadgesFixture();
    trigger.focus();

    // Press Escape on the focused trigger.
    const escapeEvent = dispatchEscape(trigger);

    // Verify the wrapper is dismissed, focus stays, and other handlers still run.
    expect(wrapper.hasAttribute(DISMISSED_ATTRIBUTE)).to.equal(true);
    expect(document.activeElement).to.equal(trigger);
    expect(escapeEvent.defaultPrevented).to.equal(false);
    expectNoDisclosureState();
  });

  it("dismisses the hovered trigger on Escape while focus is in another control", () => {
    // Render a dashboard badge trigger, focus the search input, and hover the trigger.
    const { search, trigger, wrapper } = renderDashboardBadgesFixture();
    search.focus();
    dispatchPointerEvent(trigger, "pointerover");

    // Press Escape inside the search input.
    dispatchEscape(search);

    // Verify the hovered wrapper is dismissed and focus stays in the input.
    expect(wrapper.hasAttribute(DISMISSED_ATTRIBUTE)).to.equal(true);
    expect(document.activeElement).to.equal(search);
    expectNoDisclosureState();
  });

  it("clears the dismissal once the trigger loses focus and the pointer leaves", () => {
    // Render a focused and hovered dashboard trigger and dismiss it.
    const { outside, trigger, wrapper } = renderDashboardBadgesFixture();
    trigger.focus();
    dispatchPointerEvent(trigger, "pointerover");
    dispatchEscape(trigger);

    // Blur the trigger while the pointer still hovers it.
    trigger.blur();
    expect(wrapper.hasAttribute(DISMISSED_ATTRIBUTE)).to.equal(true);

    // Move the pointer out of the wrapper.
    dispatchPointerEvent(trigger, "pointerout", { relatedTarget: outside });
    expect(wrapper.hasAttribute(DISMISSED_ATTRIBUTE)).to.equal(false);

    // Verify hover and focus can open the tooltip again.
    dispatchPointerEvent(trigger, "pointerover");
    trigger.focus();
    expect(wrapper.hasAttribute(DISMISSED_ATTRIBUTE)).to.equal(false);
    expectNoDisclosureState();
  });

  it("keeps the dismissal while focus remains after the pointer leaves", () => {
    // Render a focused and hovered dashboard trigger and dismiss it.
    const { outside, trigger, wrapper } = renderDashboardBadgesFixture();
    trigger.focus();
    dispatchPointerEvent(trigger, "pointerover");
    dispatchEscape(trigger);

    // Move the pointer out while the trigger keeps focus.
    dispatchPointerEvent(trigger, "pointerout", { relatedTarget: outside });
    expect(wrapper.hasAttribute(DISMISSED_ATTRIBUTE)).to.equal(true);

    // Verify blurring the trigger clears the dismissal.
    trigger.blur();
    expect(wrapper.hasAttribute(DISMISSED_ATTRIBUTE)).to.equal(false);
    expectNoDisclosureState();
  });

  it("blurs a focused trigger only on a press outside its wrapper", () => {
    // Render a focused dashboard trigger and dismiss it.
    const { outside, panelContent, trigger, wrapper } = renderDashboardBadgesFixture();
    trigger.focus();
    dispatchEscape(trigger);

    // Press inside the open panel. A synthetic press has no native focus side effect, so this
    // only proves the handler leaves the trigger alone; browsers may still move focus natively.
    dispatchPointerEvent(panelContent, "pointerdown", { pointerType: "touch" });
    expect(document.activeElement).to.equal(trigger);

    // Press outside the wrapper.
    dispatchPointerEvent(outside, "pointerdown", { pointerType: "touch" });

    // Verify the trigger is blurred, nothing else is focused, and the dismissal is cleared.
    expect(document.activeElement).to.equal(document.body);
    expect(wrapper.hasAttribute(DISMISSED_ATTRIBUTE)).to.equal(false);
    expectNoDisclosureState();
  });

  it("treats the refunds recovery span as both trigger and wrapper", () => {
    // Render the recovery shape: a focusable span holding a disabled button and its panel.
    const { outside, panelContent, trigger } = renderRecoveryFixture();

    // Click the span, where real presses land because the button ignores pointer events.
    trigger.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    expect(document.activeElement).to.equal(trigger);
    expect(trigger.hasAttribute(DISMISSED_ATTRIBUTE)).to.equal(false);

    // Press Escape and verify the span itself is dismissed and keeps focus.
    dispatchEscape(trigger);
    expect(trigger.hasAttribute(DISMISSED_ATTRIBUTE)).to.equal(true);
    expect(document.activeElement).to.equal(trigger);

    // Press on the span and inside its panel; both are inside the wrapper, so the handler
    // doesn't blur the span (synthetic presses have no native focus side effect).
    dispatchPointerEvent(trigger, "pointerdown");
    dispatchPointerEvent(panelContent, "pointerdown");
    expect(document.activeElement).to.equal(trigger);

    // Press outside and verify the span is blurred.
    dispatchPointerEvent(outside, "pointerdown");
    expect(document.activeElement).to.equal(document.body);
    expectNoDisclosureState();
  });

  it("supports the session counter shape with the panel beside its button", () => {
    // Render the session-card counter shape.
    document.body.innerHTML = `
      <div id="dashboard-content">
        <span data-session-labels-more>
          <button type="button" aria-describedby="labels-more-tooltip">+2</button>
          <span id="labels-more-tooltip" role="tooltip" data-tooltip-panel>Labels</span>
        </span>
      </div>
    `;
    const trigger = document.querySelector("[aria-describedby]");
    const wrapper = document.querySelector("[data-session-labels-more]");

    // Click the counter and press Escape.
    trigger.click();
    expect(document.activeElement).to.equal(trigger);
    dispatchEscape(trigger);

    // Verify the counter wrapper is dismissed.
    expect(wrapper.hasAttribute(DISMISSED_ATTRIBUTE)).to.equal(true);
    expectNoDisclosureState();
  });

  it("ignores tooltip triggers outside the dashboard content", () => {
    // Render the public Attend shape: the panel sits in a contents span beside the button.
    document.body.innerHTML = `
      <div>
        <button type="button" id="attend-button" aria-describedby="attend-tooltip">Attend</button>
        <span class="contents">
          <span id="attend-tooltip" role="tooltip" data-tooltip-panel>External payment</span>
        </span>
        <button type="button" id="outside-button">Outside</button>
      </div>
    `;
    const trigger = document.getElementById("attend-button");
    const focusCalls = spyOnFocus(trigger);

    // Click and hover the trigger.
    trigger.click();
    dispatchPointerEvent(trigger, "pointerover");
    expect(focusCalls.count).to.equal(0);

    // Focus it, press Escape, then press outside.
    focusCalls.restore();
    trigger.focus();
    dispatchEscape(trigger);
    dispatchPointerEvent(document.getElementById("outside-button"), "pointerdown");

    // Verify no dismissal was set and focus wasn't touched.
    expect(document.querySelector(`[${DISMISSED_ATTRIBUTE}]`)).to.equal(null);
    expect(document.activeElement).to.equal(trigger);
    expectNoDisclosureState();
  });

  it("ignores described-by targets that aren't tooltip panels", () => {
    // Render a form field described by help text inside the dashboard content.
    document.body.innerHTML = `
      <div id="dashboard-content">
        <input id="field" type="text" aria-describedby="field-help" />
        <p id="field-help">Help text</p>
        <button type="button" id="outside-button">Outside</button>
      </div>
    `;
    const field = document.getElementById("field");
    const focusCalls = spyOnFocus(field);

    // Click and hover the field.
    field.click();
    dispatchPointerEvent(field, "pointerover");
    expect(focusCalls.count).to.equal(0);

    // Focus it, press Escape, then press outside.
    focusCalls.restore();
    field.focus();
    dispatchEscape(field);
    dispatchPointerEvent(document.getElementById("outside-button"), "pointerdown");

    // Verify the field kept focus and nothing was dismissed.
    expect(document.querySelector(`[${DISMISSED_ATTRIBUTE}]`)).to.equal(null);
    expect(document.activeElement).to.equal(field);
    expectNoDisclosureState();
  });

  ["htmx:beforeHistorySave", "htmx:historyRestore"].forEach((eventName) => {
    it(`clears dismissals and the hovered wrapper on ${eventName}`, () => {
      // Dismiss a focused trigger and a hovered one.
      const { search, secondTrigger, secondWrapper, trigger, wrapper } = renderDashboardBadgesFixture();
      trigger.focus();
      dispatchPointerEvent(secondTrigger, "pointerover");
      dispatchEscape(trigger);
      expect(wrapper.hasAttribute(DISMISSED_ATTRIBUTE)).to.equal(true);
      expect(secondWrapper.hasAttribute(DISMISSED_ATTRIBUTE)).to.equal(true);

      // Dispatch the HTMX history event.
      document.dispatchEvent(new Event(eventName));

      // Verify every dismissal is gone.
      expect(document.querySelector(`[${DISMISSED_ATTRIBUTE}]`)).to.equal(null);

      // Verify the hovered wrapper was forgotten: Escape elsewhere dismisses nothing.
      search.focus();
      dispatchEscape(search);
      expect(document.querySelector(`[${DISMISSED_ATTRIBUTE}]`)).to.equal(null);
      expectNoDisclosureState();
    });
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

const dispatchEscape = (target) => {
  const event = new KeyboardEvent("keydown", {
    bubbles: true,
    cancelable: true,
    key: "Escape",
  });
  target.dispatchEvent(event);
  return event;
};

const dispatchPointerEvent = (target, type, { pointerType = "mouse", relatedTarget = null } = {}) => {
  target.dispatchEvent(
    new PointerEvent(type, {
      bubbles: true,
      composed: true,
      pointerType,
      relatedTarget,
    }),
  );
};

/** Asserts tooltips keep tooltip semantics only, with no disclosure state. */
const expectNoDisclosureState = () => {
  expect(document.querySelector("[aria-expanded], [aria-controls]")).to.equal(null);
};

const renderDashboardBadgesFixture = () => {
  document.body.innerHTML = `
    <div id="dashboard-content">
      <input id="search" type="search" aria-label="Search" />
      <span id="badge-wrapper" class="relative inline-flex">
        <button type="button" id="badge-trigger" aria-describedby="badge-tooltip">
          <span class="custom-badge">Paid</span>
        </button>
        <span id="badge-tooltip" role="tooltip" data-tooltip-panel>
          <span id="badge-panel-content">Payment details</span>
        </span>
      </span>
      <span id="second-badge-wrapper" class="relative inline-flex">
        <button type="button" id="second-badge-trigger" aria-describedby="second-badge-tooltip">
          <span class="custom-badge">Refunded</span>
        </button>
        <span id="second-badge-tooltip" role="tooltip" data-tooltip-panel>Refund details</span>
      </span>
      <button type="button" id="outside-button">Outside</button>
    </div>
  `;

  return {
    outside: document.getElementById("outside-button"),
    panelContent: document.getElementById("badge-panel-content"),
    search: document.getElementById("search"),
    secondTrigger: document.getElementById("second-badge-trigger"),
    secondWrapper: document.getElementById("second-badge-wrapper"),
    trigger: document.getElementById("badge-trigger"),
    wrapper: document.getElementById("badge-wrapper"),
  };
};

const renderRecoveryFixture = () => {
  document.body.innerHTML = `
    <div id="dashboard-content">
      <span id="recovery-trigger" class="relative block" tabindex="0" aria-describedby="recovery-tooltip">
        <button type="button" disabled aria-disabled="true" class="pointer-events-none">
          Complete recovery
        </button>
        <span id="recovery-tooltip" role="tooltip" data-tooltip-panel>
          <span id="recovery-panel-content">Events write access is required.</span>
        </span>
      </span>
      <button type="button" id="outside-button">Outside</button>
    </div>
  `;

  return {
    outside: document.getElementById("outside-button"),
    panelContent: document.getElementById("recovery-panel-content"),
    trigger: document.getElementById("recovery-trigger"),
  };
};

const renderScrollableTooltipFixture = () => {
  document.body.innerHTML = `
    <button aria-describedby="tooltip-panel">Details</button>
    <div id="tooltip-panel" data-tooltip-panel role="tooltip">
      <div style="height: 500px; width: 200px">Tooltip content</div>
    </div>
  `;

  return {
    tooltip: document.getElementById("tooltip-panel"),
    trigger: document.querySelector("button"),
  };
};

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

const spyOnFocus = (element) => {
  const calls = { count: 0 };
  const originalFocus = element.focus;
  element.focus = (...args) => {
    calls.count += 1;
    return originalFocus.apply(element, args);
  };
  calls.restore = () => {
    element.focus = originalFocus;
  };
  return calls;
};
