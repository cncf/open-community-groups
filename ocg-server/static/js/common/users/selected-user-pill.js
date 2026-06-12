import { html, nothing } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { computeUserInitials } from "/static/js/common/common.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { parseJsonAttribute } from "/static/js/common/utils.js";
import "/static/js/common/media/logo-image.js";

/**
 * SelectedUserPill renders compact removable user selections inside forms.
 * @extends LitWrapper
 */
export class SelectedUserPill extends LitWrapper {
  /**
   * Component properties definition.
   * @property {Object} user - User-like object with name, username, and photo_url.
   * @property {boolean} featured - Whether to show the featured speaker marker.
   * @property {boolean} disabled - Whether the remove action is unavailable.
   * @property {string} removeLabel - Accessible label for the remove action.
   * @property {string} variant - Visual variant for selector-specific spacing.
   */
  static properties = {
    user: { type: Object },
    featured: { type: Boolean },
    disabled: { type: Boolean },
    removeLabel: { type: String, attribute: "remove-label" },
    variant: { type: String },
  };

  constructor() {
    super();
    this.user = null;
    this.featured = false;
    this.disabled = false;
    this.removeLabel = "Remove user";
    this.variant = "user";
  }

  connectedCallback() {
    super.connectedCallback();
    this.user = parseJsonAttribute(this.user, null);
  }

  /**
   * Emits a remove request for the owning selector.
   * @private
   */
  _handleRemove() {
    if (this.disabled) {
      return;
    }
    this.dispatchEvent(new CustomEvent("remove"));
  }

  render() {
    if (!this.user) {
      return html``;
    }

    const displayName = this.user.name || this.user.username || "";
    const initials = computeUserInitials(this.user.name, this.user.username, 2);
    const isSpeakerVariant = this.variant === "speaker";
    const containerEndPaddingClass = isSpeakerVariant ? "pe-2" : "pe-1";
    const avatarFontSize = isSpeakerVariant ? nothing : "text-xs";
    const nameEndPaddingClass = isSpeakerVariant ? "" : "pe-1";

    return html`
      <div
        class="inline-flex items-center gap-2 bg-stone-100 rounded-full ps-1 ${containerEndPaddingClass} py-1"
      >
        <logo-image
          image-url=${this.user.photo_url || ""}
          placeholder=${initials}
          size="size-[24px]"
          font-size=${avatarFontSize}
          hide-border="true"
        >
        </logo-image>
        ${this.featured ? html`<div class="svg-icon size-3 icon-star bg-amber-500"></div>` : ""}
        <span class="text-sm text-stone-700 ${nameEndPaddingClass}">${displayName}</span>
        <button
          type="button"
          class="p-1 hover:bg-stone-200 rounded-full transition-colors"
          title=${this.removeLabel}
          aria-label=${this.removeLabel}
          @click=${this._handleRemove}
          ?disabled=${this.disabled}
        >
          <div class="svg-icon size-3 icon-close bg-stone-600"></div>
        </button>
      </div>
    `;
  }
}

customElements.define("selected-user-pill", SelectedUserPill);
