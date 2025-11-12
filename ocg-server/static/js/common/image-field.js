import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { isSuccessfulXHRStatus } from "/static/js/common/common.js";
import { showErrorAlert, showSuccessAlert } from "/static/js/common/alerts.js";

const IMAGE_KIND = {
  AVATAR: "avatar",
  BANNER: "banner",
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
   */
  static properties = {
    label: { type: String },
    name: { type: String },
    value: { type: String },
    required: { type: Boolean },
    inputId: { type: String, attribute: "input-id" },
    imageKind: { type: String, attribute: "image-kind" },
  };

  constructor() {
    super();
    this.label = "Image";
    this.name = "";
    this.value = "";
    this.required = false;
    this.inputId = "";
    this.imageKind = IMAGE_KIND.AVATAR;
    this._isUploading = false;
    this._isDragActive = false;
    this._uniqueId = `image-field-${Math.random().toString(36).slice(2, 9)}`;
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

  get _hasImage() {
    return typeof this.value === "string" && this.value.trim().length > 0;
  }

  /**
   * Render either the selected image or the placeholder markup for the kind.
   */
  _renderPlaceholder(isBanner) {
    if (this._hasImage) {
      return html`
        <img
          src="${this.value}"
          alt="Image preview"
          class="${isBanner
            ? "h-full w-full object-contain rounded p-1"
            : "max-h-[86px] max-w-[86px] object-contain mx-auto"}"
          loading="lazy"
        />
      `;
    }

    return html`
      <div
        class="flex flex-col items-center justify-center text-center ${isBanner
          ? "gap-3 px-4"
          : "gap-2 px-3"}"
      >
        <div class="svg-icon ${isBanner ? "size-16" : "size-8"} icon-image bg-stone-400"></div>
        <p class="text-xs text-stone-500 leading-snug">
          ${isBanner ? "Click to upload or drag and drop" : "Click or drop image"}
        </p>
      </div>
    `;
  }

  /**
   * Open the native file picker when the preview tile is activated.
   */
  _triggerFilePicker() {
    if (this._isUploading) {
      return;
    }
    const input = this.querySelector(`#${this._fileInputId}`);
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
    this._triggerFilePicker();
  }

  /**
   * Highlight the drop target while dragging files over the preview.
   */
  _handleDragOver(event) {
    if (this._isUploading) {
      return;
    }
    event.preventDefault();
    this._isDragActive = true;
    this.requestUpdate();
  }

  /**
   * Reset drop-target styles when the pointer leaves the preview area.
   */
  _handleDragLeave(event) {
    if (this._isUploading) {
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
  _handleDrop(event) {
    if (this._isUploading) {
      return;
    }
    event.preventDefault();
    this._isDragActive = false;
    const file = event.dataTransfer?.files?.[0];
    if (!file) {
      return;
    }
    this._uploadFile(file);
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
    await this._uploadFile(file, () => {
      input.value = "";
    });
  }

  /**
   * Upload the selected file via the authenticated image endpoint.
   */
  async _uploadFile(file, resetCallback) {
    this._isUploading = true;

    const formData = new FormData();
    formData.append("file", file, file.name);

    try {
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

      this._setValue(data.url);
      showSuccessAlert("Image added successfully.");
    } catch (error) {
      const ERROR_MESSAGE =
        'Something went wrong adding the image, please try again later.<br /><br /><div class="text-sm text-stone-500">Images must be at least 400x400, preferably in square format. Maximum file size: 2MB. Formats supported: SVG, PNG, JPEG, GIF, WEBP and TIFF.</div>';
      showErrorAlert(ERROR_MESSAGE, true);
    } finally {
      this._isUploading = false;
      if (typeof resetCallback === "function") {
        resetCallback();
      }
      this.requestUpdate();
    }
  }

  /**
   * Update the hidden field value and notify surrounding forms of the change.
   */
  _setValue(newValue) {
    this.value = newValue || "";
    this.dispatchEvent(
      new CustomEvent("image-change", {
        detail: { value: this.value },
        bubbles: true,
        composed: true,
      }),
    );
  }

  _handleRemove() {
    if (!this._hasImage || this._isUploading) {
      return;
    }

    this._setValue("");
  }

  /**
   * Compose the upload UI and wire all interaction hooks.
   */
  render() {
    const valueInputId = this._valueInputId;
    const kind = this.imageKind === IMAGE_KIND.BANNER ? IMAGE_KIND.BANNER : IMAGE_KIND.AVATAR;
    const isBanner = kind === IMAGE_KIND.BANNER;
    const removeDisabled = !this._hasImage || this._isUploading;

    return html`
      <label for="${this._fileInputId}" class="form-label">
        ${this.label} ${this.required ? html`<span class="asterisk">*</span>` : ""}
      </label>
      <div class="mt-3 flex flex-col gap-4 items-stretch sm:flex-row">
        <div
          class="relative ${isBanner
            ? "w-full sm:max-w-md h-24"
            : "size-24"} min-w-24 flex items-center justify-center bg-stone-200/50 rounded-lg border border-dashed border-stone-300 overflow-hidden ${this
            ._isDragActive && !this._isUploading
            ? "ring-2 ring-primary-300"
            : ""} cursor-pointer"
          role="button"
          tabindex="0"
          aria-label="Upload image"
          @click="${this._triggerFilePicker}"
          @keydown="${this._handlePreviewKeyDown}"
          @dragover="${this._handleDragOver}"
          @dragleave="${this._handleDragLeave}"
          @drop="${this._handleDrop}"
        >
          <div
            class="absolute inset-0 flex items-center justify-center bg-white/80 ${this._isUploading
              ? "opacity-100"
              : "opacity-0 pointer-events-none"} transition-opacity duration-200"
          >
            <div role="status" class="flex size-8">
              <img
                src="/static/images/spinner/spinner_4.svg"
                height="auto"
                width="auto"
                alt="Loading spinner"
                class="size-auto animate-spin"
              />
              <span class="sr-only">Uploading...</span>
            </div>
          </div>
          ${this._renderPlaceholder(isBanner)}
        </div>

        <div class="flex flex-1 flex-col justify-between gap-3">
          <p class="form-legend hidden xl:block">
            ${isBanner
              ? "Images must be at least 1200x600 in a wide ratio (16:9 or 3:1). Maximum size: 2MB. Supported formats: SVG, PNG, JPEG, GIF, WEBP and TIFF."
              : "Images must be at least 400x400 (square). Maximum size: 2MB. Supported formats: SVG, PNG, JPEG, GIF, WEBP and TIFF."}
          </p>
          <div class="flex flex-wrap gap-3 mt-auto">
            <label
              class="btn-primary btn-mini inline-flex items-center justify-center cursor-pointer whitespace-nowrap text-center h-auto min-h-0 ${this
                ._isUploading
                ? "opacity-75 pointer-events-none"
                : ""}"
            >
              <input
                type="file"
                id="${this._fileInputId}"
                class="hidden"
                accept=".svg,.png,.jpg,.jpeg,.gif,.webp,.tif,.tiff"
                @change="${this._handleFileChange}"
                ?disabled=${this._isUploading}
              />
              Upload image
            </label>
            <button
              type="button"
              class="btn-primary-outline btn-mini inline-flex items-center justify-center whitespace-nowrap text-center h-auto min-h-0 ${removeDisabled
                ? "cursor-not-allowed opacity-60"
                : "enabled:cursor-pointer"}"
              ?disabled=${removeDisabled}
              @click="${this._handleRemove}"
            >
              Remove image
            </button>
          </div>
        </div>
      </div>
      <input
        type="hidden"
        id="${valueInputId}"
        name="${this.name || valueInputId}"
        .value="${this.value}"
        ?required=${this.required}
        readonly
      />
    `;
  }
}

customElements.define("image-field", ImageField);
