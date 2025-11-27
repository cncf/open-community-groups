import { html, unsafeHTML } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { computeUserInitials, lockBodyScroll, unlockBodyScroll } from "/static/js/common/common.js";
import "/static/js/common/avatar-image.js";

/**
 * UserInfoModal displays detailed user information in a modal dialog.
 * Opens when user-chip components dispatch 'open-user-modal' events.
 *
 * Features:
 * - Shows user avatar, name, jobTitle, company, bio
 * - Displays social media links if available
 * - Keyboard navigation (Escape to close)
 * - Click outside to close
 * - ARIA attributes for accessibility
 */
export class UserInfoModal extends LitWrapper {
  static get properties() {
    return {
      _isOpen: { type: Boolean, state: true },
      _userData: { type: Object, state: true },
    };
  }

  constructor() {
    super();
    this._isOpen = false;
    this._userData = null;
  }

  connectedCallback() {
    super.connectedCallback();
    this._handleKeydown = this._handleKeydown.bind(this);
    this._handleOutsideClick = this._handleOutsideClick.bind(this);
    this._handleOpenModal = this._handleOpenModal.bind(this);

    document.addEventListener("open-user-modal", this._handleOpenModal);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this._removeEventListeners();
    if (this._isOpen) {
      unlockBodyScroll();
    }
    document.removeEventListener("open-user-modal", this._handleOpenModal);
  }

  _handleOpenModal(e) {
    this._userData = e.detail;
    this._isOpen = true;
    lockBodyScroll();
    document.addEventListener("keydown", this._handleKeydown);
    document.addEventListener("mousedown", this._handleOutsideClick);
  }

  _closeModal() {
    this._isOpen = false;
    unlockBodyScroll();
    this._removeEventListeners();
  }

  _removeEventListeners() {
    document.removeEventListener("keydown", this._handleKeydown);
    document.removeEventListener("mousedown", this._handleOutsideClick);
  }

  _handleKeydown(e) {
    if (this._isOpen && e.key === "Escape") {
      e.preventDefault();
      this._closeModal();
    }
  }

  _handleOutsideClick(e) {
    if (!this._isOpen) return;

    if (e.target.classList && e.target.classList.contains("modal-overlay")) {
      this._closeModal();
    }
  }

  _renderSocialLinks() {
    if (!this._userData) return "";

    const links = [];

    if (this._userData.websiteUrl) {
      links.push({
        url: this._userData.websiteUrl,
        icon: "website",
        label: "Website",
      });
    }
    if (this._userData.linkedinUrl) {
      links.push({
        url: this._userData.linkedinUrl,
        icon: "linkedin",
        label: "LinkedIn",
      });
    }
    if (this._userData.twitterUrl) {
      links.push({
        url: this._userData.twitterUrl,
        icon: "twitter",
        label: "Twitter",
      });
    }
    if (this._userData.facebookUrl) {
      links.push({
        url: this._userData.facebookUrl,
        icon: "facebook",
        label: "Facebook",
      });
    }

    if (links.length === 0) return "";

    return html`
      <div class="border-t border-stone-200 pt-6 mt-6">
        <div class="text-sm font-semibold text-stone-500 uppercase tracking-wide mb-4">Connect</div>
        <div class="flex flex-wrap gap-3">
          ${links.map(
            (link) => html`
              <a
                href=${link.url}
                target="_blank"
                rel="noopener noreferrer"
                class="group btn-secondary-anchor p-3 flex items-center justify-center"
                title=${link.label}
                aria-label=${link.label}
              >
                <div
                  class="svg-icon size-6 bg-primary-500 group-hover:bg-white transition-colors icon-${link.icon}"
                ></div>
              </a>
            `,
          )}
        </div>
      </div>
    `;
  }

  _renderTitleCompany() {
    if (!this._userData) return "";

    const parts = [];
    if (this._userData.jobTitle) parts.push(this._userData.jobTitle);
    if (this._userData.company) parts.push(this._userData.company);

    if (parts.length === 0) return "";

    return html` <div class="text-stone-600 text-base mt-2">${parts.join(" at ")}</div> `;
  }

  render() {
    if (!this._isOpen || !this._userData) {
      return html``;
    }

    const initials = computeUserInitials(this._userData.name, this._userData.username, 2);

    return html`
      <div
        class="fixed inset-0 z-1300 flex items-center justify-center overflow-y-auto overflow-x-hidden"
        role="dialog"
        aria-modal="true"
        aria-labelledby="user-info-modal-title"
      >
        <div
          class="modal-overlay absolute w-full h-full bg-stone-950 opacity-[0.35]"
          @click=${this._closeModal}
        ></div>

        <div class="relative p-4 w-full max-w-2xl max-h-full">
          <div class="relative bg-white rounded-lg shadow-lg">
            <div class="flex items-center justify-between p-6 border-b border-stone-200 rounded-t">
              <h3 id="user-info-modal-title" class="text-2xl font-semibold text-stone-900">
                User Information
              </h3>
              <button
                type="button"
                class="group text-stone-400 bg-transparent hover:bg-stone-200 hover:text-stone-900 transition-colors rounded-lg text-sm w-10 h-10 inline-flex justify-center items-center"
                @click=${this._closeModal}
                aria-label="Close modal"
              >
                <div
                  class="svg-icon w-6 h-6 bg-stone-500 group-hover:bg-stone-900 transition-colors icon-close"
                ></div>
              </button>
            </div>

            <div class="p-8">
              <div class="flex items-center gap-6 mb-6">
                <avatar-image
                  image-url=${this._userData.imageUrl || ""}
                  placeholder=${initials}
                  size="size-24"
                  font-size="text-3xl"
                ></avatar-image>
                <div class="flex-1 min-w-0">
                  <div class="font-semibold text-2xl text-stone-900">
                    ${this._userData.name || this._userData.username}
                  </div>
                  ${this._renderTitleCompany()}
                </div>
              </div>

              ${this._userData.bio
                ? html`
                    <div class="text-stone-700 text-base leading-relaxed">
                      ${this._userData.bioIsHtml
                        ? html`<div class="markdown">${unsafeHTML(this._userData.bio)}</div>`
                        : html`<div>${this._userData.bio}</div>`}
                    </div>
                  `
                : ""}
              ${this._renderSocialLinks()}
            </div>
          </div>
        </div>
      </div>
    `;
  }
}

customElements.define("user-info-modal", UserInfoModal);
