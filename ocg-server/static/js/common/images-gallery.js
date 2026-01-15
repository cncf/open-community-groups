import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { lockBodyScroll, unlockBodyScroll } from "/static/js/common/common.js";

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
  }

  connectedCallback() {
    super.connectedCallback();
    this._handleKeydown = this._handleKeydown.bind(this);
    this._handleModalBackgroundClick = this._handleModalBackgroundClick.bind(this);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    if (this._isModalOpen) {
      unlockBodyScroll();
    }
    this._removeModalEventListeners();
  }

  _openModal(index) {
    this._currentIndex = index;
    this._isModalOpen = true;
    lockBodyScroll();
    document.addEventListener("keydown", this._handleKeydown);
    document.addEventListener("mousedown", this._handleModalBackgroundClick);
  }

  _closeModal() {
    this._isModalOpen = false;
    unlockBodyScroll();
    this._removeModalEventListeners();
  }

  _removeModalEventListeners() {
    document.removeEventListener("keydown", this._handleKeydown);
    document.removeEventListener("mousedown", this._handleModalBackgroundClick);
  }

  _navigateCarousel(direction) {
    if (direction === "next") {
      this._currentIndex = (this._currentIndex + 1) % this.images.length;
    } else if (direction === "prev") {
      this._currentIndex = this._currentIndex === 0 ? this.images.length - 1 : this._currentIndex - 1;
    }
  }

  _handleKeydown(e) {
    if (!this._isModalOpen) return;

    if (e.key === "Escape") {
      this._closeModal();
    } else if (e.key === "ArrowRight") {
      this._navigateCarousel("next");
    } else if (e.key === "ArrowLeft") {
      this._navigateCarousel("prev");
    }
  }

  _handleModalBackgroundClick(e) {
    if (!this._isModalOpen) return;

    if (e.target.parentElement?.tagName !== "BUTTON" && !["IMG", "BUTTON"].includes(e.target.tagName)) {
      this._closeModal();
    }
  }

  render() {
    if (!this.images || this.images.length === 0) {
      return html``;
    }

    return html`
      <div class="grid grid-cols-2 md:grid-cols-5 gap-4 md:gap-8">
        <!-- Photos list -->
        ${this.images.map(
          (image, index) => html`
            <div class="hidden md:block">
              <button class="w-full" @click=${() => this._openModal(index)}>
                <img
                  width="160"
                  height="160"
                  class="bg-white w-full aspect-[1/1] object-cover rounded-lg border border-5 border-white outline outline-offset-1 outline-1 outline-stone-300"
                  src=${image}
                  alt="${this.altImage} image ${index + 1}"
                />
              </button>
            </div>
            <div class="block md:hidden">
              <img
                width="160"
                height="160"
                class="bg-white w-full aspect-[1/1] object-cover rounded-lg border border-5 border-white outline outline-offset-1 outline-1 outline-stone-300"
                src=${image}
                alt="${this.altImage} image ${index + 1}"
              />
            </div>
          `,
        )}
        <!-- End photos list -->
      </div>

      <!-- Modal full page -->
      <div
        class="modal ${this._isModalOpen
          ? ""
          : "opacity-0 pointer-events-none"} fixed w-full h-full top-0 left-0 flex items-center justify-center z-1000"
      >
        <!-- Modal overlay -->
        <div class="modal-overlay absolute w-full h-full bg-stone-950 opacity-[0.35]"></div>
        <!-- End modal overlay -->

        <div class="modal-container fixed w-full h-full z-50 overflow-y-auto">
          <!-- Close button -->
          <button
            class="modal-close absolute top-0 right-0 cursor-pointer mt-10 mr-10 z-50 p-2 rounded-full bg-stone-200/75 hover:bg-stone-200/90"
            @click=${this._closeModal}
          >
            <div class="svg-icon size-8 bg-stone-800 icon-close"></div>
          </button>
          <!-- End close button -->

          <div class="modal-content container mx-auto h-full p-10 flex flex-col">
            <!-- Title -->
            <div
              class="uppercase text-lg lg:text-2xl tracking-wide font-bold text-stone-800 text-center leading-10 mb-10 w-1/2 mx-auto min-w-[200px] bg-stone-200/75 rounded-full"
            >
              ${this.title}
            </div>
            <!-- End title -->

            <!-- Body -->
            <div class="grow mx-10 xl:mx-20">
              <!-- Gallery -->
              <div class="relative size-full overflow-hidden">
                ${this.images.map(
                  (image, index) => html`
                    <div
                      class="duration-700 ease-in-out absolute inset-0 transition-transform transform ${index ===
                      this._currentIndex
                        ? "z-30 translate-x-0"
                        : "hidden z-10 translate-x-full"}"
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
                  class="inline-flex items-center justify-center w-10 h-10 rounded-full bg-stone-200/75 hover:bg-stone-200/90 focus:ring-0 focus:outline-none"
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
                  class="inline-flex items-center justify-center w-10 h-10 rounded-full bg-stone-200/75 hover:bg-stone-200/90 focus:ring-0 focus:outline-none"
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
