import { waitForActionResponses } from "../../utils.js";

/**
 * Runs a community dashboard mutation and waits for its response and the table refresh.
 * @param {import("@playwright/test").Page} page - Community dashboard page.
 * @param {string} refreshPath - Pathname of the refreshed dashboard table.
 * @param {() => Promise<unknown>|unknown} action - Click that sends the mutation.
 * @param {object} responseMatcher - `waitForActionResponse` matcher for the mutation.
 * @returns {Promise<import("@playwright/test").Response[]>} Mutation and refresh responses.
 */
export const waitForCommunityDashboardMutation = (page, refreshPath, action, responseMatcher) =>
  waitForActionResponses(page, action, [
    responseMatcher,
    { method: "GET", pathname: refreshPath, status: 200 },
  ]);
