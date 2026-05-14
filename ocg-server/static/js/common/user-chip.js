import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { computeUserInitials } from "/static/js/common/common.js";
import "/static/js/common/logo-image.js";

/**
 * UserChip shows a user card with avatar, name, and title.
 * When `display-modal` is set, clicking opens a modal with full user information.
 *
 * Attributes/props:
 * - user: object (required) - User object with all user information
 * - bio-is-html: boolean (optional) - When true, bio is rendered as HTML
 * - display-modal: boolean (optional) - When true, clicking opens the user modal
 * - small: boolean (optional) - When true, renders a compact version
 */
export class UserChip extends LitWrapper {
  static get properties() {
    return {
      user: { type: Object },
      bioIsHtml: { type: Boolean, attribute: "bio-is-html" },
      displayModal: { type: Boolean, attribute: "display-modal" },
      small: { type: Boolean },
      featured: { type: Boolean },
    };
  }

  constructor() {
    super();
    this.user = null;
    this.bioIsHtml = false;
    this.displayModal = false;
    this.small = false;
    this.featured = false;
  }

  connectedCallback() {
    super.connectedCallback();

    // Parse user if it's a JSON string from template
    if (typeof this.user === "string") {
      try {
        this.user = JSON.parse(this.user);
      } catch (_) {
        this.user = null;
      }
    }
  }

  _handleClick = (e) => {
    if (!this.displayModal) {
      return;
    }

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
          blueskyUrl: this.user.bluesky_url,
          facebookUrl: this.user.facebook_url,
          githubUrl: this.user.github_url,
          linkedinUrl: this.user.linkedin_url,
          provider: this.user.provider,
          twitterUrl: this.user.twitter_url,
          websiteUrl: this.user.website_url,
        },
        bubbles: true,
        composed: true,
      }),
    );
  };

  _handleKeydown = (e) => {
    if (this.displayModal && (e.key === "Enter" || e.key === " ")) {
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
    const displayName = name || username;
    const isClickable = this.displayModal;
    const initials = computeUserInitials(name, username, 2);
    const cardSize = this.featured ? "px-5 py-4 md:py-5" : "px-4 py-3";
    const borderState = this.featured
      ? "border-amber-200 bg-amber-50/50 shadow-sm"
      : "border-stone-200 bg-white";
    const avatarSize = this.featured ? "size-18 md:size-22" : "size-15 md:size-18";
    const nameSize = this.featured ? "text-lg md:text-xl" : "text-base";
    const jobSize = this.featured ? "text-sm md:text-base" : "text-[0.8rem]";

    if (this.small) {
      return html`
        <div
          class="inline-flex items-center gap-2 rounded-full ps-1 pe-2 py-1 ${this.featured
            ? "bg-amber-50/50 border border-amber-200 text-amber-800"
            : "bg-stone-100 text-stone-700"} ${isClickable
            ? `cursor-pointer ${this.featured ? "hover:border-amber-400 hover:bg-amber-100/70" : "hover:bg-stone-200"} transition-colors`
            : ""}"
          @click=${isClickable ? this._handleClick : null}
          role=${isClickable ? "button" : ""}
          tabindex=${isClickable ? "0" : "-1"}
          @keydown=${isClickable ? this._handleKeydown : null}
          aria-label=${isClickable ? `View ${displayName}'s profile` : ""}
        >
          <logo-image
            image-url=${imageUrl}
            placeholder=${initials}
            size="size-[24px]"
            font-size="text-[0.65rem]"
            hide-border="true"
          >
          </logo-image>
          ${this.featured ? html`<div class="svg-icon size-3 icon-star bg-amber-500"></div>` : ""}
          <span class="text-sm pe-1">${displayName}</span>
        </div>
      `;
    }

    return html`
      <div
        class="relative flex items-center gap-4 rounded-lg border ${cardSize} ${borderState} w-full ${isClickable
          ? `cursor-pointer ${this.featured ? "hover:border-amber-500" : "hover:border-primary-300"} hover:shadow-sm transition-all`
          : ""}"
        @click=${isClickable ? this._handleClick : null}
        role=${isClickable ? "button" : ""}
        tabindex=${isClickable ? "0" : "-1"}
        @keydown=${isClickable ? this._handleKeydown : null}
        aria-label=${isClickable ? `View ${displayName}'s profile` : ""}
      >
        <logo-image image-url=${imageUrl} size=${avatarSize} placeholder=${initials} font-size="text-lg">
        </logo-image>
        <div class="leading-tight min-w-0">
          <div class="font-semibold text-stone-900 truncate ${nameSize}">${displayName}</div>
          ${jobTitle ? html`<div class="text-stone-600 mt-3 truncate ${jobSize}">${jobTitle}</div>` : ""}
        </div>
      </div>
    `;
  }
}

customElements.define("user-chip", UserChip);
