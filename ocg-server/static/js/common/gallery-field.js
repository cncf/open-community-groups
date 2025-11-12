import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { isSuccessfulXHRStatus } from "/static/js/common/common.js";
import { showErrorAlert, showSuccessAlert } from "/static/js/common/alerts.js";

const DEFAULT_MAX_IMAGES = 8;

/**
 * GalleryField mirrors the single-image upload flow from image-field while
 * managing multiple thumbnails, drag/drop, and validation inside dashboards.
 * @extends LitWrapper
 */
export class GalleryField extends LitWrapper {
  /**
   * Component properties exposed to Lit templates.
   * @property {string} label - Visible label shown above the gallery grid.
   * @property {string} legend - Optional instructions or help text for the uploader.
   * @property {string} fieldName - Name attribute used for hidden inputs when set.
   * @property {Array<string>} images - Initial gallery URLs to render in the grid.
   * @property {number} maxImages - Maximum number of uploads allowed (0 = unlimited).
   */
  static properties = {
    label: { type: String },
    legend: { type: String },
    fieldName: { type: String, attribute: "field-name" },
    images: { type: Array },
    maxImages: { type: Number, attribute: "max-images" },
  };

  /**
   * Initialize defaults for labels, state flags, and unique IDs.
   */
  constructor() {
    super();
    this.label = "Gallery";
    this.legend = "";
    this.fieldName = "";
    this.images = [];
    this.maxImages = DEFAULT_MAX_IMAGES;
    this._isUploading = false;
    this._isDragActive = false;
    this._pendingUploads = 0;
    this._uploadErrorShown = false;
    this._uniqueId = `gallery-field-${Math.random().toString(36).slice(2, 9)}`;
    this._draggedIndex = null;
    this._dragOverIndex = null;
  }

  /**
   * Normalize provided image data before the first render.
   */
  connectedCallback() {
    super.connectedCallback();
    this._normalizeImages();
  }

  /**
   * Normalize and trim stored image URLs according to maxImages.
   */
  _normalizeImages() {
    let current = this.images;
    if (typeof current === "string") {
      try {
        current = JSON.parse(current);
      } catch (error) {
        current = [];
      }
    }

    if (!Array.isArray(current)) {
      current = [];
    }

    const limit = this.maxImages > 0 ? this.maxImages : undefined;
    this.images = current
      .filter((item) => typeof item === "string" && item.trim().length > 0)
      .slice(0, limit);
  }

  /**
   * Build a consistent ID for the hidden file input per instance.
   */
  get _fileInputId() {
    return `${this._uniqueId}-file`;
  }

  /**
   * Remaining slots = maxImages minus current images, or infinite when unlimited.
   */
  get _remainingSlots() {
    if (this.maxImages > 0) {
      return Math.max(this.maxImages - (this.images?.length || 0), 0);
    }
    return Number.POSITIVE_INFINITY;
  }

  /**
   * Show add tile only when there is capacity or uploads are unlimited.
   */
  get _showAddTile() {
    return this._remainingSlots > 0;
  }

  /**
   * Provide contextual instructions based on legend or maximum count.
   */
  get _instructions() {
    let tmp_legend;
    if (this.legend && this.legend.trim().length > 0) {
      tmp_legend = this.legend;
    }
    if (this.maxImages > 0) {
      tmp_legend = `Upload up to ${this.maxImages} images. Maximum size: 2MB each.`;
    }
    tmp_legend = `Upload as many images as you need. Maximum size: 2MB each.`;

    return `${tmp_legend} Drag and drop thumbnails to change their order before submitting.`;
  }

  /**
   * Disable new uploads while a drag/upload cycle is active or limit reached.
   */
  get _isAddDisabled() {
    return this._isUploading || this._remainingSlots === 0;
  }

  /**
   * Programmatically open the hidden file selector if uploads are allowed.
   */
  _triggerFilePicker() {
    if (this._isAddDisabled) {
      return;
    }
    const input = this.querySelector(`#${this._fileInputId}`);
    input?.click();
  }

  /**
   * Let Enter or Space activate the picker for accessibility.
   */
  _handlePlaceholderKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }
    event.preventDefault();
    this._triggerFilePicker();
  }

  /**
   * Highlight the drop target while files are dragged over it.
   */
  _handleDragOver(event) {
    if (this._isAddDisabled) {
      event.preventDefault();
      return;
    }
    event.preventDefault();
    this._isDragActive = true;
    this.requestUpdate();
  }

  /**
   * Reset the drag state when the pointer leaves the drop zone.
   */
  _handleDragLeave(event) {
    if (this._isAddDisabled) {
      return;
    }
    if (event.relatedTarget && this.contains(event.relatedTarget)) {
      return;
    }
    event.preventDefault();
    this._isDragActive = false;
    this.requestUpdate();
  }

  /**
   * Accept dropped files and forward them to the upload handler.
   */
  async _handleDrop(event) {
    if (this._isAddDisabled) {
      return;
    }
    event.preventDefault();
    this._isDragActive = false;
    const files = Array.from(event.dataTransfer?.files || []);
    if (files.length === 0) {
      return;
    }
    await this._handleIncomingFiles(files);
  }

  /**
   * Forward files selected via the native picker to the upload pipeline.
   */
  async _handleFileChange(event) {
    const input = event.target;
    const files = Array.from(input.files || []);
    if (files.length === 0) {
      return;
    }
    await this._handleIncomingFiles(files);
    input.value = "";
  }

  /**
   * Uploads files sequentially while keeping feedback consistent with image-field.
   */
  async _handleIncomingFiles(files) {
    const hasLimit = this.maxImages > 0;
    const filesToUpload = hasLimit ? files.slice(0, this._remainingSlots) : files;
    if (filesToUpload.length === 0) {
      if (hasLimit && this._remainingSlots === 0) {
        showErrorAlert(`You can upload up to ${this.maxImages} images.`);
      }
      return;
    }

    this._pendingUploads += filesToUpload.length;
    this._isUploading = true;
    this._uploadErrorShown = false;
    this.requestUpdate();

    let createdCount = 0;

    for (const file of filesToUpload) {
      try {
        const url = await this._uploadFile(file);
        if (url) {
          createdCount += 1;
          this._setImages([...this.images, url]);
        }
      } catch (error) {
        if (!this._uploadErrorShown) {
          const ERROR_MESSAGE =
            'Something went wrong adding the images, please try again later.<br /><br /><div class="text-sm text-stone-500"> Maximum file size: 2MB. Formats supported: SVG, PNG, JPEG, GIF, WEBP and TIFF.</div>';
          showErrorAlert(ERROR_MESSAGE, true);
          this._uploadErrorShown = true;
        }
      }
    }

    this._pendingUploads = Math.max(0, this._pendingUploads - filesToUpload.length);
    if (this._pendingUploads === 0) {
      this._isUploading = false;
    }
    this.requestUpdate();

    if (createdCount > 0) {
      const message =
        createdCount === 1 ? "Image added successfully." : `${createdCount} images added successfully.`;
      showSuccessAlert(message);
    }
  }

  /**
   * Upload a single file to the server and return the resulting URL.
   */
  async _uploadFile(file) {
    const formData = new FormData();
    formData.append("file", file, file.name);

    const response = await fetch("/images", {
      method: "POST",
      body: formData,
      credentials: "same-origin",
      headers: {
        "HX-Request": "true",
      },
    });

    if (!isSuccessfulXHRStatus(response.status)) {
      const errorMessage = await response.text();
      throw new Error(errorMessage || "Upload failed");
    }

    const data = await response.json();
    if (!data || !data.url) {
      throw new Error("Missing image URL");
    }

    return data.url;
  }

  /**
   * Matches the normalization done earlier so we always render the latest list.
   */
  _setImages(newImages) {
    const limit = this.maxImages > 0 ? this.maxImages : undefined;
    const sanitized = (newImages || [])
      .filter((value) => typeof value === "string" && value.trim().length > 0)
      .slice(0, limit);
    this.images = sanitized;
    this._dispatchImagesChange();
    this.requestUpdate();
  }

  /**
   * Removes exactly the requested index while uploads remain blocking.
   */
  _handleRemoveImage(index) {
    if (this._isUploading) {
      return;
    }
    const filtered = [...this.images];
    filtered.splice(index, 1);
    this._setImages(filtered);
  }

  /**
   * Reorder images when a drag drop completes.
   */
  _reorderImages(sourceIndex, targetIndex) {
    if (this._isUploading || sourceIndex === targetIndex) {
      return;
    }
    const reordered = [...this.images];
    const [item] = reordered.splice(sourceIndex, 1);
    reordered.splice(targetIndex, 0, item);
    this._setImages(reordered);
  }

  /**
   * Clear any drag tracking metadata.
   */
  _clearDragState() {
    this._draggedIndex = null;
    this._dragOverIndex = null;
    this.requestUpdate();
  }

  /**
   * Mark the tile being dragged and update the drag data transfer.
   */
  _handleTileDragStart(event, index) {
    event.stopPropagation();
    this._draggedIndex = index;
    this._dragOverIndex = index;
    const dataTransfer = event.dataTransfer;
    if (dataTransfer) {
      dataTransfer.setData("text/plain", String(index));
      if (typeof dataTransfer.setDragImage === "function") {
        dataTransfer.setDragImage(event.currentTarget, 0, 0);
      }
      if (typeof dataTransfer.setDropEffect === "function") {
        dataTransfer.setDropEffect("move");
      }
    }
    this.requestUpdate();
  }

  /**
   * Highlight the drop target while dragging over a tile.
   */
  _handleTileDragOver(event, index) {
    event.preventDefault();
    if (this._draggedIndex === null) {
      return;
    }
    this._dragOverIndex = index;
    this.requestUpdate();
  }

  /**
   * Reset drag highlight when leaving a tile.
   */
  _handleTileDragLeave(event, index) {
    if (this._dragOverIndex === index) {
      this._dragOverIndex = null;
      this.requestUpdate();
    }
  }

  /**
   * Reorder images when the tile is dropped.
   */
  _handleTileDrop(event, index) {
    event.preventDefault();
    event.stopPropagation();
    if (this._draggedIndex === null) {
      return;
    }
    this._reorderImages(this._draggedIndex, index);
    this._clearDragState();
  }

  /**
   * Clear drag state after dragging finishes.
   */
  _handleTileDragEnd() {
    this._clearDragState();
  }

  /**
   * Stop propagation from the button and remove the provided index.
   */
  _handleRemoveImageButtonClick(event, index) {
    event.stopPropagation();
    if (typeof index !== "number") {
      return;
    }
    this._handleRemoveImage(index);
  }

  /**
   * Broadcast the latest image list so outer forms stay in sync.
   */
  _dispatchImagesChange() {
    this.dispatchEvent(
      new CustomEvent("images-change", {
        detail: { images: this.images },
        bubbles: true,
        composed: true,
      }),
    );
  }

  /**
   * Clear every thumbnail when the form requests a full reset.
   */
  _handleRemoveAll() {
    if (this._isUploading || this.images.length === 0) {
      return;
    }
    this._setImages([]);
  }

  /**
   * Ensures the add tile stays the same size as the existing previews on large screens.
   */
  _renderAddTile() {
    if (!this._showAddTile) {
      return "";
    }

    return html`
      <div
        class="${[
          "relative flex h-32 w-full max-h-32 flex-1 cursor-pointer items-center justify-center rounded-lg border-2 border-dashed border-stone-300 bg-stone-50 transition duration-150",
          this._isAddDisabled ? "cursor-not-allowed opacity-70" : "hover:border-primary-400",
          this._isDragActive && !this._isUploading ? "ring-2 ring-primary-300" : "",
        ].join(" ")}"
        role="button"
        tabindex="0"
        aria-label="Add gallery images"
        aria-disabled="${this._isAddDisabled}"
        @click="${this._triggerFilePicker}"
        @keydown="${this._handlePlaceholderKeyDown}"
        @dragover="${this._handleDragOver}"
        @dragleave="${this._handleDragLeave}"
        @drop="${this._handleDrop}"
      >
        <div class="flex flex-col items-center gap-1 text-center text-stone-500">
          <div class="text-4xl font-bold leading-none">+</div>
          <span class="text-sm font-semibold leading-snug">Add images</span>
        </div>

        <div
          class="absolute inset-0 flex items-center justify-center bg-white/80 transition-opacity duration-150 ${this
            ._isUploading
            ? "opacity-100"
            : "opacity-0 pointer-events-none"}"
        >
          <div role="status" class="flex size-8">
            <img
              src="/static/images/spinner/spinner_4.svg"
              height="auto"
              width="auto"
              alt="Uploading spinner"
              class="size-6 animate-spin"
            />
            <span class="sr-only">Uploading...</span>
          </div>
        </div>
      </div>
    `;
  }

  /**
   * Render the instructions, preview grid, and hidden inputs.
   */
  render() {
    return html`
      <div class="space-y-4">
        <div class="flex flex-col gap-1">
          <div class="text-lg font-semibold text-stone-900">${this.label}</div>
          <p class="form-legend">${this._instructions}</p>
        </div>

        <div class="grid grid-cols-3 gap-6 md:gap-8 sm:grid-cols-4">
          ${this.images.map(
            (imageUrl, index) => html`
              <div
                class="${[
                  "relative h-32 max-h-32 w-full overflow-hidden rounded-lg border border-stone-200 bg-stone-100",
                  this._dragOverIndex === index && this._draggedIndex !== null && this._draggedIndex !== index
                    ? "ring-2 ring-primary-300"
                    : "",
                  this._draggedIndex === index ? "opacity-80" : "",
                ].join(" ")}"
                draggable="true"
                @dragstart="${(event) => this._handleTileDragStart(event, index)}"
                @dragover="${(event) => this._handleTileDragOver(event, index)}"
                @dragleave="${(event) => this._handleTileDragLeave(event, index)}"
                @drop="${(event) => this._handleTileDrop(event, index)}"
                @dragend="${this._handleTileDragEnd}"
              >
                <img
                  src="${imageUrl}"
                  alt="Gallery image ${index + 1}"
                  class="absolute inset-0 h-full w-full object-cover pointer-events-none"
                  loading="lazy"
                />
                <button
                  type="button"
                  class="absolute end-2 top-2 z-20 flex h-7 w-7 items-center justify-center rounded-full bg-white/90 text-stone-600 border border-stone-200 transition hover:bg-stone-100"
                  @click="${(event) => this._handleRemoveImageButtonClick(event, index)}"
                  aria-label="Remove image ${index + 1}"
                >
                  <div class="svg-icon size-6 bg-stone-700 hover:bg-stone-900 icon-close"></div>
                </button>
              </div>
            `,
          )}
          ${this._renderAddTile()}
        </div>

        <input
          type="file"
          id="${this._fileInputId}"
          class="hidden"
          accept=".svg,.png,.jpg,.jpeg,.gif,.webp,.tif,.tiff"
          multiple
          ?disabled=${this._isUploading}
          @change="${this._handleFileChange}"
        />

        ${this.fieldName
          ? this.images.map(
              (imageUrl) => html`<input type="hidden" name="${this.fieldName}[]" value="${imageUrl}" />`,
            )
          : ""}
      </div>
    `;
  }
}

customElements.define("gallery-field", GalleryField);
