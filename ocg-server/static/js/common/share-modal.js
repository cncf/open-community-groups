import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { lockBodyScroll, unlockBodyScroll } from "/static/js/common/common.js";
import { showSuccessAlert, showErrorAlert } from "/static/js/common/alerts.js";
import "/static/vendor/js/sharer.v0.5.3.min.js";

/**
 * ShareModal displays a Share button that opens a modal with share options.
 * @extends LitWrapper
 * @property {string} title - The title to share
 * @property {string} url - The URL to share
 */
export class ShareModal extends LitWrapper {
  /**
   * Defines the reactive properties for this component.
   * @returns {Object} Property definitions for Lit
   */
  static get properties() {
    return {
      title: { type: String },
      url: { type: String },
      _isOpen: { type: Boolean, state: true },
    };
  }

  constructor() {
    super();
    this.title = "";
    this.url = "";
    this._isOpen = false;
  }

  /**
   * Invoked when the element is added to the document's DOM. Binds event handlers.
   */
  connectedCallback() {
    super.connectedCallback();
    this._handleKeydown = this._handleKeydown.bind(this);
    this._handleOutsideClick = this._handleOutsideClick.bind(this);
  }

  /**
   * Invoked when the element is removed from the document's DOM. Cleans up resources.
   */
  disconnectedCallback() {
    super.disconnectedCallback();
    this._removeEventListeners();
    if (this._isOpen) {
      unlockBodyScroll();
    }
  }

  /**
   * Opens the share modal and sets up event listeners for dismissal.
   */
  _openModal() {
    this._isOpen = true;
    lockBodyScroll();
    document.addEventListener("keydown", this._handleKeydown);
    document.addEventListener("mousedown", this._handleOutsideClick);
  }

  /**
   * Closes the share modal and removes event listeners.
   */
  _closeModal() {
    this._isOpen = false;
    unlockBodyScroll();
    this._removeEventListeners();
  }

  /**
   * Removes document-level event listeners for keydown and outside click.
   */
  _removeEventListeners() {
    document.removeEventListener("keydown", this._handleKeydown);
    document.removeEventListener("mousedown", this._handleOutsideClick);
  }

  /**
   * Handles keydown events to close the modal on Escape key press.
   * @param {KeyboardEvent} e - The keyboard event
   */
  _handleKeydown(e) {
    if (this._isOpen && e.key === "Escape") {
      e.preventDefault();
      this._closeModal();
    }
  }

  /**
   * Handles clicks outside the modal content to close the modal.
   * @param {MouseEvent} e - The mouse event
   */
  _handleOutsideClick(e) {
    if (!this._isOpen) return;

    if (e.target.classList && e.target.classList.contains("modal-overlay")) {
      this._closeModal();
    }
  }

  /**
   * Returns the full URL including origin for relative URLs.
   * @returns {string} The full URL
   */
  _getFullUrl() {
    let url = this.url;
    if (url && !url.startsWith("http")) {
      url = window.location.origin + url;
    }
    return url;
  }

  /**
   * Handles click on share platform buttons.
   * Uses sharer.js to open the share dialog.
   * @param {Event} e - Click event
   */
  _handleShareClick(e) {
    const button = e.currentTarget;

    if (window.Sharer) {
      const sharerInstance = new window.Sharer(button);
      sharerInstance.share();
      this._closeModal();
    }
  }

  /**
   * Handles click on copy button.
   * Copies the URL to clipboard and shows feedback.
   */
  async _handleCopyClick() {
    const url = this._getFullUrl();

    try {
      await navigator.clipboard.writeText(url);
      showSuccessAlert("Link copied to clipboard!");
      this._closeModal();
    } catch {
      showErrorAlert("Failed to copy link. Please try again.");
    }
  }

  /**
   * Renders a share button for a specific platform.
   * @param {string} sharer - The sharer.js platform identifier
   * @param {string} icon - The icon class name
   * @param {string} label - The button label/title (for accessibility)
   * @returns {TemplateResult} The share button template
   */
  _renderShareButton(sharer, icon, label) {
    return html`
      <button
        type="button"
        data-sharer=${sharer}
        data-title=${this.title}
        data-url=${this._getFullUrl()}
        data-subject=${sharer === "email" ? this.title : ""}
        class="group btn-secondary-anchor flex items-center justify-center size-12 p-2"
        title=${label}
        aria-label=${label}
        @click=${this._handleShareClick}
      >
        <div
          class="svg-icon size-5 bg-primary-500 group-hover:bg-white transition-colors
                 icon-${icon}"
        ></div>
      </button>
    `;
  }

  /**
   * Renders the share button and modal.
   * @returns {TemplateResult} The component template
   */
  render() {
    return html`
      <button
        type="button"
        class="group btn-primary-outline h-10 md:h-[30px] px-4
               flex items-center justify-center space-x-2"
        @click=${this._openModal}
        title="Share"
      >
        <div class="svg-icon size-3 icon-share"></div>
        <span>Share</span>
      </button>

      ${this._isOpen
        ? html`
            <div
              class="fixed inset-0 z-1300 flex items-center justify-center
                     overflow-y-auto overflow-x-hidden"
              role="dialog"
              aria-modal="true"
              aria-labelledby="share-modal-title"
            >
              <div
                class="modal-overlay absolute w-full h-full bg-stone-950 opacity-[0.35]"
                @click=${this._closeModal}
              ></div>

              <div class="relative p-4 w-full max-w-lg max-h-full">
                <div class="relative bg-white rounded-lg shadow-lg">
                  <div
                    class="flex items-center justify-between p-4 border-b
                           border-stone-200 rounded-t"
                  >
                    <h3 id="share-modal-title" class="text-lg font-semibold text-stone-900">Share</h3>
                    <button
                      type="button"
                      class="group text-stone-400 bg-transparent hover:bg-stone-200
                             hover:text-stone-900 transition-colors rounded-lg text-sm
                             w-8 h-8 inline-flex justify-center items-center"
                      @click=${this._closeModal}
                      aria-label="Close modal"
                    >
                      <div
                        class="svg-icon w-5 h-5 bg-stone-500 group-hover:bg-stone-900
                               transition-colors icon-close"
                      ></div>
                    </button>
                  </div>

                  <div class="p-5">
                    <div class="text-sm font-medium text-stone-700 mb-4">Share this link via</div>
                    <div class="flex flex-wrap gap-3">
                      ${this._renderShareButton("email", "email", "Email")}
                      ${this._renderShareButton("twitter", "twitter", "X")}
                      ${this._renderShareButton("facebook", "facebook", "Facebook")}
                      ${this._renderShareButton("whatsapp", "whatsapp", "WhatsApp")}
                      ${this._renderShareButton("reddit", "reddit", "Reddit")}
                      ${this._renderShareButton("linkedin", "linkedin", "LinkedIn")}
                      ${this._renderShareButton("bluesky", "bluesky", "Bluesky")}
                    </div>

                    <div class="border-t border-stone-200 mt-5 pt-5">
                      <div class="text-sm font-medium text-stone-700 mb-3">Copy link</div>
                      <div
                        class="flex items-center gap-2 p-3 border border-stone-200
                               rounded-lg bg-stone-50"
                      >
                        <span class="flex-1 text-sm text-stone-600 truncate select-all">
                          ${this._getFullUrl()}
                        </span>
                        <button
                          type="button"
                          class="flex items-center justify-center size-8 rounded
                                 hover:bg-stone-200 transition-colors cursor-pointer
                                 flex-shrink-0"
                          title="Copy link"
                          aria-label="Copy link"
                          @click=${this._handleCopyClick}
                        >
                          <div class="svg-icon size-5 bg-stone-600 icon-copy"></div>
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          `
        : ""}
    `;
  }
}

customElements.define("share-modal", ShareModal);
