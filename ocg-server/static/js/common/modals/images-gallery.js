import { html } from "lit";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import {
  bindModalDismissListeners,
  closeModalBodyScroll,
  focusModal,
  openModalBodyScroll,
  restoreModalFocus,
  trapModalFocus,
} from "/static/js/common/modals/modal-lifecycle.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { isPhoneViewport, PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import { syncSnapDots } from "/static/js/common/snap-dots.js";

const MAX_SNAP_DOTS = 10;
const SWIPE_AXIS_RATIO = 1.5;
const SWIPE_MIN_DISTANCE = 48;

/**
 * ImagesGallery component for displaying images with modal carousel.
 * @extends LitWrapper
 */
export class ImagesGallery extends LitWrapper {
  static get properties() {
    return {
      images: { type: Array },
      title: { type: String },
      altImage: { type: String },
      _isModalOpen: { type: Boolean },
      _currentIndex: { type: Number },
    };
  }

  constructor() {
    super();
    this.images = [];
    this.title = "Gallery";
    this.altImage = "Gallery";
    this._isModalOpen = false;
    this._currentIndex = 0;
    this._removeDismissListeners = null;
    this._removeLightboxDialog = null;
    this._removePhoneQueryListener = null;
    this._removeSwipeListeners = null;
    this._restoreLightboxFocus = null;
    this._swipeStart = null;
  }

  connectedCallback() {
    super.connectedCallback();
    this._handleKeydown = this._handleKeydown.bind(this);
    this._handleModalBackgroundClick = this._handleModalBackgroundClick.bind(this);
    this._handleTouchEnd = this._handleTouchEnd.bind(this);
    this._handleTouchStart = this._handleTouchStart.bind(this);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this._isModalOpen = closeModalBodyScroll(this._isModalOpen);
    this._removeModalEventListeners();
    this._restoreLightboxFocus = null;
  }

  updated(changedProperties) {
    if (changedProperties.has("images")) {
      syncSnapDots(this);
    }
  }

  _openModal(index) {
    this._currentIndex = index;
    this._isModalOpen = openModalBodyScroll(this._isModalOpen);
    this._removeModalEventListeners();
    this._removeDismissListeners = bindModalDismissListeners({
      onKeydown: this._handleKeydown,
      onOutsideClick: this._handleModalBackgroundClick,
    });
    this._bindPhoneLightbox(window.event?.currentTarget ?? null);
  }

  _closeModal() {
    this._isModalOpen = closeModalBodyScroll(this._isModalOpen);
    this._removeModalEventListeners();
    this._restoreLightboxFocus?.();
  }

  _removeModalEventListeners() {
    this._removeDismissListeners?.();
    this._removeDismissListeners = null;
    this._removePhoneQueryListener?.();
    this._releasePhoneLightbox();
  }

  /**
   * Releases the dialog and swipe of a phone lightbox.
   */
  _releasePhoneLightbox() {
    this._removeLightboxDialog?.();
    this._removeSwipeListeners?.();
    this._removeSwipeListeners = null;
    this._swipeStart = null;
  }

  /**
   * Gives a lightbox opened on a phone its dialog and swipe, and follows the phone query until it
   * closes: a rotation past phone widths releases both, and rotating back binds them again. Focus
   * still returns on close after a rotation.
   * @param {HTMLElement|null} opener Tile that opened the lightbox.
   */
  _bindPhoneLightbox(opener) {
    const lightbox = this.querySelector(".modal");
    if (!lightbox || !isPhoneViewport()) return;

    const phoneQuery = window.matchMedia(PHONE_MEDIA_QUERY);
    const handlePhoneQueryChange = (event) => {
      if (!event.matches) {
        this._releasePhoneLightbox();
        return;
      }

      this._bindLightboxDialog(lightbox);
      this._bindLightboxSwipe(lightbox);
      // The plain lightbox has no trap, so focus may have reached the page behind it.
      if (!lightbox.contains(document.activeElement)) {
        lightbox.querySelector(".modal-close")?.focus();
      }
    };

    phoneQuery.addEventListener("change", handlePhoneQueryChange);
    this._removePhoneQueryListener = () => {
      this._removePhoneQueryListener = null;
      phoneQuery.removeEventListener("change", handlePhoneQueryChange);
    };

    this._bindLightboxDialog(lightbox);
    this._bindLightboxSwipe(lightbox);
    this._restoreLightboxFocus = () => {
      this._restoreLightboxFocus = null;
      restoreModalFocus(lightbox);
      // A backdrop tap closes on mousedown, whose default action would clear focus again.
      if (window.event?.type === "mousedown") {
        window.event.preventDefault();
      }
    };

    // The closed lightbox is invisible on phones, and its controls take no focus until it renders.
    const removeDialog = this._removeLightboxDialog;
    this.updateComplete.then(() => {
      if (this._removeLightboxDialog === removeDialog) {
        focusModal(lightbox, opener);
      }
    });
  }

  /**
   * Makes the lightbox a modal dialog. A template attribute would reach every width.
   * @param {HTMLElement} lightbox Lightbox root.
   */
  _bindLightboxDialog(lightbox) {
    const handleHistorySave = () => this._closeModal();
    const handlePageShow = (event) => {
      if (event.persisted) {
        this._closeModal();
      }
    };

    lightbox.setAttribute("aria-label", this.title);
    lightbox.setAttribute("aria-modal", "true");
    lightbox.setAttribute("role", "dialog");
    document.addEventListener("htmx:beforeHistorySave", handleHistorySave);
    window.addEventListener("pageshow", handlePageShow);
    this._removeLightboxDialog = () => {
      this._removeLightboxDialog = null;
      document.removeEventListener("htmx:beforeHistorySave", handleHistorySave);
      window.removeEventListener("pageshow", handlePageShow);
      lightbox.removeAttribute("aria-label");
      lightbox.removeAttribute("aria-modal");
      lightbox.removeAttribute("role");
      // The shared restore hides any open dialog, and this node stays in the page.
      lightbox.removeAttribute("aria-hidden");
    };
  }

  /**
   * Binds lightbox swipe. Lit's @touchstart would attach at every width.
   * @param {HTMLElement} lightbox Lightbox root.
   */
  _bindLightboxSwipe(lightbox) {
    if (this.images.length < 2) return;

    lightbox.addEventListener("touchstart", this._handleTouchStart, { passive: true });
    lightbox.addEventListener("touchend", this._handleTouchEnd, { passive: true });
    this._removeSwipeListeners = () => {
      lightbox.removeEventListener("touchstart", this._handleTouchStart);
      lightbox.removeEventListener("touchend", this._handleTouchEnd);
    };
  }

  _navigateCarousel(direction) {
    if (direction === "next") {
      this._currentIndex = (this._currentIndex + 1) % this.images.length;
    } else if (direction === "prev") {
      this._currentIndex = this._currentIndex === 0 ? this.images.length - 1 : this._currentIndex - 1;
    }
  }

  _handleKeydown(event) {
    if (!this._isModalOpen) return;

    if (isEscapeEvent(event)) {
      this._closeModal();
    } else if (event.key === "ArrowRight") {
      this._navigateCarousel("next");
    } else if (event.key === "ArrowLeft") {
      this._navigateCarousel("prev");
    } else if (this._removeLightboxDialog) {
      trapModalFocus(event, this.querySelector(".modal"));
    }
  }

  _handleModalBackgroundClick(event) {
    if (!this._isModalOpen) return;

    if (
      event.target.parentElement?.tagName !== "BUTTON" &&
      !["IMG", "BUTTON"].includes(event.target.tagName)
    ) {
      this._closeModal();
    }
  }

  /**
   * Records where a one-finger touch began. A second finger cancels it, so pinch zoom works.
   * @param {TouchEvent} event Touch start event.
   */
  _handleTouchStart(event) {
    const [touch] = event.touches;
    this._swipeStart = event.touches.length === 1 ? { x: touch.clientX, y: touch.clientY } : null;
  }

  /**
   * Turns a horizontal swipe into a carousel step.
   * @param {TouchEvent} event Touch end event.
   */
  _handleTouchEnd(event) {
    const start = this._swipeStart;
    this._swipeStart = null;
    if (!start) return;

    const [touch] = event.changedTouches;
    const deltaX = touch.clientX - start.x;
    const deltaY = touch.clientY - start.y;
    if (Math.abs(deltaX) >= SWIPE_MIN_DISTANCE && Math.abs(deltaX) > SWIPE_AXIS_RATIO * Math.abs(deltaY)) {
      this._navigateCarousel(deltaX < 0 ? "next" : "prev");
    }
  }

  render() {
    if (!this.images || this.images.length === 0) {
      return html``;
    }

    const hasManyImages = this.images.length > 1;

    return html`
      <div
        class="grid grid-cols-2 md:grid-cols-5 gap-4 md:gap-8 phone:flex phone:gap-3 phone:-mx-3 phone:px-3 phone:py-0.5 phone:scroll-px-3 phone:overflow-x-auto phone:snap-x phone:snap-mandatory phone:[scrollbar-width:none]"
      >
        <!-- Photos list -->
        ${this.images.map(
          (image, index) => html`
            <div
              class="hidden md:block phone:block ${
                hasManyImages ? "phone:w-[calc(100%-3.5rem)]" : "phone:w-full"
              } phone:shrink-0 phone:snap-start"
            >
              <button
                class="relative w-full overflow-hidden rounded-lg bg-white outline outline-offset-1 outline-1 outline-stone-300 transition-all hover:outline-primary-300 hover:shadow-sm focus-visible:ring-2 focus-visible:ring-primary-300"
                aria-label="Open ${this.altImage} image ${index + 1}"
                @click=${() => this._openModal(index)}
              >
                <img
                  width="160"
                  height="160"
                  class="bg-white w-full aspect-[1/1] object-cover rounded-lg border border-5 border-white"
                  data-ocg-broken-image-bg-class="bg-stone-50 m-[5px] rounded-md"
                  src=${image}
                  alt="${this.altImage} image ${index + 1}"
                />
              </button>
            </div>
            <div
              class="relative block overflow-hidden rounded-lg bg-white outline outline-offset-1 outline-1 outline-stone-300 md:hidden phone:hidden"
            >
              <img
                width="160"
                height="160"
                class="bg-white w-full aspect-[1/1] object-cover rounded-lg border border-5 border-white"
                data-ocg-broken-image-bg-class="bg-stone-50 m-[5px] rounded-md"
                src=${image}
                alt="${this.altImage} image ${index + 1}"
              />
            </div>
          `,
        )}
        <!-- End photos list -->
      </div>
      ${
        hasManyImages
          ? html`
              <!-- Position row, directly after the list for snap-dots.js -->
              <div
                class="not-phone:hidden"
                aria-hidden="true"
                data-snap-dots
                data-snap-dots-max=${MAX_SNAP_DOTS}
              >
                <span data-snap-counter></span>
              </div>
              <!-- End position row -->
            `
          : ""
      }

      <!-- Modal full page -->
      <div
        class="modal ${
          this._isModalOpen ? "" : "opacity-0 pointer-events-none phone:invisible"
        } fixed w-full h-full top-0 left-0 flex items-center justify-center z-1000"
      >
        <!-- Modal overlay -->
        <div
          class="modal-overlay absolute w-full h-full bg-stone-950 opacity-[0.35] phone:opacity-[0.85]"
        ></div>
        <!-- End modal overlay -->

        <div class="modal-container fixed w-full h-full z-50 overflow-y-auto">
          <!-- Close button -->
          <button
            class="modal-close absolute top-0 right-0 cursor-pointer mt-10 mr-10 z-50 p-2 rounded-full bg-stone-200/75 hover:bg-stone-200/90 phone:mt-3 phone:mr-3 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-300"
            @click=${this._closeModal}
          >
            <div class="svg-icon size-8 bg-stone-800 icon-close"></div>
            <span class="sr-only">Close</span>
          </button>
          <!-- End close button -->

          <div class="modal-content container mx-auto h-full p-10 flex flex-col phone:p-0">
            <!-- Title -->
            <div
              class="uppercase text-lg lg:text-2xl tracking-wide font-bold text-stone-800 text-center leading-10 mb-10 w-1/2 mx-auto min-w-[200px] bg-stone-200/75 rounded-full phone:mt-3 phone:mb-3 phone:min-w-0"
            >
              ${this.title}
            </div>
            <!-- End title -->

            <!-- Body -->
            <div class="grow mx-10 xl:mx-20 phone:mx-0">
              <!-- Gallery -->
              <div class="relative size-full overflow-hidden">
                ${this.images.map(
                  (image, index) => html`
                    <div
                      class="duration-700 ease-in-out absolute inset-0 transition-transform transform ${
                        index === this._currentIndex ? "z-30 translate-x-0" : "hidden z-10 translate-x-full"
                      }"
                    >
                      <img
                        src=${image}
                        height="auto"
                        width="auto"
                        class="bg-white rounded-lg border border-5 border-white absolute block w-auto max-w-full max-h-full h-auto -translate-x-1/2 -translate-y-1/2 top-1/2 left-1/2"
                        alt="${this.altImage} image ${index + 1}"
                      />
                    </div>
                  `,
                )}
              </div>
              <!-- End gallery -->
            </div>
            <!-- End body -->

            <!-- Buttons -->
            <div class="flex">
              <div class="absolute top-0 start-0 z-30 flex items-center justify-center h-full px-5 xl:px-10">
                <!-- Prev button -->
                <button
                  class="inline-flex items-center justify-center w-10 h-10 rounded-full bg-stone-200/75 hover:bg-stone-200/90 phone:size-11 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-300"
                  @click=${() => this._navigateCarousel("prev")}
                >
                  <div class="svg-icon h-4 w-2.5 bg-stone-950 icon-prev"></div>
                  <span class="sr-only">Previous</span>
                </button>
                <!-- End prev button -->
              </div>
              <div class="absolute top-0 end-0 z-30 flex items-center justify-center h-full px-5 xl:px-10">
                <!-- Next button -->
                <button
                  class="inline-flex items-center justify-center w-10 h-10 rounded-full bg-stone-200/75 hover:bg-stone-200/90 phone:size-11 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-300"
                  @click=${() => this._navigateCarousel("next")}
                >
                  <div class="svg-icon h-4 w-2.5 bg-stone-950 icon-next"></div>
                  <span class="sr-only">Next</span>
                </button>
                <!-- End next button -->
              </div>
            </div>
            <!-- End buttons -->
          </div>
        </div>
      </div>
      <!-- End modal full page -->
    `;
  }
}
customElements.define("images-gallery", ImagesGallery);
