import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";

/**
 * Builds map preview sync state from component fields.
 * @param {Object} state Component map state.
 * @returns {Object}
 */
export const getLocationMapPreviewState = (state) => ({
  mapVisible: state.mapVisible,
  latitudeValue: state.latitudeValue,
  longitudeValue: state.longitudeValue,
  mapZoom: state.mapZoom,
  mapBoundingBox: state.mapBoundingBox,
  shouldFitBounds: state.shouldFitBounds,
});

/**
 * Renders the enabled location map preview container.
 * @param {string} mapElementId Map element id.
 * @returns {import("lit").TemplateResult}
 */
export const renderLocationMapPreview = (mapElementId) => html`
  <div class="mt-6 max-w-5xl">
    <label class="form-label">Location Preview</label>
    <div class="mt-2 rounded-lg border border-stone-200 overflow-hidden h-48">
      <div id="${mapElementId}" class="w-full h-full"></div>
    </div>
  </div>
`;
