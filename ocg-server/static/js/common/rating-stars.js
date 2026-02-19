import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * RatingStars renders a 5-star row with fractional fill support.
 *
 * @property {number} averageRating Rating value from 0 to 5
 * @property {string} size Tailwind size class used by each star icon
 */
export class RatingStars extends LitWrapper {
  static properties = {
    averageRating: { type: Number, attribute: "average-rating" },
    size: { type: String, attribute: "size" },
  };

  constructor() {
    super();
    this.averageRating = 0;
    this.size = "size-4";
  }

  /**
   * Returns rating clamped to 0..5.
   * @returns {number}
   */
  _normalizedRating() {
    const rating = Number(this.averageRating || 0);
    if (!Number.isFinite(rating)) {
      return 0;
    }
    return Math.max(0, Math.min(5, rating));
  }

  /**
   * Renders a single star icon.
   * @param {string} colorClass
   * @returns {import("lit").TemplateResult}
   */
  _renderStar(colorClass) {
    return html`<div
      class="svg-icon ${this.size || "size-4"} icon-star ${colorClass} shrink-0"
      aria-hidden="true"
    ></div>`;
  }

  render() {
    const rating = this._normalizedRating();
    const overlayWidth = `${(rating / 5) * 100}%`;
    const ratingLabel = `${rating.toFixed(2)} out of 5 stars`;

    return html`
      <div
        class="relative inline-flex items-center align-middle leading-none"
        role="img"
        aria-label=${ratingLabel}
      >
        <div class="inline-flex items-center gap-1">
          ${[0, 1, 2, 3, 4].map(() => this._renderStar("bg-stone-300"))}
        </div>
        <div class="absolute inset-y-0 left-0 overflow-hidden" style="width:${overlayWidth};">
          <div class="inline-flex items-center gap-1">
            ${[0, 1, 2, 3, 4].map(() => this._renderStar("bg-amber-500"))}
          </div>
        </div>
      </div>
    `;
  }
}

if (!customElements.get("rating-stars")) {
  customElements.define("rating-stars", RatingStars);
}
