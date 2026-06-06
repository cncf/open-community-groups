import { expect } from "@open-wc/testing";

import {
  getLocationMapPreviewState,
} from "/static/js/common/location-map-preview-renderer.js";

describe("location map preview renderer", () => {
  it("builds map preview sync state", () => {
    // Map preview state keeps sync input shape outside the component class.
    expect(
      getLocationMapPreviewState({
        mapVisible: true,
        latitudeValue: "36.7213",
        longitudeValue: "-4.4214",
        mapZoom: 11,
        mapBoundingBox: [36.68, 36.75, -4.49, -4.35],
        shouldFitBounds: true,
      }),
    ).to.deep.equal({
      mapVisible: true,
      latitudeValue: "36.7213",
      longitudeValue: "-4.4214",
      mapZoom: 11,
      mapBoundingBox: [36.68, 36.75, -4.49, -4.35],
      shouldFitBounds: true,
    });
  });
});
