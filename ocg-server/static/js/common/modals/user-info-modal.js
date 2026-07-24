import { html } from "/static/vendor/js/lit-all.v3.3.3.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { computeUserInitials } from "/static/js/common/users/initials.js";
import {
  bindModalDismissListeners,
  closeModalBodyScroll,
  isModalOverlayTarget,
  openModalBodyScroll,
} from "/static/js/common/modals/modal-lifecycle.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { renderTrustedHtml } from "/static/js/common/trusted-lit-html.js";
import "/static/js/common/media/logo-image.js";

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
      _badges: { type: Array, state: true },
      _badgesState: { type: String, state: true },
      _userData: { type: Object, state: true },
    };
  }

  constructor() {
    super();
    this._isOpen = false;
    this._badges = [];
    this._badgesState = "idle";
    this._userData = null;
    this._badgesAbortController = null;
    this._badgesRequestId = 0;
    this._removeDismissListeners = null;
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
    this._badgesRequestId += 1;
    this._badgesAbortController?.abort();
    this._isOpen = closeModalBodyScroll(this._isOpen);
    document.removeEventListener("open-user-modal", this._handleOpenModal);
  }

  _handleOpenModal(event) {
    this._badgesAbortController?.abort();
    this._userData = event.detail;
    this._badges = [];
    this._badgesState = "loading";
    this._isOpen = openModalBodyScroll(this._isOpen);
    this._removeEventListeners();
    this._removeDismissListeners = bindModalDismissListeners({
      onKeydown: this._handleKeydown,
      onOutsideClick: this._handleOutsideClick,
    });
    this._loadBadges();
  }

  _closeModal() {
    this._badgesRequestId += 1;
    this._badgesAbortController?.abort();
    this._isOpen = closeModalBodyScroll(this._isOpen);
    this._removeEventListeners();
  }

  _communityName() {
    const dashboardCommunity = document.querySelector("[data-community-name]")?.dataset?.communityName;
    if (dashboardCommunity) {
      return dashboardCommunity;
    }

    const firstPathSegment = window.location.pathname.split("/").filter(Boolean)[0] || "";
    return [
      "__web-test-runner__",
      "badges",
      "dashboard",
      "docs",
      "explore",
      "images",
      "log-in",
      "tests",
    ].includes(firstPathSegment)
      ? ""
      : firstPathSegment;
  }

  async _loadBadges() {
    const requestId = ++this._badgesRequestId;
    const community = this._communityName();
    const username = this._userData?.username;
    if (!community || !username) {
      this._badgesState = "empty";
      return;
    }

    this._badgesAbortController = new AbortController();
    try {
      const response = await fetch(
        `/communities/${encodeURIComponent(community)}/users/${encodeURIComponent(username)}/badges`,
        { signal: this._badgesAbortController.signal },
      );
      if (!response.ok) {
        throw new Error("Badge profile request failed");
      }
      const badges = await response.json();
      if (requestId !== this._badgesRequestId) {
        return;
      }
      this._badges = Array.isArray(badges) ? badges : [];
      this._badgesState = this._badges.length ? "ready" : "empty";
    } catch (error) {
      if (error.name !== "AbortError" && requestId === this._badgesRequestId) {
        this._badges = [];
        this._badgesState = "error";
      }
    }
  }

  _removeEventListeners() {
    this._removeDismissListeners?.();
    this._removeDismissListeners = null;
  }

  _handleKeydown(event) {
    if (this._isOpen && isEscapeEvent(event)) {
      event.preventDefault();
      this._closeModal();
    }
  }

  _handleOutsideClick(event) {
    if (!this._isOpen) return;

    if (isModalOverlayTarget(event.target)) {
      this._closeModal();
    }
  }

  /**
   * Builds the ordered social links supported by the user info modal.
   * @returns {Array<{url: string, icon: string, label: string}>} Social links
   * @private
   */
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
    if (this._userData.githubUrl) {
      links.push({
        url: this._userData.githubUrl,
        icon: "github",
        label: "GitHub",
      });
    }

    return links;
  }

  _hasProfileDetails(bio, socialLinks) {
    return Boolean(bio) || socialLinks.length > 0;
  }

  /**
   * Renders profile social links as icon buttons.
   * @param {Array<{url: string, icon: string, label: string}>} links - Links to render
   * @returns {TemplateResult|string} Social links template or empty string
   * @private
   */
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

  _renderBadges() {
    if (this._badgesState === "loading") {
      return html`<p class="sr-only" role="status">Loading profile badges</p>`;
    }
    if (this._badgesState === "error") {
      return html`<p class="mt-6 text-sm text-red-700" role="status">
        Profile badges are temporarily unavailable.
      </p>`;
    }
    if (this._badgesState !== "ready") {
      return "";
    }

    return html`
      <section class="mt-6 border-t border-stone-200 pt-6" aria-labelledby="profile-badges-title">
        <h4
          id="profile-badges-title"
          class="mb-4 text-sm font-semibold uppercase tracking-wide text-stone-500"
        >
          Badges
        </h4>
        <ul class="grid gap-3 sm:grid-cols-2">
          ${this._badges.map(
            (badge) => html`
              <li>
                <a
                  class="group grid grid-cols-[3rem_1fr] gap-3 rounded-lg border border-stone-200 p-3 transition-colors hover:border-primary-400 hover:bg-primary-50 focus-visible:border-primary-500 focus-visible:outline-2 focus-visible:outline-primary-500"
                  href=${`/badges/credentials/${badge.user_badge_id}`}
                  aria-label=${`View ${badge.snapshot.name} badge credential`}
                >
                  <img
                    class="size-12 rounded-md object-cover"
                    src=${`/images/badges/${badge.snapshot.image_file_name}`}
                    alt=${`${badge.snapshot.name} badge artwork`}
                    width="48"
                    height="48"
                  />
                  <span class="min-w-0">
                    <span class="block truncate text-sm font-semibold text-stone-900"
                      >${badge.snapshot.name}</span
                    >
                    <span class="mt-1 block text-xs text-stone-600">${badge.snapshot.issuer.group_name}</span>
                  </span>
                </a>
              </li>
            `,
          )}
        </ul>
      </section>
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

              ${
                bio
                  ? html`
                      <div class="text-stone-700 text-base leading-relaxed">
                        ${
                          this._userData.bioIsHtml
                            ? html`<div class="markdown">${renderTrustedHtml(bio)}</div>`
                            : html`<div>${bio}</div>`
                        }
                      </div>
                    `
                  : ""
              }
              ${this._renderProfilePlaceholder(bio, socialLinks)} ${this._renderSocialLinks(socialLinks)}
              ${this._renderBadges()}
            </div>
          </div>
        </div>
      </div>
    `;
  }
}

customElements.define("user-info-modal", UserInfoModal);
