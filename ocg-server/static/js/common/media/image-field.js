import { html, nothing } from "lit";
import { showErrorAlert } from "/static/js/common/alerts.js";
import { getElementById } from "/static/js/common/dom.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { ImageCropper } from "/static/js/common/media/image-cropper.js";
import {
  CROP_IMAGE_ACCEPTED_FORMATS,
  CROP_IMAGE_SUPPORTED_FORMATS_TEXT,
  DEFAULT_IMAGE_ACCEPTED_FORMATS,
  getImageUploadErrorMessage,
  IMAGE_UPLOAD_ERROR_DETAILS,
  IMAGE_UPLOAD_MAX_SIZE_TEXT,
  IMAGE_UPLOAD_SUPPORTED_FORMATS_TEXT,
  OPEN_GRAPH_IMAGE_ACCEPTED_FORMATS,
  OPEN_GRAPH_IMAGE_SUPPORTED_FORMATS_TEXT,
  uploadImageFile,
} from "/static/js/common/media/image-upload.js";
import "/static/js/common/svg-spinner.js";

const GIF_IMAGE_ERROR_MESSAGE =
  "GIF images cannot be cropped because their animation would be lost. " +
  "Choose a static SVG, PNG, JPEG or WEBP image.";
const IMAGE_KIND = {
  AVATAR: "avatar",
  BANNER: "banner",
  LOGO: "logo",
};
const IMAGE_TARGET = {
  BADGE: "badge",
  OPEN_GRAPH: "open_graph",
};

/**
 * ImageField renders upload controls with drag-and-drop support and a preview.
 * Keeps banner and avatar variants aligned with the rest of the dashboard form.
 */
export class ImageField extends LitWrapper {
  /**
   * Lit properties / attributes exposed by the component.
   * @property {string} label - Visible label for the field.
   * @property {string} name - Form field name used for submissions.
   * @property {string} value - Current image URL saved in the form.
   * @property {boolean} required - Whether the hidden input is required.
   * @property {string} inputId - Optional override for the hidden input id attribute.
   * @property {string} imageKind - Determines which styling preset (avatar/banner) to apply.
   * @property {string} previewBgClass - Optional utility class to override the preview background (e.g., "bg-stone-900").
   * @property {string} helpPrefixText - Optional text shown before the built-in helper copy.
   * @property {boolean} hideUploadButton - Whether to hide the secondary upload button.
   * @property {boolean} hideRemoveButton - Whether to hide the remove image button.
   * @property {string} acceptedFormats - Optional accepted file formats.
   * @property {string} cropTarget - Optional client-side crop dimension target.
   * @property {boolean} directUpload - Whether to submit the selected file with the parent form.
   * @property {string} helpText - Optional replacement for the default help text.
   * @property {string} submitLabel - Optional label for a form submit action.
   * @property {string} target - Upload target and default crop dimension target.
   * @property {string} legend - Optional legend text displayed under the image preview area.
   */
  static properties = {
    label: { type: String },
    name: { type: String },
    value: { type: String },
    required: { type: Boolean },
    inputId: { type: String, attribute: "input-id" },
    imageKind: { type: String, attribute: "image-kind" },
    previewBgClass: { type: String, attribute: "preview-bg-class" },
    helpPrefixText: { type: String, attribute: "help-prefix-text" },
    hideUploadButton: { type: Boolean, attribute: "hide-upload-button" },
    hideRemoveButton: { type: Boolean, attribute: "hide-remove-button" },
    acceptedFormats: { type: String, attribute: "accepted-formats" },
    cropTarget: { type: String, attribute: "crop-target" },
    directUpload: { type: Boolean, attribute: "direct-upload" },
    helpText: { type: String, attribute: "help-text" },
    submitLabel: { type: String, attribute: "submit-label" },
    target: { type: String },
    legend: { type: String },
    _isPreparing: { state: true },
    _pendingUploadFile: { state: true },
  };

  constructor() {
    super();
    this.label = "Image";
    this.name = "";
    this.value = "";
    this.required = false;
    this.inputId = "";
    this.imageKind = IMAGE_KIND.AVATAR;
    this._filePickerTrigger = null;
    this._filePreparationToken = 0;
    this._isDragActive = false;
    this._isPreparing = false;
    this._isUploading = false;
    this._pendingUploadFile = null;
    this._uniqueId = `image-field-${Math.random().toString(36).slice(2, 9)}`;
    this.previewBgClass = "";
    this.helpPrefixText = "";
    this.hideUploadButton = false;
    this.hideRemoveButton = false;
    this.acceptedFormats = "";
    this.cropTarget = "";
    this.directUpload = false;
    this.helpText = "";
    this.submitLabel = "";
    this.target = "";
    this.legend = "";
    this._directFileName = "";
  }

  /** Invalidate pending file preparation when the field leaves the document. */
  disconnectedCallback() {
    this._filePreparationToken += 1;
    this._isPreparing = false;
    super.disconnectedCallback();
  }

  get _valueInputId() {
    if (this.inputId && this.inputId.length > 0) {
      return this.inputId;
    }
    if (this.name && this.name.length > 0) {
      return this.name;
    }
    return `${this._uniqueId}-value`;
  }

  get _fileInputId() {
    return `${this._uniqueId}-file`;
  }

  get _cropperId() {
    return `${this._uniqueId}-cropper`;
  }

  get _hasImage() {
    return typeof this.value === "string" && this.value.trim().length > 0;
  }

  get _isPending() {
    return this._isPreparing || this._isUploading;
  }

  /** Return a dashboard-safe preview URL for unsaved badge artwork. */
  get _previewUrl() {
    if (this.target === IMAGE_TARGET.BADGE && this.value.startsWith("/images/badges/")) {
      return this.value.replace("/images/badges/", "/images/");
    }
    return this.value;
  }

  /** Size and format guidance matching the formats the field actually accepts. */
  get _uploadErrorDetails() {
    if (this.target === IMAGE_TARGET.OPEN_GRAPH || this.target === IMAGE_TARGET.BADGE) {
      return `${IMAGE_UPLOAD_MAX_SIZE_TEXT} ${OPEN_GRAPH_IMAGE_SUPPORTED_FORMATS_TEXT}`;
    }
    if (ImageCropper.hasRequiredSize(this.cropTarget || this.target)) {
      return `${IMAGE_UPLOAD_MAX_SIZE_TEXT} ${CROP_IMAGE_SUPPORTED_FORMATS_TEXT}`;
    }
    return IMAGE_UPLOAD_ERROR_DETAILS;
  }

  /**
   * Render either the selected image or the placeholder markup for the kind.
   */
  _renderPlaceholder(isWide) {
    if (this.directUpload && this._directFileName) {
      return html`
        <div class="flex flex-col items-center justify-center gap-2 px-3 text-center">
          <div class="svg-icon ${isWide ? "size-12" : "size-8"} icon-image bg-stone-400"></div>
          <p class="text-xs leading-snug text-stone-500">${this._directFileName}</p>
        </div>
      `;
    }

    if (this._hasImage) {
      return html`
        <img
          src=${this._previewUrl}
          alt="Image preview"
          class=${
            isWide
              ? "h-full w-full object-contain rounded p-1"
              : "max-h-[86px] max-w-[86px] object-contain mx-auto"
          }
          loading="lazy"
        />
      `;
    }

    return html`
      <div
        class="flex flex-col items-center justify-center text-center ${isWide ? "gap-3 px-4" : "gap-2 px-3"}"
      >
        <div class="svg-icon ${isWide ? "size-12" : "size-8"} icon-image bg-stone-400"></div>
        <p class="text-xs text-stone-500 leading-snug">
          ${isWide ? "Click to upload or drag and drop" : "Click or drop image"}
        </p>
      </div>
    `;
  }

  /**
   * Open the native file picker when the preview tile is activated.
   */
  _triggerFilePicker(event) {
    if (this._isPending) {
      return;
    }
    this._filePickerTrigger = event?.currentTarget instanceof HTMLElement ? event.currentTarget : null;
    const input = getElementById(this, this._fileInputId);
    input?.click();
  }

  /**
   * Allow Enter/Space to trigger the hidden file input for accessibility.
   */
  _handlePreviewKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }
    event.preventDefault();
    this._triggerFilePicker(event);
  }

  /**
   * Highlight the drop target while dragging files over the preview.
   */
  _handleDragOver(event) {
    event.preventDefault();
    if (this._isPending) {
      return;
    }
    this._isDragActive = true;
    this.requestUpdate();
  }

  /**
   * Reset drop-target styles when the pointer leaves the preview area.
   */
  _handleDragLeave(event) {
    if (this._isPending) {
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
   * Accept dropped files and initiate the upload flow.
   */
  async _handleDrop(event) {
    event.preventDefault();
    if (this._isPending) {
      return;
    }
    this._isDragActive = false;
    const file = event.dataTransfer?.files?.[0];
    if (!file) {
      return;
    }
    if (this.directUpload) {
      const input = getElementById(this, this._fileInputId);
      if (!input) {
        return;
      }
      const dataTransfer = new DataTransfer();
      dataTransfer.items.add(file);
      input.files = dataTransfer.files;
      input.dispatchEvent(new Event("change", { bubbles: true }));
      return;
    }

    await this._processFile(file, undefined, event.currentTarget);
  }

  /**
   * Forward file selection from the native input to the upload helper.
   */
  async _handleFileChange(event) {
    const input = event.target;
    const file = input.files?.[0];
    if (!file) {
      return;
    }

    if (this.directUpload) {
      this._directFileName = file.name;
      this._filePickerTrigger = null;
      this.requestUpdate();
      return;
    }

    const focusOrigin =
      this._filePickerTrigger ||
      this.querySelector("[data-image-upload-trigger]:not(.hidden)") ||
      this.querySelector("[data-image-upload-preview]");
    this._filePickerTrigger = null;
    await this._processFile(
      file,
      () => {
        input.value = "";
      },
      focusOrigin,
    );
  }

  /**
   * Crop files with mandatory dimensions before starting the upload.
   */
  async _processFile(file, resetCallback, focusOrigin = null) {
    const preparationToken = ++this._filePreparationToken;
    this._pendingUploadFile = null;
    this._isPreparing = true;

    try {
      const cropper = getElementById(this, this._cropperId);
      const isGif = file.type.toLowerCase() === "image/gif" || file.name.toLowerCase().endsWith(".gif");
      if (cropper && isGif) {
        showErrorAlert(GIF_IMAGE_ERROR_MESSAGE, true);
        resetCallback?.();
        return;
      }

      const preparedFile = cropper ? await cropper.edit(file, { focusOrigin }) : file;
      if (preparationToken !== this._filePreparationToken) {
        return;
      }
      if (!preparedFile) {
        resetCallback?.();
        return;
      }

      await this._uploadFile(preparedFile, resetCallback);
    } finally {
      if (preparationToken === this._filePreparationToken) {
        this._isPreparing = false;
      }
    }
  }

  /**
   * Upload the selected file via the authenticated image endpoint.
   */
  async _uploadFile(file, resetCallback) {
    this._isUploading = true;
    this.requestUpdate();
    let uploadSucceeded = false;

    try {
      const imageUrl = await uploadImageFile(file, { target: this.target });
      this._pendingUploadFile = null;
      this.setValue(imageUrl);
      uploadSucceeded = true;
    } catch (error) {
      this._pendingUploadFile = file;
      showErrorAlert(getImageUploadErrorMessage("image", error.message, this._uploadErrorDetails), true);
    } finally {
      this._isUploading = false;
      if (typeof resetCallback === "function") {
        resetCallback();
      }
      this.requestUpdate();
    }

    return uploadSucceeded;
  }

  /** Retry a failed upload without asking the user to repeat the crop. */
  async _retryUpload() {
    if (this._isPending || !this._pendingUploadFile) {
      return;
    }

    const uploadSucceeded = await this._uploadFile(this._pendingUploadFile);
    if (uploadSucceeded) {
      await this.updateComplete;
      const focusTarget =
        this.querySelector("[data-image-upload-trigger]:not(.hidden)") ||
        this.querySelector("[data-image-upload-preview]");
      focusTarget?.focus();
    }
  }

  /**
   * Update the hidden field value and notify surrounding forms of the change.
   */
  setValue(newValue) {
    this.value = newValue || "";
    const valueInput = getElementById(this, this._valueInputId);
    valueInput?.setCustomValidity("");
    this.dispatchEvent(
      new CustomEvent("image-change", {
        detail: { value: this.value },
        bubbles: true,
        composed: true,
      }),
    );
  }

  _handleRemove() {
    if (!this._hasImage || this._isPending) {
      return;
    }

    this.setValue("");
  }

  _handleValueInvalid(event) {
    const message = `${this.label} is required.`;
    event.target.setCustomValidity(message);
  }

  /** Render the direct-submit drop zone used when a parent form owns the upload. */
  _renderDirectUploadField(acceptedFormats) {
    return html`
      <label for=${this._fileInputId} class="form-label">
        ${this.label} ${this.required ? html`<span class="asterisk">*</span>` : ""}
      </label>
      <div class="mt-2">
        <div
          class="relative flex min-h-24 cursor-pointer items-center gap-4 rounded-lg border border-dashed border-stone-300 px-6 text-stone-600 transition-colors hover:border-primary-500 ${
            this._isDragActive ? "border-primary-500 bg-primary-50" : ""
          }"
          role="button"
          tabindex="0"
          aria-label="Upload ${this.label}"
          @click=${this._triggerFilePicker}
          @keydown=${this._handlePreviewKeyDown}
          @dragover=${this._handleDragOver}
          @dragleave=${this._handleDragLeave}
          @drop=${this._handleDrop}
        >
          <div class="svg-icon size-8 shrink-0 icon-image bg-stone-400" aria-hidden="true"></div>
          <p class="text-sm">
            <span class="font-semibold text-primary-600">Click to upload</span>
            ${
              this._directFileName
                ? html`<span> ${this._directFileName}</span>`
                : html`<span> or drag and drop a file</span>`
            }
          </p>
          <input
            type="file"
            id=${this._fileInputId}
            name=${this._directFileName ? this.name : nothing}
            class="hidden"
            accept=${acceptedFormats}
            @change=${this._handleFileChange}
          />
        </div>
      </div>
    `;
  }

  /**
   * Compose the upload UI and wire all interaction hooks.
   */
  render() {
    const valueInputId = this._valueInputId;
    const bannerLikeKinds = [IMAGE_KIND.BANNER];
    const isWide = bannerLikeKinds.includes(this.imageKind);
    const isOpenGraphTarget = this.target === IMAGE_TARGET.OPEN_GRAPH;
    const isBadgeTarget = this.target === IMAGE_TARGET.BADGE;
    const cropTarget = this.cropTarget || this.target;
    const removeDisabled = !this._hasImage || this._isPending;
    const submitDisabled = !this._hasImage || this._isPending;
    const helpPrefixText = (this.helpPrefixText || "").trim();
    const requiresCropping = ImageCropper.hasRequiredSize(cropTarget);
    const supportedFormatsText = requiresCropping
      ? CROP_IMAGE_SUPPORTED_FORMATS_TEXT
      : IMAGE_UPLOAD_SUPPORTED_FORMATS_TEXT;
    const helpText =
      this.helpText.trim() ||
      (isOpenGraphTarget
        ? IMAGE_UPLOAD_MAX_SIZE_TEXT
        : isBadgeTarget
          ? `Images must be 512 x 512 px (square). ${IMAGE_UPLOAD_MAX_SIZE_TEXT} ${OPEN_GRAPH_IMAGE_SUPPORTED_FORMATS_TEXT}`
          : isWide
            ? `${IMAGE_UPLOAD_MAX_SIZE_TEXT} ${supportedFormatsText}`
            : `Images must be 360 x 360 px (square). ${IMAGE_UPLOAD_MAX_SIZE_TEXT} ${supportedFormatsText}`);
    const combinedHelpText = helpPrefixText.length > 0 ? `${helpPrefixText} ${helpText}` : helpText;
    const acceptedFormats =
      this.acceptedFormats.trim() ||
      (isOpenGraphTarget || isBadgeTarget
        ? OPEN_GRAPH_IMAGE_ACCEPTED_FORMATS
        : requiresCropping
          ? CROP_IMAGE_ACCEPTED_FORMATS
          : DEFAULT_IMAGE_ACCEPTED_FORMATS);

    if (this.directUpload) {
      return this._renderDirectUploadField(acceptedFormats);
    }

    return html`
      <label for=${this._fileInputId} class="form-label">
        ${this.label} ${this.required ? html`<span class="asterisk">*</span>` : ""}
      </label>
      <div class="mt-3 flex flex-col gap-4 items-stretch sm:flex-row">
        <div
          class="relative ${
            isWide ? "w-full sm:max-w-md h-24" : "size-24"
          } min-w-24 flex items-center justify-center bg-stone-200/50 rounded-lg border border-dashed border-stone-300 overflow-hidden ${
            this._isDragActive && !this._isPending ? "ring-2 ring-primary-300" : ""
          } cursor-pointer ${this.previewBgClass ? ` ${this.previewBgClass}` : ""}"
          role="button"
          tabindex="0"
          aria-label="Upload image"
          aria-busy=${this._isPending ? "true" : "false"}
          aria-disabled=${this._isPending ? "true" : "false"}
          data-image-upload-preview
          @click=${this._triggerFilePicker}
          @keydown=${this._handlePreviewKeyDown}
          @dragover=${this._handleDragOver}
          @dragleave=${this._handleDragLeave}
          @drop=${this._handleDrop}
        >
          <div
            class="absolute inset-0 flex items-center justify-center bg-white/50 z-10 ${
              this._isPending ? "opacity-100" : "opacity-0 pointer-events-none"
            } transition-opacity duration-200"
            aria-hidden=${this._isPending ? "false" : "true"}
          >
            <svg-spinner
              size="size-8"
              background-color="var(--color-primary-100)"
              label=${this._isUploading ? "Uploading..." : "Preparing image..."}
            ></svg-spinner>
          </div>
          ${this._renderPlaceholder(isWide)}
        </div>

        <div class="flex flex-1 flex-col justify-between gap-3">
          <p class="form-legend hidden xl:block">${combinedHelpText}</p>
          <div class="flex flex-wrap gap-3 mb-1">
            <button
              type="button"
              class="btn-primary btn-mini items-center justify-center cursor-pointer whitespace-nowrap text-center h-auto min-h-0 ${
                this.hideUploadButton ? "hidden" : "inline-flex"
              } ${this._isPending ? "opacity-75 pointer-events-none" : ""}"
              data-image-upload-trigger
              aria-label="Upload image for ${this.label}"
              aria-disabled=${this._isPending ? "true" : "false"}
              @click=${this._triggerFilePicker}
            >
              Upload image
            </button>
            <input
              type="file"
              id=${this._fileInputId}
              class="hidden"
              accept=${acceptedFormats}
              @change=${this._handleFileChange}
              ?disabled=${this._isPending}
            />
            ${
              this._pendingUploadFile
                ? html`
                    <button
                      type="button"
                      class="btn-primary-outline btn-mini inline-flex items-center justify-center whitespace-nowrap text-center h-auto min-h-0 ${
                        this._isPending ? "opacity-75 pointer-events-none" : ""
                      }"
                      aria-label="Retry upload for ${this.label}"
                      aria-disabled=${this._isPending ? "true" : "false"}
                      @click=${this._retryUpload}
                    >
                      Retry upload
                    </button>
                  `
                : nothing
            }
            ${
              this.submitLabel
                ? html`
                    <button
                      type="submit"
                      class="btn-primary btn-mini inline-flex items-center justify-center whitespace-nowrap text-center h-auto min-h-0"
                      ?disabled=${submitDisabled}
                      title=${submitDisabled ? "Upload an image first." : ""}
                    >
                      ${this.submitLabel}
                    </button>
                  `
                : ""
            }
            ${
              this.hideRemoveButton
                ? ""
                : html`
                    <button
                      type="button"
                      class="btn-primary-outline btn-mini inline-flex items-center justify-center whitespace-nowrap text-center h-auto min-h-0 ${
                        removeDisabled ? "cursor-not-allowed opacity-60" : "enabled:cursor-pointer"
                      }"
                      ?disabled=${removeDisabled}
                      @click=${this._handleRemove}
                    >
                      Remove image
                    </button>
                  `
            }
          </div>
        </div>
      </div>
      ${this.legend ? html`<p class="form-legend mt-2">${this.legend}</p>` : ""}
      <input
        type="text"
        id=${valueInputId}
        name=${this.name || valueInputId}
        class="sr-only"
        .value=${this.value}
        ?required=${this.required}
        tabindex="-1"
        aria-hidden="true"
        @invalid=${this._handleValueInvalid}
      />
      ${
        requiresCropping
          ? html`
              <image-cropper id=${this._cropperId} .label=${this.label} .target=${cropTarget}></image-cropper>
            `
          : nothing
      }
    `;
  }
}

customElements.define("image-field", ImageField);
