import { html } from "/static/vendor/js/lit-all.v3.2.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * BannerImage component for displaying banner images with loading skeleton.
 * Handles image loading states gracefully by showing skeleton placeholder.
 * Uses object-contain to display full image without cropping.
 * @extends LitWrapper
 */
export class BannerImage extends LitWrapper {
  /**
   * Component properties definition
   * @property {string} imageUrl - URL of the banner image to display
   * @property {string} alt - Alt text for the image
   * @property {boolean} _hasError - Internal state tracking if image failed to load
   * @property {boolean} _hasLoaded - Internal state tracking if image loaded successfully
   */
  static get properties() {
    return {
      imageUrl: { type: String, attribute: "image-url" },
      alt: { type: String },
      _hasError: { type: Boolean },
      _hasLoaded: { type: Boolean },
    };
  }

  constructor() {
    super();
    this.imageUrl = "";
    this.alt = "Banner";
    this._hasError = false;
    this._hasLoaded = false;
  }

  /**
   * Lifecycle callback when component is added to DOM.
   */
  connectedCallback() {
    super.connectedCallback();
  }

  /**
   * Lifecycle callback when properties change.
   * Resets loading states when image URL changes to attempt loading new image.
   * @param {Map} changedProperties - Map of changed property names to old values
   */
  updated(changedProperties) {
    if (changedProperties.has("imageUrl")) {
      // Reset states when image URL changes
      this._hasError = false;
      this._hasLoaded = false;
    }
  }

  /**
   * Handles successful image load event.
   * Updates internal state to show the image and hide skeleton.
   * @private
   */
  _handleImageLoad() {
    this._hasLoaded = true;
    this._hasError = false;
  }

  /**
   * Handles image load error event.
   * Updates internal state to hide the component.
   * @private
   */
  _handleImageError() {
    this._hasError = true;
    this._hasLoaded = false;
  }

  /**
   * Renders the banner component with image or skeleton.
   * Shows skeleton during loading, hides on error, or when no image URL provided.
   * @returns {TemplateResult} Lit HTML template
   */
  render() {
    // Hide entire component if no image URL or image has error
    if (!this.imageUrl || this._hasError) {
      return html``;
    }

    const showSkeleton = !this._hasLoaded;
    const showImage = this._hasLoaded;
    const skeletonVisibility = showSkeleton ? "opacity-100" : "opacity-0 pointer-events-none";
    const imageVisibility = showImage ? "opacity-100" : "opacity-0";

    return html`
      <div class="flex justify-center min-h-64 min-h-80">
        <div class="relative inline-block">
          <!-- Skeleton placeholder (visible during loading) -->
          <div
            class="flex absolute w-full h-full min-w-[300px] items-center justify-center skeleton-shimmer transition-opacity duration-300 ${skeletonVisibility}"
          >
            <div
              class="w-full h-full bg-stone-200 rounded-lg flex items-center justify-center border border-stone-200"
            >
              <div class="text-stone-400 text-center">
                <div class="text-sm font-medium">Loading banner...</div>
              </div>
            </div>
          </div>

          <!-- Banner image (always rendered if URL exists, visibility controlled by load state) -->
          <img
            src="${this.imageUrl}"
            alt="${this.alt}"
            @load="${this._handleImageLoad}"
            @error="${this._handleImageError}"
            class="${imageVisibility} transition-opacity duration-300 max-h-64 lg:max-h-80 w-auto h-auto p-[5px] bg-white border border-stone-200 rounded-lg"
            loading="lazy"
          />
        </div>
      </div>
    `;
  }
}

customElements.define("banner-image", BannerImage);
