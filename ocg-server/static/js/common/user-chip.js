import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { computeUserInitials } from "/static/js/common/common.js";
import "/static/js/common/avatar-image.js";

/**
 * UserChip shows a small user card with avatar, name, and title.
 * When clicked, it opens a modal with full user information.
 *
 * Attributes/props:
 * - name: string (required)
 * - username: string (optional, used for initials)
 * - image-url: string (optional)
 * - job-title: string (optional)
 * - bio: string (optional)
 * - bio-is-html: boolean (optional). When true, bio is rendered as HTML.
 * - small: boolean (optional). When true, renders a compact version.
 * - company: string (optional)
 * - facebook-url: string (optional)
 * - linkedin-url: string (optional)
 * - twitter-url: string (optional)
 * - website-url: string (optional)
 */
export class UserChip extends LitWrapper {
  static get properties() {
    return {
      name: { type: String },
      username: { type: String },
      imageUrl: { type: String, attribute: "image-url" },
      jobTitle: { type: String, attribute: "job-title" },
      bio: { type: String },
      bioIsHtml: { type: Boolean, attribute: "bio-is-html" },
      small: { type: Boolean },
      company: { type: String },
      facebookUrl: { type: String, attribute: "facebook-url" },
      linkedinUrl: { type: String, attribute: "linkedin-url" },
      twitterUrl: { type: String, attribute: "twitter-url" },
      websiteUrl: { type: String, attribute: "website-url" },
      _hasBio: { type: Boolean, state: true },
    };
  }

  constructor() {
    super();
    this.name = "";
    this.username = "";
    this.imageUrl = "";
    this.jobTitle = "";
    this.bio = "";
    this.bioIsHtml = false;
    this.small = false;
    this.company = "";
    this.facebookUrl = "";
    this.linkedinUrl = "";
    this.twitterUrl = "";
    this.websiteUrl = "";
    this._hasBio = false;
  }

  firstUpdated() {
    this._hasBio = typeof this.bio === "string" && this.bio.trim().length > 0;
  }

  _handleClick = (e) => {
    if (this._hasBio && !this.small) {
      e.preventDefault();

      this.dispatchEvent(
        new CustomEvent("open-user-modal", {
          detail: {
            name: this.name,
            username: this.username,
            imageUrl: this.imageUrl,
            jobTitle: this.jobTitle,
            company: this.company,
            bio: this.bio,
            bioIsHtml: this.bioIsHtml,
            facebookUrl: this.facebookUrl,
            linkedinUrl: this.linkedinUrl,
            twitterUrl: this.twitterUrl,
            websiteUrl: this.websiteUrl,
          },
          bubbles: true,
          composed: true,
        }),
      );
    }
  };

  _handleKeydown = (e) => {
    if (this._hasBio && !this.small && (e.key === "Enter" || e.key === " ")) {
      e.preventDefault();
      this._handleClick(e);
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
        size="size-15 md:size-18"
        placeholder="${initials}"
        font-size="text-lg"
      >
      </avatar-image>
      <div class="leading-tight min-w-0">
        <div class="font-semibold text-stone-900 ${!isTooltip ? "truncate" : ""}">${this.name || ""}</div>
        ${this.jobTitle
          ? html`<div class="text-[0.8rem] text-stone-600 mt-1.5 ${!isTooltip ? "line-clamp-2" : ""}">
              ${this.jobTitle}
            </div>`
          : ""}
      </div>
    `;
  }

  render() {
    const isClickable = this._hasBio && !this.small;

    return html`
      <div
        class="relative ${this.small
          ? "inline-flex items-center gap-2 bg-stone-100 rounded-full ps-1 pe-1 py-1"
          : "flex items-center gap-3 rounded-lg border border-stone-200 bg-white px-4 py-3 w-full"} ${isClickable
          ? "cursor-pointer hover:border-primary-300 hover:shadow-sm transition-all"
          : ""}"
        @click="${isClickable ? this._handleClick : null}"
        role="${isClickable ? "button" : ""}"
        tabindex="${isClickable ? "0" : "-1"}"
        @keydown="${isClickable ? this._handleKeydown : null}"
        aria-label="${isClickable ? `View ${this.name || this.username}'s profile` : ""}"
      >
        ${this._renderHeader(false, this.small)}
      </div>
    `;
  }
}

customElements.define("user-chip", UserChip);
