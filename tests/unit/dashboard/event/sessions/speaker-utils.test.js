import { expect } from "@open-wc/testing";

import {
  hasSpeaker,
  normalizeSpeakers,
  speakerKey,
} from "/static/js/dashboard/event/sessions/speaker-utils.js";

describe("speaker-utils", () => {
  it("normalizes nested user data and featured flags", () => {
    // Prepare speakers for normalizing nested user data and featured flags.
    const speakers = normalizeSpeakers([
      {
        featured: 1,
        user: {
          name: "Casey",
          user_id: 12,
          username: "casey",
        },
      },
      {
        username: "alex",
      },
      null,
    ]);

    // Verify normalizes nested user data and featured flags.
    expect(speakers).to.deep.equal([
      {
        featured: true,
        name: "Casey",
        user_id: 12,
        username: "casey",
      },
      {
        featured: false,
        username: "alex",
      },
    ]);
  });

  it("accepts json strings and ignores invalid values", () => {
    // JSON strings are normalized into speaker records.
    expect(
      normalizeSpeakers(
        JSON.stringify([
          {
            username: "jamie",
          },
        ]),
      ),
    ).to.deep.equal([
      {
        featured: false,
        username: "jamie",
      },
    ]);

    // Invalid speaker values fall back to an empty list.
    expect(normalizeSpeakers("{")).to.deep.equal([]);
    expect(normalizeSpeakers({ username: "jamie" })).to.deep.equal([]);
  });

  it("builds comparable keys and checks membership", () => {
    // Prepare speakers with user ids and username-only profiles.
    const speakers = normalizeSpeakers([
      {
        user: {
          user_id: 42,
          username: "sam",
        },
      },
      {
        username: "taylor",
      },
    ]);

    // Assert comparable keys and membership checks use the normalized speakers.
    expect(speakerKey({ user_id: 42 })).to.equal("42");
    expect(speakerKey({ username: "taylor" })).to.equal("taylor");
    expect(hasSpeaker(speakers, { user_id: 42 })).to.equal(true);
    expect(hasSpeaker(speakers, { username: "taylor" })).to.equal(true);
    expect(hasSpeaker(speakers, { username: "missing" })).to.equal(false);
  });
});
