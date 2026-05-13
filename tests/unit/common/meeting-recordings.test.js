import { expect } from "@open-wc/testing";

import {
  getMeetingRecordingVisibilityText,
  MEETING_RECORDING_URL_LEGEND,
} from "/static/js/common/meeting-recordings.js";

describe("meeting-recordings", () => {
  it("returns the shared final recording URL legend", () => {
    expect(MEETING_RECORDING_URL_LEGEND).to.equal(
      "Optional processed recording that takes priority over the original provider recording.",
    );
  });

  it("hides unpublished recordings", () => {
    expect(
      getMeetingRecordingVisibilityText({
        published: false,
        finalUrl: "https://video.example.com/final",
        rawUrl: "https://zoom.us/rec/share/raw",
      }),
    ).to.equal("Public visitors will not see a recording link.");
  });

  it("prefers the final recording URL when published", () => {
    expect(
      getMeetingRecordingVisibilityText({
        published: true,
        finalUrl: " https://video.example.com/final ",
        rawUrl: "https://zoom.us/rec/share/raw",
      }),
    ).to.equal("Public visitors will see the final public recording URL.");
  });

  it("falls back to the raw provider recording when published", () => {
    expect(
      getMeetingRecordingVisibilityText({
        published: true,
        rawUrl: "https://zoom.us/rec/share/raw",
      }),
    ).to.equal("Public visitors will see the original provider recording.");
  });

  it("explains that no link is available when published without URLs", () => {
    expect(
      getMeetingRecordingVisibilityText({
        published: true,
        finalUrl: " ",
        rawUrl: "",
      }),
    ).to.equal("Public visitors will not see a recording link until a recording URL is available.");
  });
});
