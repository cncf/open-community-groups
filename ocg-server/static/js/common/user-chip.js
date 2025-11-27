import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { computeUserInitials } from "/static/js/common/common.js";
import "/static/js/common/avatar-image.js";

/**
 * UserChip shows a small user card with avatar, name, and title.
 * When clicked, it opens a modal with full user information.
 *
 * Attributes/props:
 * - user: object (required) - User object with all user information
 * - bio-is-html: boolean (optional) - When true, bio is rendered as HTML
 * - small: boolean (optional) - When true, renders a compact version
 */
export class UserChip extends LitWrapper {
  static get properties() {
    return {
      user: { type: Object },
      bioIsHtml: { type: Boolean, attribute: "bio-is-html" },
      small: { type: Boolean },
    };
  }

  constructor() {
    super();
    this.user = null;
    this.bioIsHtml = false;
    this.small = false;
  }

  _handleClick = (e) => {
    const bio = this.user?.bio || "";
    const hasBio = bio.trim().length > 0;

    if (hasBio && !this.small) {
      e.preventDefault();

      this.dispatchEvent(
        new CustomEvent("open-user-modal", {
          detail: {
            name: this.user.name,
            username: this.user.username,
            imageUrl: this.user.photo_url,
            jobTitle: this.user.title,
            company: this.user.company,
            bio: this.user.bio,
            bioIsHtml: this.bioIsHtml,
            facebookUrl: this.user.facebook_url,
            linkedinUrl: this.user.linkedin_url,
            twitterUrl: this.user.twitter_url,
            websiteUrl: this.user.website_url,
          },
          bubbles: true,
          composed: true,
        }),
      );
    }
  };

  _handleKeydown = (e) => {
    const bio = this.user?.bio || "";
    const hasBio = bio.trim().length > 0;

    if (hasBio && !this.small && (e.key === "Enter" || e.key === " ")) {
      e.preventDefault();
      this._handleClick(e);
    }
  };

  render() {
    if (!this.user) {
      return html``;
    }

    const name = this.user.name || "";
    const username = this.user.username || "";
    const imageUrl = this.user.photo_url || "";
    const jobTitle = this.user.title || "";
    const bio = this.user.bio || "";
    const hasBio = bio.trim().length > 0;
    const isClickable = hasBio && !this.small;
    const initials = computeUserInitials(name, username, 2);

    if (this.small) {
      return html`
        <div class="inline-flex items-center gap-2 bg-stone-100 rounded-full ps-1 pe-1 py-1">
          <avatar-image
            image-url="${imageUrl}"
            placeholder="${initials}"
            size="size-[24px]"
            font-size="text-[0.65rem]"
            hide-border="true"
          >
          </avatar-image>
          <span class="text-sm text-stone-700 pe-2">${name}</span>
        </div>
      `;
    }

    return html`
      <div
        class="relative flex items-center gap-3 rounded-lg border border-stone-200 bg-white px-4 py-3 w-full ${isClickable
          ? "cursor-pointer hover:border-primary-300 hover:shadow-sm transition-all"
          : ""}"
        @click="${isClickable ? this._handleClick : null}"
        role="${isClickable ? "button" : ""}"
        tabindex="${isClickable ? "0" : "-1"}"
        @keydown="${isClickable ? this._handleKeydown : null}"
        aria-label="${isClickable ? `View ${name || username}'s profile` : ""}"
      >
        <avatar-image
          image-url="${imageUrl}"
          size="size-15 md:size-18"
          placeholder="${initials}"
          font-size="text-lg"
        >
        </avatar-image>
        <div class="leading-tight min-w-0">
          <div class="font-semibold text-stone-900 truncate">${name}</div>
          ${jobTitle
            ? html`<div class="text-[0.8rem] text-stone-600 mt-1.5 line-clamp-2">${jobTitle}</div>`
            : ""}
        </div>
      </div>
    `;
  }
}

customElements.define("user-chip", UserChip);
