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
    this.classList.add("block", "h-full", "w-full");
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

    const imageVisibility = this._hasLoaded ? "opacity-100" : "opacity-0";

    return html`
      <div class="max-w-full h-full relative">
        <img
          src="${this.imageUrl}"
          alt="${this.alt}"
          @load="${this._handleImageLoad}"
          @error="${this._handleImageError}"
          class="w-auto max-w-full bg-white border-[5px] border-white outline outline-1 outline-stone-200 rounded-lg overflow-hidden h-full ${imageVisibility} transition-opacity duration-300"
          loading="lazy"
        />
      </div>
    `;
  }
}

customElements.define("banner-image", BannerImage);
