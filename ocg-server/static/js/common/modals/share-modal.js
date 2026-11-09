import { html, render } from "lit";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { showSuccessAlert, showErrorAlert } from "/static/js/common/alerts.js";
import {
  bindModalDismissListeners,
  closeModalBodyScroll,
  focusBottomSheet,
  focusModal,
  isModalOverlayTarget,
  openModalBodyScroll,
  trapBottomSheetFocus,
} from "/static/js/common/modals/modal-lifecycle.js";
import { bindSheetGestures } from "/static/js/common/modals/sheet-gestures.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { isPhoneViewport } from "/static/js/common/phone-viewport.js";
import "/static/vendor/js/sharer.v0.5.4.min.js";

/**
 * ShareModal displays a Share button that opens a modal with share options.
 * @extends LitWrapper
 * @property {string} triggerLabel - The accessible label for the share trigger
 * @property {string} triggerVariant - The trigger style variant: button, icon or
 *   menu-item, or the phone-only pill and action, which render in not-phone:hidden
 *   hosts. An action fills its host, so the host takes the row's flex-1.
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
      triggerLabel: { type: String, attribute: "trigger-label" },
      triggerVariant: { type: String, attribute: "trigger-variant" },
      title: { type: String },
      url: { type: String },
      _isOpen: { type: Boolean, state: true },
    };
  }

  constructor() {
    super();
    this.triggerLabel = "Share";
    this.triggerVariant = "button";
    this.title = "";
    this.url = "";
    this._isOpen = false;
    this._isSharing = false;
    this._modalContainer = null;
    this._removeDismissListeners = null;
    this._removeSheetGestures = null;
    this._restoreFocus = null;
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
    this._removeModalContainer();
    this._isOpen = closeModalBodyScroll(this._isOpen);
    this._restoreFocus = null;
  }

  /**
   * Opens the share modal and sets up event listeners for dismissal.
   */
  _openModal() {
    this._isOpen = openModalBodyScroll(this._isOpen);
    this._removeEventListeners();
    this._removeDismissListeners = bindModalDismissListeners({
      onKeydown: this._handleKeydown,
      onOutsideClick: this._handleOutsideClick,
    });
    this._renderModal();
    this._closeContainingDropdown();
  }

  /**
   * Closes the share modal and removes event listeners.
   */
  _closeModal() {
    this._isOpen = closeModalBodyScroll(this._isOpen);
    this._removeEventListeners();
    this._removeModalContainer();
    this._restoreFocus?.();
    this._restoreFocus = null;
  }

  /**
   * Removes document-level event listeners for keydown and outside click, and
   * releases the sheet gestures.
   */
  _removeEventListeners() {
    this._removeDismissListeners?.();
    this._removeDismissListeners = null;
    this._removeSheetGestures?.();
    this._removeSheetGestures = null;
  }

  /**
   * Ensures the modal is mounted outside any dropdown that contains the trigger.
   * @returns {HTMLElement} The document-level modal container
   */
  _ensureModalContainer() {
    if (!this._modalContainer) {
      this._modalContainer = document.createElement("div");
      document.body.append(this._modalContainer);
    }

    return this._modalContainer;
  }

  /**
   * Removes the document-level modal container.
   */
  _removeModalContainer() {
    if (!this._modalContainer) {
      return;
    }

    render("", this._modalContainer);
    this._modalContainer.remove();
    this._modalContainer = null;
  }

  /**
   * Renders the modal into the document-level container.
   */
  _renderModal() {
    if (!this._isOpen) {
      this._removeModalContainer();
      return;
    }

    const container = this._ensureModalContainer();
    render(this._renderModalContent(), container);
    const panel = container.querySelector(".sheet-panel");
    this._removeSheetGestures = bindSheetGestures(panel, { onPageRestore: () => this._closeModal() });
    this._restoreFocus ??=
      focusBottomSheet(panel, this.querySelector("button")) ?? this._focusCentredModal(panel);
  }

  /**
   * Closes the dropdown that contains the share trigger, when present.
   */
  _closeContainingDropdown() {
    const dropdown = this.closest("[data-event-actions-menu], details[open]");

    if (dropdown instanceof HTMLDetailsElement) {
      dropdown.open = false;
    }
  }

  /**
   * Moves focus into the centred modal, to its close button.
   * @param {HTMLElement} panel - The modal card
   * @returns {() => void} Callback that returns focus to the visible trigger
   */
  _focusCentredModal(panel) {
    focusModal(panel);
    return () => {
      this._getFocusReturnTarget()?.focus();
      // A backdrop click closes on mousedown, whose default action would clear focus again.
      if (window.event?.type === "mousedown") {
        window.event.preventDefault();
      }
    };
  }

  /**
   * Returns the control that takes focus back when the centred modal closes: the
   * trigger, or the summary of the menu whose closing hid the menu item trigger.
   * @returns {HTMLElement|null} The visible focus return target
   */
  _getFocusReturnTarget() {
    const trigger = this.querySelector("button");
    if (trigger?.checkVisibility()) {
      return trigger;
    }

    const summary = this.closest("details")?.querySelector(":scope > summary");
    return summary?.checkVisibility() ? summary : null;
  }

  /**
   * Handles keydown events to close the modal on Escape key press, and keeps Tab
   * inside the sheet.
   * @param {KeyboardEvent} event - The keyboard event
   */
  _handleKeydown(event) {
    if (this._isOpen && isEscapeEvent(event)) {
      event.preventDefault();
      this._closeModal();
    }
    if (this._restoreFocus) {
      trapBottomSheetFocus(event, this._modalContainer?.querySelector(".sheet-panel"));
    }
  }

  /**
   * Handles clicks outside the modal content to close the modal.
   * @param {MouseEvent} event - The mouse event
   */
  _handleOutsideClick(event) {
    if (!this._isOpen) return;

    if (isModalOverlayTarget(event.target)) {
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
   * @param {Event} event - Click event
   */
  _handleShareClick(event) {
    const button = event.currentTarget;

    if (window.Sharer) {
      const sharerInstance = new window.Sharer(button);
      sharerInstance.share();
      this._closeModal();
    }
  }

  /**
   * Handles click on copy button.
   * Copies the URL to clipboard and shows feedback. The modal closes before the
   * alert opens, so the alert hands focus back to the trigger when dismissed.
   */
  async _handleCopyClick() {
    const url = this._getFullUrl();

    try {
      await navigator.clipboard.writeText(url);
      this._closeModal();
      showSuccessAlert("Link copied to clipboard!");
    } catch {
      showErrorAlert("Failed to copy link. Please try again.");
    }
  }

  /**
   * Shares through the system sheet on phones, and opens the modal without
   * support or after a failure. navigator.share needs the tap's user gesture,
   * so nothing may be awaited before it.
   */
  async _handleNativeShare() {
    if (this._isSharing) {
      return;
    }

    const shareData = { title: this.title, url: this._getFullUrl() };
    if (!isPhoneViewport() || !navigator.canShare?.(shareData)) {
      this._openModal();
      return;
    }

    this._isSharing = true;
    try {
      await navigator.share(shareData);
    } catch (error) {
      if (error?.name !== "AbortError" && this.isConnected) {
        this._openModal();
      }
    } finally {
      this._isSharing = false;
    }
  }

  /**
   * Renders the control that opens the share modal.
   * @returns {TemplateResult} The share trigger template
   */
  _renderTrigger() {
    if (this.triggerVariant === "icon") {
      return html`
        <button
          type="button"
          class="btn-tertiary inline-flex items-center justify-center p-2"
          aria-label=${this.triggerLabel}
          @click=${() => this._openModal()}
          title=${this.triggerLabel}
        >
          <span class="svg-icon size-3.5 icon-share" aria-hidden="true"></span>
        </button>
      `;
    }

    if (this.triggerVariant === "pill" || this.triggerVariant === "action") {
      return html`
        <button
          type="button"
          class="group btn-primary-outline phone:inline-flex phone:h-11 phone:items-center phone:justify-center phone:gap-2 phone:px-5 phone:whitespace-nowrap ${
            this.triggerVariant === "action"
              ? "phone:w-full phone:max-[360px]:px-2.5 phone:max-[360px]:text-[13px]"
              : ""
          }"
          aria-label=${this.triggerLabel}
          @click=${() => this._handleNativeShare()}
          title=${this.triggerLabel}
        >
          <div class="svg-icon size-3 icon-share"></div>
          <span>Share</span>
        </button>
      `;
    }

    if (this.triggerVariant === "menu-item") {
      return html`
        <button
          type="button"
          class="group flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-stone-700 hover:bg-stone-50"
          aria-label=${this.triggerLabel}
          @click=${() => this._openModal()}
          title=${this.triggerLabel}
        >
          <div class="svg-icon size-4 bg-stone-600 icon-share"></div>
          <span>Share</span>
        </button>
      `;
    }

    return html`
      <button
        type="button"
        class="group btn-primary-outline flex h-10 w-10 items-center justify-center p-0 md:h-[30px] md:w-auto md:px-4 md:py-2 md:space-x-2"
        aria-label=${this.triggerLabel}
        @click=${() => this._openModal()}
        title=${this.triggerLabel}
      >
        <div class="svg-icon size-3 icon-share"></div>
        <span class="hidden md:inline">Share</span>
      </button>
    `;
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
        @click=${(event) => this._handleShareClick(event)}
      >
        <div
          class="svg-icon size-5 bg-primary-500 group-hover:bg-white transition-colors
                 icon-${icon}"
        ></div>
      </button>
    `;
  }

  /**
   * Renders the share modal.
   * @returns {TemplateResult} The component template
   */
  _renderModalContent() {
    return html`
      <div
        class="fixed inset-0 z-1300 flex items-center justify-center
               overflow-y-auto overflow-x-hidden"
        role="dialog"
        aria-modal="true"
        aria-labelledby="share-modal-title"
      >
        <div
          class="modal-overlay absolute w-full h-full bg-stone-950 opacity-[0.35]"
          @click=${() => this._closeModal()}
        ></div>

        <div class="modal-panel p-4 max-w-lg phone:p-0">
          <div class="modal-card sheet-panel rounded-lg">
            <div
              class="sheet-head sheet-grab flex items-center justify-between p-4 border-b
                     border-stone-200 rounded-t phone:py-0"
            >
              <h3 id="share-modal-title" class="text-lg font-semibold text-stone-900">Share</h3>
              <button
                type="button"
                class="group text-stone-400 bg-transparent hover:bg-stone-200
                       hover:text-stone-900 transition-colors rounded-lg text-sm
                       w-8 h-8 inline-flex justify-center items-center"
                @click=${() => this._closeModal()}
                aria-label="Close modal"
              >
                <div
                  class="svg-icon w-5 h-5 bg-stone-500 group-hover:bg-stone-900
                         transition-colors icon-close"
                ></div>
              </button>
            </div>

            <div class="modal-body sheet-body p-5 phone:p-3">
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
                    class="flex items-center justify-center size-8 rounded-full
                           hover:bg-stone-200 transition-colors cursor-pointer
                           flex-shrink-0 phone:size-11"
                    title="Copy link"
                    aria-label="Copy link"
                    @click=${() => this._handleCopyClick()}
                  >
                    <div class="svg-icon size-4 bg-stone-600 icon-copy"></div>
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    `;
  }

  /**
   * Renders the share button.
   * @returns {TemplateResult} The component template
   */
  render() {
    return this._renderTrigger();
  }
}

customElements.define("share-modal", ShareModal);
