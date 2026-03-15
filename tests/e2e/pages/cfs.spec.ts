import { expect, test } from "../fixtures";

import {
  TEST_COMMUNITY_NAME,
  TEST_GROUP_SLUGS,
  navigateToEvent,
} from "../utils";

const CFS_EVENT_SLUG = "alpha-cfs-summit";

test.describe("call for speakers", () => {
  test("public event page renders the CFS section for an open event", async ({
    page,
  }) => {
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      CFS_EVENT_SLUG,
    );

    await expect(page.getByText("Call for Speakers", { exact: true })).toBeVisible();
    await expect(page.getByText(/Submissions open:/)).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Submit session proposal" }),
    ).toBeEnabled();
  });

  test("anonymous users are prompted to sign in before submitting", async ({
    page,
  }) => {
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      CFS_EVENT_SLUG,
    );

    await page.getByRole("button", { name: "Submit session proposal" }).click();

    await expect(
      page.getByText("You need to sign in to submit a proposal for this event."),
    ).toBeVisible();
    await expect(page.getByRole("link", { name: "Sign in" })).toBeVisible();
  });

  test("eligible and already-submitted proposals are distinguished in the modal", async ({
    member1Page,
  }) => {
    await navigateToEvent(
      member1Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      CFS_EVENT_SLUG,
    );

    await member1Page
      .getByRole("button", { name: "Submit session proposal" })
      .click();

    await expect(
      member1Page.getByRole("dialog", { name: "Submit a proposal" }),
    ).toBeVisible();
    await expect(member1Page.locator("#session_proposal_id")).toBeVisible();
    await expect(member1Page.locator("cfs-label-selector")).toBeVisible();
    await expect(
      member1Page.getByText(
        "Proposals already submitted to this event will appear disabled.",
      ),
    ).toBeVisible();

    const readyOption = member1Page.locator(
      'option[value="99999999-9999-9999-9999-999999999801"]',
    );
    const submittedOption = member1Page.locator(
      'option[value="99999999-9999-9999-9999-999999999802"]',
    );

    await expect(readyOption).toContainText("Cloud Native Operations Deep Dive");
    await expect(submittedOption).toContainText("Platform Reliability Patterns");
    await expect(submittedOption).toHaveAttribute("disabled", "");
  });
});
