import { html } from "lit";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { computeUserInitials } from "/static/js/common/users/initials.js";
import { parseJsonAttribute } from "/static/js/common/utils.js";
import { dispatchUserModalOpenEvent } from "/static/js/common/users/user-modal-event.js";
import "/static/js/common/media/logo-image.js";

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
    this._handleClick = this._handleClick.bind(this);
  }

  connectedCallback() {
    super.connectedCallback();

    // Parse user if it's a JSON string from template
    this.user = parseJsonAttribute(this.user, null);
  }

  _handleClick(event) {
    if (!this.displayModal) {
      return;
    }

    event.preventDefault();

    dispatchUserModalOpenEvent(this, this.user, { bioIsHtml: this.bioIsHtml });
  }

  render() {
    if (!this.user) {
      return html``;
    }

    const name = this.user.name || "";
    const username = this.user.username || "";
    const imageUrl = this.user.photo_url || "";
    const jobTitle = this.user.title || "";
    const displayName = name || username;
    const initials = computeUserInitials(name, username, 2);
    // The avatar's phone size sits here, because logo-image's size attribute is desktop-visible.
    const cardSize = this.featured ? "px-5 py-4 md:py-5" : "px-4 py-3 phone:[&>logo-image>div]:size-12";
    const borderState = this.featured ? "border-amber-200 bg-amber-50/50" : "border-stone-200 bg-white";
    // Only clickable cards react to a press.
    const pressState = this.featured ? "phone:active:border-amber-500" : "phone:active:border-primary-300";
    const avatarSize = this.featured ? "size-18 md:size-22" : "size-15 md:size-18";
    const nameSize = this.featured ? "text-lg md:text-xl" : "text-base";
    const jobSize = this.featured ? "text-sm md:text-base" : "text-[0.8rem]";

    if (this.small) {
      return this._renderWrapper(
        `inline-flex items-center gap-2 rounded-full ps-1 pe-2 py-1 phone:relative phone:after:absolute phone:after:inset-x-0 phone:after:-inset-y-1.5 ${
          this.featured
            ? "bg-amber-50/50 border border-amber-200 text-amber-800"
            : "bg-stone-100 border border-stone-200 text-stone-700"
        }`,
        `cursor-pointer ${this.featured ? "hover:border-amber-400" : "hover:border-primary-300"} hover:shadow-sm transition-all`,
        html`
          <logo-image
            aria-hidden="true"
            image-url=${imageUrl}
            placeholder=${initials}
            size="size-[24px]"
            font-size="text-[0.65rem]"
            hide-border="true"
          >
          </logo-image>
          ${this.featured ? html`<div class="svg-icon size-3 icon-star bg-amber-500"></div>` : ""}
          <span class="text-sm pe-1">${displayName}</span>
        `,
      );
    }

    return this._renderWrapper(
      `relative flex items-center gap-4 rounded-lg border ${cardSize} ${borderState} w-full phone:min-h-16 phone:gap-3 phone:px-3 phone:py-2.5`,
      `cursor-pointer ${this.featured ? "hover:border-amber-500" : "hover:border-primary-300"} ${pressState} hover:shadow-sm transition-all`,
      html`
        <logo-image
          aria-hidden="true"
          image-url=${imageUrl}
          size=${avatarSize}
          placeholder=${initials}
          font-size="text-lg"
        >
        </logo-image>
        <div class="leading-tight min-w-0">
          <div class="font-semibold text-stone-900 truncate ${nameSize}">${displayName}</div>
          ${
            jobTitle
              ? html`<div class="text-stone-600 mt-3 truncate phone:mt-0.5 ${jobSize}">${jobTitle}</div>`
              : ""
          }
        </div>
        ${
          this.displayModal
            ? html`<div
                class="svg-icon ms-auto size-4 shrink-0 bg-stone-400 icon-arrow-right not-phone:hidden"
                aria-hidden="true"
              ></div>`
            : ""
        }
      `,
    );
  }

  /**
   * Wraps chip content in a static container, or in a profile dialog trigger when the
   * modal is enabled. Lit cannot switch tag names, so each wrapper has its own template.
   * @param {string} baseClass Classes shared by both wrappers.
   * @param {string} clickableClass Classes added only to the trigger button.
   * @param {import("lit").TemplateResult} content Chip content.
   * @returns {import("lit").TemplateResult} Wrapped chip content.
   */
  _renderWrapper(baseClass, clickableClass, content) {
    if (!this.displayModal) {
      return html`<div class=${baseClass}>${content}</div>`;
    }

    return html`
      <button
        type="button"
        aria-haspopup="dialog"
        class="${baseClass} ${clickableClass} text-start"
        @click=${this._handleClick}
      >
        <span class="sr-only">View profile:</span>
        ${content}
      </button>
    `;
  }
}

customElements.define("user-chip", UserChip);
