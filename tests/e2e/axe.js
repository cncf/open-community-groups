import AxeBuilder from "@axe-core/playwright";
import { expect } from "@playwright/test";

import { AXE_ALLOWLIST } from "./axe-allowlist.js";

// `color-contrast` stays disabled until the palette is audited separately.
const AXE_DISABLED_RULES = ["color-contrast"];
const AXE_FAILING_IMPACTS = new Set(["critical", "serious"]);
const AXE_TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"];

/**
 * Scans the current page with axe (WCAG 2.0/2.1 A and AA) and fails on critical or
 * serious violations that `AXE_ALLOWLIST` does not list for this scan, and on allowlist
 * entries for this scan that no longer match a violation.
 * @param {import("@playwright/test").Page} page - Page already loaded and settled.
 * @param {{ exclude?: string[], scan: string }} options - `scan` names the allowlist
 *   scope; `exclude` lists CSS selectors left out of the scan (callers give the reason).
 */
export const expectNoAxeViolations = async (page, { exclude = [], scan }) => {
  const builder = new AxeBuilder({ page }).withTags(AXE_TAGS).disableRules(AXE_DISABLED_RULES);
  for (const selector of exclude) {
    builder.exclude(selector);
  }
  const { violations } = await builder.analyze();

  const allowlist = AXE_ALLOWLIST.filter((entry) => entry.scan === scan);
  const failingNodes = violations.flatMap((violation) =>
    violation.nodes
      .map((node) => ({
        help: violation.help,
        html: node.html,
        impact: node.impact ?? violation.impact,
        rule: violation.id,
        target: node.target,
      }))
      .filter((node) => AXE_FAILING_IMPACTS.has(node.impact)),
  );

  const matchedEntries = new Set();
  const unexpected = [];
  for (const node of failingNodes) {
    let entry;
    for (const candidate of allowlist) {
      if (
        candidate.rule === node.rule &&
        (await matchesAllowlistTarget(page, node.target, candidate.target))
      ) {
        entry = candidate;
        break;
      }
    }
    if (entry) {
      matchedEntries.add(entry);
      continue;
    }

    unexpected.push({ ...node, target: formatTarget(node.target) });
  }

  const stale = allowlist.filter((entry) => !matchedEntries.has(entry));
  expect(unexpected, `unexpected critical/serious axe violations on ${scan}`).toEqual([]);
  expect(stale, `stale axe allowlist entries for ${scan}`).toEqual([]);
};

/** Formats an axe node target (nested arrays for frames and shadow roots) as one string. */
const formatTarget = (target) =>
  target.map((selector) => (Array.isArray(selector) ? selector.join(" >>> ") : selector)).join(" ");

/**
 * Checks whether a violating node is the allowlist target or sits inside it. Entries
 * without a target match every node of their rule; frame and shadow targets never match.
 */
const matchesAllowlistTarget = async (page, nodeTarget, allowedTarget) => {
  if (!allowedTarget) {
    return true;
  }
  if (nodeTarget.length !== 1 || typeof nodeTarget[0] !== "string") {
    return false;
  }

  return page.evaluate(
    ([selector, allowedSelector]) => Boolean(document.querySelector(selector)?.closest(allowedSelector)),
    [nodeTarget[0], allowedTarget],
  );
};
