import { expect, test } from "../../fixtures.js";

import { queryE2eDatabase } from "../../database.js";
import { cleanupCredential, setupRevocableCredential } from "../../data-graphs/badges.js";
import { TEST_GROUP_IDS, TEST_USER_IDS } from "../../seed.js";
import { buildE2eUrl } from "../../utils.js";

const MEMBER_HOST_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada06";
const MEMBER_SPEAKER_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada03";
const MEMBER_TWO_MENTOR_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada07";
const MEMBER_TWO_REVOKED_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada04";
const MEMBER_TWO_VOLUNTEER_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada08";

const HOST_SNAPSHOT = {
  image_file_name: "7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png",
  issuer: {
    community_name: "Platform Engineering Community",
    group_name: "Platform Ops Meetup",
  },
  name: "Host",
};

const SPEAKER_SNAPSHOT = {
  image_file_name: "eba31486952cc567f080e2d52d0280c40e6c99da7dbad42c762d64b2f1ff9a32.png",
  issuer: {
    community_name: "Platform Engineering Community",
    group_name: "Platform Ops Meetup",
  },
  name: "Speaker",
};

test.describe("public user badge resources", () => {
  test("returns listed active profile badges with the public JSON projection", async ({ request }) => {
    // Request a seeded user with two listed active badges.
    const response = await request.get(buildE2eUrl("/users/e2e-member-1/badges"));
    const badges = await response.json();

    // Verify only the documented public fields cross the JSON boundary.
    expect(response.status()).toBe(200);
    expect(response.headers()["content-type"]).toContain("application/json");
    expect(badges).toEqual([
      {
        snapshot: SPEAKER_SNAPSHOT,
        user_badge_id: MEMBER_SPEAKER_CREDENTIAL_ID,
      },
      {
        snapshot: HOST_SNAPSHOT,
        user_badge_id: MEMBER_HOST_CREDENTIAL_ID,
      },
    ]);
  });

  test("omits seeded revoked and unlisted profile badges", async ({ request }) => {
    // Request a seeded user whose revoked badge is also hidden from the profile.
    const response = await request.get(buildE2eUrl("/users/e2e-member-2/badges"));
    const badges = await response.json();

    // Verify revoked or unlisted credentials are not present in the public list.
    expect(response.status()).toBe(200);
    expect(response.headers()["content-type"]).toContain("application/json");
    expect(badges).toEqual([
      {
        snapshot: {
          image_file_name: "e2e-disposable-badge.png",
          issuer: {
            community_name: "Platform Engineering Community",
            group_name: "Platform Ops Meetup",
          },
          name: "Mentor",
        },
        user_badge_id: MEMBER_TWO_MENTOR_CREDENTIAL_ID,
      },
      {
        snapshot: {
          image_file_name: "e2e-disposable-badge.png",
          issuer: {
            community_name: "Platform Engineering Community",
            group_name: "Platform Ops Meetup",
          },
          name: "Volunteer",
        },
        user_badge_id: MEMBER_TWO_VOLUNTEER_CREDENTIAL_ID,
      },
    ]);
    expect(badges).not.toEqual(
      expect.arrayContaining([expect.objectContaining({ user_badge_id: MEMBER_TWO_REVOKED_CREDENTIAL_ID })]),
    );
  });

  test("omits active unlisted disposable profile badges", async ({ request }) => {
    // Create an owned credential and hide it from the public profile.
    const credential = setupRevocableCredential({
      groupId: TEST_GROUP_IDS.community1.alpha,
      userId: TEST_USER_IDS.member1,
    });

    try {
      // Hide the owned credential from the public profile.
      queryE2eDatabase(`
        update user_badge
        set is_listed = false
        where user_badge_id = '${credential.userBadgeId}'::uuid;
      `);

      // Verify the active but unlisted credential is absent.
      const response = await request.get(buildE2eUrl("/users/e2e-member-1/badges"));
      const badges = await response.json();

      // Verify the unlisted credential is omitted from the public JSON.
      expect(response.status()).toBe(200);
      expect(response.headers()["content-type"]).toContain("application/json");
      expect(badges).not.toEqual(
        expect.arrayContaining([expect.objectContaining({ user_badge_id: credential.userBadgeId })]),
      );
    } finally {
      // Remove the owned credential fixture.
      cleanupCredential(credential);
    }
  });

  test("returns an empty JSON list for an unknown username", async ({ request }) => {
    // Request a username that does not exist in the seeded catalog.
    const response = await request.get(buildE2eUrl("/users/e2e-unknown-profile/badges"));
    const badges = await response.json();

    // Verify unknown users use the empty-list contract.
    expect(response.status()).toBe(200);
    expect(response.headers()["content-type"]).toContain("application/json");
    expect(badges).toEqual([]);
  });
});
