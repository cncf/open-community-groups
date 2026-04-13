import { html, unsafeHTML } from "/static/vendor/js/lit-all.v3.3.2.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { computeUserInitials, lockBodyScroll, unlockBodyScroll } from "/static/js/common/common.js";
import "/static/js/common/logo-image.js";

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

  _getSocialLinks() {
    if (!this._userData) return [];

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
    if (this._userData.blueskyUrl) {
      links.push({
        url: this._userData.blueskyUrl,
        icon: "bluesky",
        label: "Bluesky",
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

    return links;
  }

  _hasProfileDetails(bio, socialLinks) {
    return Boolean(bio) || socialLinks.length > 0;
  }

  _renderSocialLinks(links) {
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

    return html` <div class="mt-1 text-sm text-stone-600 sm:mt-2 sm:text-base">${parts.join(" at ")}</div> `;
  }

  _renderLinuxFoundationLink() {
    const linuxFoundationUsername = this._userData?.provider?.linuxfoundation?.username?.trim();

    if (!linuxFoundationUsername) {
      return "";
    }

    const openProfileUrl = `https://openprofile.dev/profile/${encodeURIComponent(linuxFoundationUsername)}`;

    return html`
      <a
        href=${openProfileUrl}
        target="_blank"
        rel="noopener noreferrer"
        class="group btn-primary-outline-anchor inline-flex max-w-full items-center justify-center gap-2 h-10 md:h-[30px]"
      >
        <span>openprofile.dev</span>
        <div class="svg-icon size-3 icon-external-link"></div>
      </a>
    `;
  }

  _renderProfilePlaceholder(bio, socialLinks) {
    if (this._hasProfileDetails(bio, socialLinks)) {
      return "";
    }

    return html`
      <div
        class="border-2 border-dashed border-stone-300 rounded-lg bg-stone-50 px-4 py-6 text-center sm:px-6 sm:py-8"
      >
        <div class="text-base text-stone-600 mb-3 sm:text-lg">Profile not completed</div>
        <p class="text-sm text-stone-600">This user hasn’t finished setting up their profile yet.</p>
      </div>
    `;
  }

  render() {
    if (!this._isOpen || !this._userData) {
      return html``;
    }

    const bio = this._userData.bio?.trim() || "";
    const initials = computeUserInitials(this._userData.name, this._userData.username, 2);
    const socialLinks = this._getSocialLinks();

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

        <div class="modal-panel p-4 max-w-2xl">
          <div class="modal-card rounded-lg">
            <div
              class="flex items-center justify-between gap-3 border-b border-stone-200 rounded-t p-5 sm:gap-4 sm:p-6"
            >
              <h3
                id="user-info-modal-title"
                class="min-w-0 flex-1 text-lg font-semibold leading-tight text-stone-900 sm:text-2xl"
              >
                <span class="sm:hidden">User</span>
                <span class="hidden sm:inline">User Information</span>
              </h3>
              <div class="flex shrink-0 items-center gap-3 sm:gap-5 sm:pe-2">
                ${this._renderLinuxFoundationLink()}
                <button
                  type="button"
                  class="group shrink-0 text-stone-400 bg-transparent hover:bg-stone-200 hover:text-stone-900 transition-colors rounded-lg text-sm w-10 h-10 inline-flex justify-center items-center"
                  @click=${this._closeModal}
                  aria-label="Close modal"
                >
                  <div
                    class="svg-icon w-6 h-6 bg-stone-500 group-hover:bg-stone-900 transition-colors icon-close"
                  ></div>
                </button>
              </div>
            </div>

            <div class="modal-body p-6 sm:p-8">
              <div class="mb-6 flex items-center gap-4 text-left sm:gap-6">
                <logo-image
                  image-url=${this._userData.imageUrl || ""}
                  placeholder=${initials}
                  size="size-16 sm:size-24"
                  font-size="text-xl sm:text-3xl"
                ></logo-image>
                <div class="flex-1 min-w-0">
                  <div class="font-semibold text-lg leading-tight text-stone-900 sm:text-2xl">
                    ${this._userData.name || this._userData.username}
                  </div>
                  ${this._renderTitleCompany()}
                </div>
              </div>

              ${bio
                ? html`
                    <div class="text-stone-700 text-base leading-relaxed">
                      ${this._userData.bioIsHtml
                        ? html`<div class="markdown">${unsafeHTML(bio)}</div>`
                        : html`<div>${bio}</div>`}
                    </div>
                  `
                : ""}
              ${this._renderProfilePlaceholder(bio, socialLinks)} ${this._renderSocialLinks(socialLinks)}
            </div>
          </div>
        </div>
      </div>
    `;
  }
}

customElements.define("user-info-modal", UserInfoModal);
