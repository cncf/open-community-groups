import { html } from "/static/vendor/js/lit-all.v3.2.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { computeUserInitials } from "/static/js/common/common.js";
import "/static/js/common/avatar-image.js";

/**
 * UserChip shows a small user card with avatar, name, title,
 * and an optional tooltip with a bio.
 *
 * Attributes/props:
 * - name: string (required)
 * - username: string (optional, used for initials)
 * - image-url: string (optional)
 * - title: string (optional)
 * - bio: string (optional)
 * - bio-is-html: boolean (optional). When true, bio is rendered as HTML.
 * - delay: number (optional). Show delay in ms (default: 300).
 * - tooltip-visible: boolean (optional). When true, tooltip is shown.
 */
export class UserChip extends LitWrapper {
  static get properties() {
    return {
      name: { type: String },
      username: { type: String },
      imageUrl: { type: String, attribute: "image-url" },
      title: { type: String },
      bio: { type: String },
      bioIsHtml: { type: Boolean, attribute: "bio-is-html" },
      tooltipVisible: { type: Boolean, attribute: "tooltip-visible" },
      delay: { type: Number },
      // When true, renders a compact badge-like chip
      small: { type: Boolean },
      _hasBio: { type: Boolean, state: true },
    };
  }

  constructor() {
    super();
    this.name = "";
    this.username = "";
    this.imageUrl = "";
    this.title = "";
    this.bio = "";
    this.bioIsHtml = false;
    this.tooltipVisible = false;
    this.delay = 300;
    this.small = false;
    this._hasBio = false;
    this._timer = null;
  }

  firstUpdated() {
    this._hasBio = typeof this.bio === "string" && this.bio.trim().length > 0;
  }

  _showTooltip = () => {
    this._timer = setTimeout(() => {
      this.tooltipVisible = true;
    }, this.delay);
  };

  _hideTooltip = () => {
    clearTimeout(this._timer);
    this._timer = setTimeout(() => {
      this.tooltipVisible = false;
    }, 120);
  };

  _onTooltipEnter = () => {
    clearTimeout(this._timer);
    this.tooltipVisible = true;
  };

  _onTooltipLeave = () => {
    this._hideTooltip();
  };

  _onKeydown = (e) => {
    if (e.key === "Escape" && this._hasBio) {
      e.preventDefault();
      this.tooltipVisible = false;
      clearTimeout(this._timer);
    }
  };

  _renderHeader(isTooltip = false, isSmall = false) {
    const initials = computeUserInitials(this.name, this.username, 2);
    if (isSmall) {
      return html`
        <avatar-image
          image-url="${this.imageUrl || ""}"
          placeholder="${initials}"
          size="size-[24px]"
          font-size="text-[0.65rem]"
          hide-border="true"
        >
        </avatar-image>
        <span class="text-sm text-stone-700 pe-2">${this.name || ""}</span>
      `;
    }
    return html`
      <avatar-image
        image-url="${this.imageUrl || ""}"
        size="size-18"
        placeholder="${initials}"
        font-size="text-lg"
      >
      </avatar-image>
      <div class="leading-tight min-w-0">
        <div class="font-semibold text-stone-900 ${!isTooltip ? "truncate" : ""}">${this.name || ""}</div>
        ${this.title
          ? html`<div class="text-xs text-stone-600 mt-0.5 ${!isTooltip ? "line-clamp-2" : ""}">
              ${this.title}
            </div>`
          : ""}
      </div>
    `;
  }

  render() {
    return html`
      <div
        class="relative ${this.small
          ? "inline-flex items-center gap-2 bg-stone-100 rounded-full ps-1 pe-1 py-1"
          : "flex items-center gap-3 rounded-lg border border-stone-200 bg-white px-4 py-3 w-full"}"
      >
        ${this._renderHeader(false, this.small)}
      </div>
    `;
  }
}

customElements.define("user-chip", UserChip);
