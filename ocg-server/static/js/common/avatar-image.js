import { html } from "/static/vendor/js/lit-all.v3.2.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * AvatarImage component for displaying user avatars with fallback to initials.
 * Handles image loading errors gracefully by showing initials placeholder.
 * Provides smooth transition between loading, loaded, and error states.
 * @extends LitWrapper
 */
export class AvatarImage extends LitWrapper {
  /**
   * Component properties definition
   * @property {string} imageUrl - URL of the avatar image to display
   * @property {string} placeholder - Text to show when image is not available (typically initials)
   * @property {number} size - Size of the avatar in pixels (default: 40)
   * @property {boolean} _hasError - Internal state tracking if image failed to load
   * @property {boolean} _hasLoaded - Internal state tracking if image loaded successfully
   */
  static get properties() {
    return {
      imageUrl: { type: String, attribute: "image-url" },
      placeholder: { type: String },
      size: { type: Number },
      _hasError: { type: Boolean },
      _hasLoaded: { type: Boolean },
    };
  }

  constructor() {
    super();
    this.imageUrl = "";
    this.placeholder = "-";
    this.size = 40; // Default size in pixels
    this._hasError = false;
    this._hasLoaded = false;
  }

  /**
   * Lifecycle callback when component is added to DOM.
   * Resets loading states to ensure fresh image load attempt.
   */
  connectedCallback() {
    super.connectedCallback();
    // Reset states when component is connected
    this._hasError = false;
    this._hasLoaded = false;
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
   * Updates internal state to show the image and hide placeholder.
   * @private
   */
  _handleImageLoad() {
    this._hasLoaded = true;
    this._hasError = false;
  }

  /**
   * Handles image load error event.
   * Updates internal state to show placeholder instead of broken image.
   * @private
   */
  _handleImageError() {
    this._hasError = true;
    this._hasLoaded = false;
  }

  /**
   * Renders the avatar component with image or placeholder.
   * Shows placeholder during loading, on error, or when no image URL provided.
   * @returns {TemplateResult} Lit HTML template
   */
  render() {
    const sizeClass = this.size === 40 ? "size-10" : `size-[${this.size}px]`;
    const showPlaceholder = !this.imageUrl || this._hasError || !this._hasLoaded;
    const showImage = this.imageUrl && !this._hasError && this._hasLoaded;

    return html`
      <div class="relative flex-shrink-0 ${sizeClass}">
        <!-- Initials placeholder (visible when no image, loading, or on error) -->
        <div
          class="${showPlaceholder
            ? "flex"
            : "hidden"} absolute inset-0 items-center justify-center rounded-full bg-stone-400 border-2 border-gray-400 text-white font-semibold text-sm"
        >
          ${this.placeholder}
        </div>

        <!-- Avatar image (always rendered if URL exists, visibility controlled by load/error state) -->
        ${this.imageUrl
          ? html`
              <img
                src="${this.imageUrl}"
                alt="Avatar"
                @load="${this._handleImageLoad}"
                @error="${this._handleImageError}"
                class="${showImage
                  ? ""
                  : "opacity-0 pointer-events-none"} absolute inset-0 w-full h-full object-cover rounded-full border-2 border-gray-400"
                loading="lazy"
              />
            `
          : ""}
      </div>
    `;
  }
}

customElements.define("avatar-image", AvatarImage);
