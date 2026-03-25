import { expect } from "@open-wc/testing";

import { hasSpeaker, normalizeSpeakers, speakerKey } from "/static/js/dashboard/event/speaker-utils.js";

describe("speaker-utils", () => {
  it("normalizes nested user data and featured flags", () => {
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

    expect(normalizeSpeakers("{")).to.deep.equal([]);
    expect(normalizeSpeakers({ username: "jamie" })).to.deep.equal([]);
  });

  it("builds comparable keys and checks membership", () => {
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

    expect(speakerKey({ user_id: 42 })).to.equal("42");
    expect(speakerKey({ username: "taylor" })).to.equal("taylor");
    expect(hasSpeaker(speakers, { user_id: 42 })).to.equal(true);
    expect(hasSpeaker(speakers, { username: "taylor" })).to.equal(true);
    expect(hasSpeaker(speakers, { username: "missing" })).to.equal(false);
  });
});
