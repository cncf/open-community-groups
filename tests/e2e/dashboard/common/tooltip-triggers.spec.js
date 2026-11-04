import { expect, test } from "../../fixtures.js";
import { cleanupEventsByIds, setupLabeledSessionEvent } from "../../data-graphs/events.js";
import { TEST_GROUP_IDS, TEST_PAYMENT_EVENT_IDS } from "../../seed.js";
import { enableDesktopVersion } from "../../snapshots.js";
import { navigateToPath, waitForActionResponse, waitForHtmxSettle } from "../../utils.js";
import {
  openCfsEventSubmissionsTab,
  openEventUpdateFormByName,
  showEventEditorSection,
} from "../group/events/helpers.js";
import { getRefundRow, openRefundsDashboard } from "../group/refunds/helpers.js";

// Dashboard tooltip triggers (common/tooltip-panel.js): CSS hover and focus-within decide what is
// shown, and the module only focuses a clicked trigger, blurs it on an outside press and dismisses
// it on Escape.
//
// - Panels are found by their id, not with `getByRole("tooltip")`: a hidden panel leaves the
//   accessibility tree, so `toBeHidden()` on a role locator would pass without matching anything.
// - Focus is never asserted after a click inside an open panel. Chromium moves focus to <body> on a
//   mousedown over non-focusable content before any handler runs; the panel stays open there only
//   because the pointer is still over its wrapper.
// - Hover persistence across the 4px gap between trigger and panel is proven with a stepped
//   `page.mouse.move`, so the pointer really passes through the gap.

const AWARDS_PATH = "/dashboard/group?tab=awards";

const COMPLETED_REFUNDS_PATH = `/dashboard/group?tab=refunds&view=completed&event_id=${TEST_PAYMENT_EVENT_IDS.refunds}`;

const CFS_LABELS_SUBMISSION_ID = "99999999-9999-9999-9999-999999999913";

const CFS_LABELS_SUBMISSION_TITLE = "Scaling Community Workshops";

const MEMBERS_MENU_LINK_SELECTOR =
  '#dashboard-menu-drawer a[hx-push-url][href="/dashboard/group?tab=members"]';

const REFUNDS_DESCRIPTION =
  "Review attendee requests and track provider and external refunds through completion.";

const REJECTED_REFUND_ATTENDEE = "E2E Pending One";

const REVOKED_AWARD_ID = "dadadada-dada-dada-dada-dadadadada04";

const VIEWPORT_PADDING = 16;

test.describe("dashboard tooltip triggers", () => {
  test("refunds details badge opens on hover, click and focus and closes on Escape and outside presses", async ({
    organizerGroupPage: page,
  }) => {
    const { outside, tooltip, trigger, wrapper } = await openRejectedRefundDetails(page);

    await test.step("tooltip semantics only", async () => {
      // The trigger describes its panel and exposes no disclosure state.
      await expectTooltipContract(trigger, tooltip);
    });

    await test.step("hover opens it and leaving closes it", async () => {
      // Hover the badge, then move the pointer away.
      await trigger.hover();
      await expect(tooltip).toBeVisible();
      await outside.hover();
      await expect(tooltip).toBeHidden();
    });

    await test.step("hover persists across the gap into the panel", async () => {
      // Hover the badge and check the panel is centred on it inside the viewport.
      await trigger.hover();
      await expect(tooltip).toBeVisible();
      await expectPanelPlacedInViewport(page, trigger, tooltip);

      // Cross the gap in small steps, then reach the panel centre, on hover alone.
      await movePointerFromTriggerIntoPanel(page, trigger, tooltip);
      await outside.hover();
      await expect(tooltip).toBeHidden();
    });

    await test.step("click keeps it open without hover", async () => {
      // Click the badge, then move the pointer away: focus keeps the panel open.
      await trigger.click();
      await expect(trigger).toBeFocused();
      await outside.hover();
      await expect(tooltip).toBeVisible();
      await expect(trigger).toBeFocused();
    });

    await test.step("Escape hides it without moving focus", async () => {
      // Dismiss the focused trigger.
      await page.keyboard.press("Escape");
      await expect(tooltip).toBeHidden();
      await expect(trigger).toBeFocused();
      await expect(wrapper).toHaveAttribute("data-tooltip-dismissed", "");
    });

    await test.step("Tab away and Shift+Tab back reopen it", async () => {
      // Leaving with the keyboard clears the dismissal.
      await page.keyboard.press("Tab");
      await expect(trigger).not.toBeFocused();
      await expect(tooltip).toBeHidden();
      await expect(wrapper).not.toHaveAttribute("data-tooltip-dismissed");

      // Coming back shows the panel again.
      await page.keyboard.press("Shift+Tab");
      await expect(trigger).toBeFocused();
      await expect(tooltip).toBeVisible();
    });

    await test.step("an outside press closes it", async () => {
      // Press outside the wrapper while the trigger has focus.
      await outside.click();
      await expect(tooltip).toBeHidden();
      await expect(trigger).not.toBeFocused();
      await expect(wrapper).not.toHaveAttribute("data-tooltip-dismissed");
    });
  });

  test("an HTMX history restore never brings back a dismissed tooltip", async ({
    organizerGroupPage: page,
  }) => {
    const { outside, row, tooltip, trigger, wrapper } = await openRejectedRefundDetails(page);

    // Keep the pointer away, focus the trigger and dismiss it with Escape.
    await outside.hover();
    await trigger.focus();
    await expect(tooltip).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(wrapper).toHaveAttribute("data-tooltip-dismissed", "");
    await expect(tooltip).toBeHidden();

    // Navigate to members without pointer or focus events, so nothing else clears the dismissal.
    await waitForActionResponse(
      page,
      () =>
        page.evaluate((selector) => {
          const link = document.querySelector(selector);
          if (!(link instanceof HTMLAnchorElement)) {
            throw new Error(`Missing menu link: ${selector}`);
          }
          link.click();
        }, MEMBERS_MENU_LINK_SELECTOR),
      { method: "GET", params: { tab: "members" }, pathname: "/dashboard/group", status: 200 },
    );
    await expect(page).toHaveURL(/[?&]tab=members(?:&|$)/u);

    // Go back: the refunds page comes from the HTMX history snapshot, without the dismissal.
    await page.goBack();
    await expect(page).toHaveURL(/[?&]tab=refunds(?:&|$)/u);
    await waitForHtmxSettle(page);
    await expect(row).toBeVisible();
    await expect(page.locator("[data-tooltip-dismissed]")).toHaveCount(0);

    // The restored trigger opens again on hover.
    await trigger.hover();
    await expect(tooltip).toBeVisible();
  });

  test("session card labels counter opens on click and closes on Escape", async ({
    organizerGroupPage: page,
    owned,
  }) => {
    // Create an event whose session collapses its labels behind the counter and open its sessions.
    const event = owned.track(
      setupLabeledSessionEvent({ groupId: TEST_GROUP_IDS.community1.alpha }),
      (graph) => cleanupEventsByIds([graph.eventId]),
    );
    await page.setViewportSize({ width: 1280, height: 900 });
    await openEventUpdateFormByName(page, event.name, event.eventId);
    await showEventEditorSection(page, "sessions");
    const card = page.locator("sessions-section session-card").filter({ hasText: event.sessionName });
    const wrapper = card.locator("[data-session-labels-more]");
    const trigger = wrapper.locator("button");
    const tooltip = wrapper.locator("[data-tooltip-panel]");
    await expect(trigger).toBeVisible();
    await expectTooltipContract(trigger, tooltip);

    // Click the counter to focus it and show the hidden labels.
    await trigger.click();
    await expect(tooltip).toBeVisible();
    await expect(trigger).toBeFocused();

    // Escape hides the panel and keeps focus on the counter.
    await page.keyboard.press("Escape");
    await expect(tooltip).toBeHidden();
    await expect(wrapper).toHaveAttribute("data-tooltip-dismissed", "");
    await expect(trigger).toBeFocused();
  });

  test("submission labels summary opens on click and closes on Escape", async ({
    eventsManagerGroupPage: page,
  }) => {
    // Load the CFS submissions at xl, where two labels collapse into a labels badge.
    await page.setViewportSize({ width: 1280, height: 900 });
    const content = await openCfsEventSubmissionsTab(page);
    const row = content.locator("tr", { hasText: CFS_LABELS_SUBMISSION_TITLE });
    const trigger = row.getByRole("button", { exact: true, name: "2 labels" });
    const tooltip = page.locator(`#submission-labels-${CFS_LABELS_SUBMISSION_ID}`);
    await expect(trigger).toBeVisible();
    await expectTooltipContract(trigger, tooltip);

    // Click the badge to focus it and list both labels.
    await trigger.click();
    await expect(tooltip).toBeVisible();
    await expect(tooltip).toContainText("Platform");
    await expect(tooltip).toContainText("Workshop");
    await expect(trigger).toBeFocused();

    // Escape hides the panel and keeps focus on the badge.
    await page.keyboard.press("Escape");
    await expect(tooltip).toBeHidden();
    await expect(trigger).toBeFocused();
  });

  test("award revocation badge opens on click and closes on Escape below xl", async ({
    organizerGroupPage: page,
  }) => {
    // Load the revoked awards at lg, where the revocation details move into a tooltip.
    await page.setViewportSize({ width: 1024, height: 900 });
    await navigateToPath(page, `${AWARDS_PATH}&status=revoked`);
    const tooltip = page.locator(`#award-revocation-${REVOKED_AWARD_ID}`);
    const row = page.getByRole("table", { name: "Awards list" }).locator("tbody tr").filter({ has: tooltip });
    const trigger = row.getByRole("button", { exact: true, name: "Revoked" });
    await expect(trigger).toBeVisible();
    await expectTooltipContract(trigger, tooltip);

    // Click the badge to focus it and show the revocation details.
    await trigger.click();
    await expect(tooltip).toBeVisible();
    await expect(tooltip).toContainText("Revoked on");
    await expect(tooltip).toContainText("Award issued in error");
    await expect(trigger).toBeFocused();

    // Escape hides the panel and keeps focus on the badge.
    await page.keyboard.press("Escape");
    await expect(tooltip).toBeHidden();
    await expect(trigger).toBeFocused();
  });

  test("refunds details badge opens on tap and closes on an outside tap @mobile", async ({
    organizerGroupPage: page,
  }) => {
    // Lay the dashboard out at 1280 on a touch device.
    await enableDesktopVersion(page);
    const { outside, tooltip, trigger } = await openRejectedRefundDetails(page);
    expect(await page.evaluate(() => navigator.maxTouchPoints)).toBeGreaterThan(0);

    // A tap opens the panel: the tap's pointerdown, focus and click order doesn't close it.
    await trigger.tap();
    await expect(tooltip).toBeVisible();
    await expect(trigger).toBeFocused();

    // A tap outside the wrapper closes it.
    await outside.tap();
    await expect(tooltip).toBeHidden();
    await expect(trigger).not.toBeFocused();

    // Another tap on the trigger opens it again.
    await trigger.tap();
    await expect(tooltip).toBeVisible();
  });

  // Firefox and WebKit run this test in CI on Linux runners, so it proves their focus-on-click
  // behaviour there. It does not prove macOS Safari or macOS Firefox, which don't focus buttons on
  // click: the unit test "click on a scoped trigger focuses it" (tests/unit/common/tooltip-panel.test.js)
  // covers that path, because a synthetic click() doesn't focus natively and only the module's
  // trigger.focus() can. The manual WebKit pass stays the real-Safari check.
  test("refunds details badge keeps focus-driven visibility across engines @smoke", async ({
    organizerGroupPage: page,
  }) => {
    const { outside, tooltip, trigger } = await openRejectedRefundDetails(page);

    await test.step("click focuses the trigger and keeps it open without hover", async () => {
      // Click the badge, then move the pointer outside its wrapper.
      await trigger.click();
      await outside.hover();
      await expect(tooltip).toBeVisible();
      await expect(trigger).toBeFocused();
    });

    await test.step("Escape hides it without moving focus", async () => {
      // Dismiss the focused trigger.
      await page.keyboard.press("Escape");
      await expect(tooltip).toBeHidden();
      await expect(trigger).toBeFocused();
    });

    await test.step("a new click reopens it and an outside press closes it", async () => {
      // Click again to clear the dismissal, then leave with the pointer.
      await trigger.click();
      await outside.hover();
      await expect(tooltip).toBeVisible();

      // Press outside the wrapper.
      await outside.click();
      await expect(tooltip).toBeHidden();
      await expect(trigger).not.toBeFocused();
    });
  });
});

/**
 * Keeps a value inside an inclusive range.
 * @param {number} value - Preferred value.
 * @param {number} minimum - Minimum allowed value.
 * @param {number} maximum - Maximum allowed value.
 * @returns {number} Clamped value.
 */
const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(value, maximum));

/**
 * Checks the panel left edge: centred on the trigger and clamped to the viewport padding, which
 * only holds when `positionTooltipPanel` resets the Tailwind `translate` utility.
 * @param {import("@playwright/test").Page} page - Page showing the tooltip.
 * @param {import("@playwright/test").Locator} trigger - Tooltip trigger.
 * @param {import("@playwright/test").Locator} tooltip - Visible tooltip panel.
 */
const expectPanelPlacedInViewport = async (page, trigger, tooltip) => {
  await expect
    .poll(
      async () => {
        const triggerBox = await trigger.boundingBox();
        const panelBox = await tooltip.boundingBox();
        const viewportWidth = await page.evaluate(() => window.visualViewport?.width || window.innerWidth);
        const expectedLeft = clamp(
          triggerBox.x + triggerBox.width / 2 - panelBox.width / 2,
          VIEWPORT_PADDING,
          viewportWidth - VIEWPORT_PADDING - panelBox.width,
        );

        return panelBox.x >= VIEWPORT_PADDING && Math.abs(panelBox.x - expectedLeft) <= 1;
      },
      { message: "tooltip panel is centred on its trigger and at least 16px from the viewport edge" },
    )
    .toBe(true);
};

/**
 * Checks the tooltip-only semantics: the trigger describes the panel and carries no disclosure
 * state.
 * @param {import("@playwright/test").Locator} trigger - Tooltip trigger.
 * @param {import("@playwright/test").Locator} tooltip - Tooltip panel.
 */
const expectTooltipContract = async (trigger, tooltip) => {
  await expect(tooltip).toHaveAttribute("role", "tooltip");
  await expect(trigger).toHaveAttribute("aria-describedby", await tooltip.getAttribute("id"));
  await expect(trigger).not.toHaveAttribute("aria-expanded");
  await expect(trigger).not.toHaveAttribute("aria-controls");
};

/**
 * Moves the pointer from the trigger edge across the gap onto the panel in sub-pixel steps, so
 * points inside the gap are hovered, then on to the panel centre. A hidden panel can't be hovered,
 * so it is only still visible at the end when hover never dropped on the way.
 * @param {import("@playwright/test").Page} page - Page showing the tooltip.
 * @param {import("@playwright/test").Locator} trigger - Hovered tooltip trigger.
 * @param {import("@playwright/test").Locator} tooltip - Visible tooltip panel.
 */
const movePointerFromTriggerIntoPanel = async (page, trigger, tooltip) => {
  const triggerBox = await trigger.boundingBox();
  const panelBox = await tooltip.boundingBox();
  const panelIsAbove = panelBox.y + panelBox.height <= triggerBox.y + 0.5;
  const pointerX = clamp(
    triggerBox.x + triggerBox.width / 2,
    panelBox.x + 2,
    panelBox.x + panelBox.width - 2,
  );

  await page.mouse.move(pointerX, panelIsAbove ? triggerBox.y + 1 : triggerBox.y + triggerBox.height - 1);
  await page.mouse.move(pointerX, panelIsAbove ? panelBox.y + panelBox.height - 2 : panelBox.y + 2, {
    steps: 10,
  });
  await expect(tooltip).toBeVisible();
  await page.mouse.move(panelBox.x + panelBox.width / 2, panelBox.y + panelBox.height / 2, { steps: 10 });
  await expect(tooltip).toBeVisible();
};

/**
 * Opens the completed refunds of the seeded review event and returns the details badge of the
 * rejected refund, its panel and wrapper, plus a non-interactive point outside the wrapper.
 * @param {import("@playwright/test").Page} page - Organizer page of the seeded group.
 */
const openRejectedRefundDetails = async (page) => {
  const dashboardContent = await openRefundsDashboard(page, COMPLETED_REFUNDS_PATH);
  const row = getRefundRow(dashboardContent, REJECTED_REFUND_ATTENDEE);
  await expect(row).toContainText("Rejected");
  const trigger = row.locator('button[aria-describedby^="refund-details-"]');
  await expect(trigger).toHaveCount(1);
  const tooltipId = await trigger.getAttribute("aria-describedby");

  return {
    outside: dashboardContent.getByText(REFUNDS_DESCRIPTION, { exact: true }),
    row,
    tooltip: page.locator(`#${tooltipId}`),
    trigger,
    wrapper: trigger.locator("xpath=.."),
  };
};
