import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * BannerImage component for displaying banner images with loading skeleton.
 * Handles image loading states gracefully by showing skeleton placeholder.
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

    const spinnerVisibility = !this._hasLoaded ? "opacity-100" : "opacity-0 pointer-events-none";
    const imageVisibility = this._hasLoaded ? "opacity-100" : "opacity-0";

    return html`
      <div class="max-w-full h-full relative">
        <div class="absolute inset-0 flex items-center ${spinnerVisibility} transition-opacity duration-300">
          <div role="status" class="flex size-8">
            <style>
              .spinner-accent {
                fill: var(--color-primary-300);
              }
            </style>
            <svg aria-hidden="true" viewBox="0 0 100 101" class="animate-spin size-auto">
              <path
                d="M100 50.5908C100 78.2051 77.6142 100.591 50 100.591C22.3858 100.591 0 78.2051 0 50.5908C0 22.9766 22.3858 0.59082 50 0.59082C77.6142 0.59082 100 22.9766 100 50.5908ZM9.08144 50.5908C9.08144 73.1895 27.4013 91.5094 50 91.5094C72.5987 91.5094 90.9186 73.1895 90.9186 50.5908C90.9186 27.9921 72.5987 9.67226 50 9.67226C27.4013 9.67226 9.08144 27.9921 9.08144 50.5908Z"
                fill="#e5e7eb"
              />
              <path
                d="M93.9676 39.0409C96.393 38.4038 97.8624 35.9116 97.0079 33.5539C95.2932 28.8227 92.871 24.3692 89.8167 20.348C85.8452 15.1192 80.8826 10.7238 75.2124 7.41289C69.5422 4.10194 63.2754 1.94025 56.7698 1.05124C51.7666 0.367541 46.6976 0.446843 41.7345 1.27873C39.2613 1.69328 37.813 4.19778 38.4501 6.62326C39.0873 9.04874 41.5694 10.4717 44.0505 10.1071C47.8511 9.54855 51.7191 9.52689 55.5402 10.0491C60.8642 10.7766 65.9928 12.5457 70.6331 15.2552C75.2735 17.9648 79.3347 21.5619 82.5849 25.841C84.9175 28.9121 86.7997 32.2913 88.1811 35.8758C89.083 38.2158 91.5421 39.6781 93.9676 39.0409Z"
                fill="#D62293"
                class="spinner-accent"
              />
            </svg>
            <span class="sr-only">Loading...</span>
          </div>
        </div>
        <img
          src="${this.imageUrl}"
          alt="${this.alt}"
          @load="${this._handleImageLoad}"
          @error="${this._handleImageError}"
          class="w-auto max-w-full object-contain bg-white border-[5px] border-white outline outline-1 outline-stone-200 rounded-lg overflow-hidden h-full ${imageVisibility} transition-opacity duration-300"
          loading="lazy"
        />
      </div>
    `;
  }
}

customElements.define("banner-image", BannerImage);
