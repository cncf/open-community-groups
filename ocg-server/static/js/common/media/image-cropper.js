import { html, nothing } from "lit";
import { showErrorAlert } from "/static/js/common/alerts.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import {
  bindModalDismissListeners,
  closeModalBodyScroll,
  openModalBodyScroll,
} from "/static/js/common/modals/modal-lifecycle.js";
import Cropper from "/static/vendor/js/cropper.v2.1.1.min.js";
import "/static/js/common/svg-spinner.js";

const CROPPER_TEMPLATE = `
  <cropper-canvas background aria-hidden="true">
    <cropper-image scalable translatable></cropper-image>
    <cropper-shade hidden></cropper-shade>
    <cropper-handle action="move" plain></cropper-handle>
    <cropper-selection outlined precise theme-color="var(--color-primary-500)">
      <cropper-grid covered></cropper-grid>
      <cropper-crosshair centered></cropper-crosshair>
      <span
        class="pointer-events-none absolute left-0 top-0 size-[10px] border-l-2 border-t-2 border-primary-500"
        data-cropper-corner
      ></span>
      <span
        class="pointer-events-none absolute right-0 top-0 size-[10px] border-r-2 border-t-2 border-primary-500"
        data-cropper-corner
      ></span>
      <span
        class="pointer-events-none absolute bottom-0 left-0 size-[10px] border-b-2 border-l-2 border-primary-500"
        data-cropper-corner
      ></span>
      <span
        class="pointer-events-none absolute bottom-0 right-0 size-[10px] border-b-2 border-r-2 border-primary-500"
        data-cropper-corner
      ></span>
    </cropper-selection>
  </cropper-canvas>
`;
const CROP_BOUNDARY_TOLERANCE = 0.1;
const FOCUSABLE_SELECTOR = 'button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])';
const IMAGE_TARGET_SIZES = Object.freeze({
  ad_banner: Object.freeze({ height: 300, width: 2400 }),
  banner: Object.freeze({ height: 192, width: 2428 }),
  banner_mobile: Object.freeze({ height: 192, width: 1220 }),
  logo: Object.freeze({ height: 360, width: 360 }),
  open_graph: Object.freeze({ height: 630, width: 1200 }),
});
const MAX_OUTPUT_SIZE_BYTES = 1_000_000;
const OUTPUT_QUALITIES = [0.92, 0.82, 0.72, 0.62, 0.52];
const OUTPUT_SIZE_ERROR_MESSAGE =
  "The cropped image is still larger than the 1MB limit. Try a different image.";
const OUTPUT_TYPE_EXTENSIONS = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};
const PAN_STEP = 8;
const STATUS = {
  ERROR: "error",
  LOADING: "loading",
  PROCESSING: "processing",
  READY: "ready",
};
const SVG_ABSOLUTE_LENGTH_PATTERN = /^([+]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?)(cm|in|mm|pc|pt|px|q)?$/i;
const SVG_LENGTH_UNIT_TO_PIXELS = Object.freeze({
  cm: 96 / 2.54,
  in: 96,
  mm: 96 / 25.4,
  pc: 16,
  pt: 96 / 72,
  px: 1,
  q: 96 / 101.6,
});

/**
 * ImageCropper owns the modal workflow for mandatory image dimensions.
 */
export class ImageCropper extends LitWrapper {
  static properties = {
    label: { type: String },
    target: { type: String },
    _errorMessage: { state: true },
    _isOpen: { state: true },
    _status: { state: true },
    _zoomPercent: { state: true },
  };

  /** Initialize editor state, tokens, and document-level handler bindings. */
  constructor() {
    super();
    this.label = "Image";
    this.target = "";
    this._cropper = null;
    this._cropperImage = null;
    this._editToken = 0;
    this._errorMessage = "";
    this._focusOrigin = null;
    this._isOpen = false;
    this._initialImageScale = 1;
    this._initialImageTransform = null;
    this._objectUrl = "";
    this._removeDismissListeners = null;
    this._resolveEdit = null;
    this._selection = null;
    this._sourceFile = null;
    this._status = STATUS.LOADING;
    this._uniqueId = `image-cropper-${Math.random().toString(36).slice(2, 9)}`;
    this._wasTransformRejected = false;
    this._zoomPercent = 100;
    this._handleDocumentKeyDown = this._handleDocumentKeyDown.bind(this);
    this._handleImageTransform = this._handleImageTransform.bind(this);
  }

  /**
   * Return whether the upload target has mandatory output dimensions.
   * @param {string} target Image upload target.
   * @returns {boolean} Whether the target requires cropping.
   */
  static hasRequiredSize(target) {
    return Object.hasOwn(IMAGE_TARGET_SIZES, target);
  }

  /** Cancel any active edit and release modal resources when removed. */
  disconnectedCallback() {
    this._close(null, { restoreFocus: false });
    super.disconnectedCallback();
  }

  /**
   * Prepare a selected file, opening the editor only when cropping is required.
   * @param {File} file Selected source image.
   * @param {Object} [options={}] Editor options.
   * @param {HTMLElement|null} [options.focusOrigin=null] Control that opened the editor.
   * @returns {Promise<File|null>} Edited file, or null when cancelled.
   */
  async edit(file, { focusOrigin = null } = {}) {
    const requiredSize = this._requiredSize;
    if (!requiredSize) {
      return file;
    }

    if (this._resolveEdit) {
      this._close(null, { restoreFocus: false });
    }

    const editToken = ++this._editToken;
    let decodedImage;

    try {
      decodedImage = await this._decodeImage(file);
    } catch {
      if (!this.isConnected || editToken !== this._editToken) {
        return null;
      }
      return this._openEditor(file, { focusOrigin });
    }

    try {
      if (!this.isConnected || editToken !== this._editToken) {
        return null;
      }

      const sourceSize = decodedImage.size;
      const requiresUpscaling =
        sourceSize.width < requiredSize.width || sourceSize.height < requiredSize.height;
      if (requiresUpscaling) {
        if (focusOrigin instanceof HTMLElement && document.contains(focusOrigin)) {
          focusOrigin.focus();
        }
        showErrorAlert(
          `The selected image (${sourceSize.width} × ${sourceSize.height} px) is smaller ` +
            `than the required size (${requiredSize.width} × ${requiredSize.height} px). ` +
            "Please choose a larger image.",
        );
        return null;
      }

      const hasRequiredDimensions =
        sourceSize.width === requiredSize.width && sourceSize.height === requiredSize.height;
      const canUploadWithoutProcessing =
        hasRequiredDimensions &&
        file.size <= MAX_OUTPUT_SIZE_BYTES &&
        Object.hasOwn(OUTPUT_TYPE_EXTENSIONS, file.type.toLowerCase());
      if (canUploadWithoutProcessing) {
        return file;
      }

      const hasRequiredAspectRatio =
        sourceSize.width * requiredSize.height === sourceSize.height * requiredSize.width;
      if (hasRequiredAspectRatio) {
        try {
          const resizedFile = await this._resizeImage(decodedImage.image, file);
          if (!this.isConnected || editToken !== this._editToken) {
            return null;
          }
          return resizedFile;
        } catch {
          // Fall through to the editor so automatic processing failures stay recoverable.
        }
      }
    } finally {
      URL.revokeObjectURL(decodedImage.objectUrl);
    }

    if (!this.isConnected || editToken !== this._editToken) {
      return null;
    }
    return this._openEditor(file, { focusOrigin });
  }

  /** Decode a source file for dimension checks and automatic resizing. */
  async _decodeImage(file) {
    const image = new Image();
    const objectUrl = URL.createObjectURL(file);

    try {
      await new Promise((resolve, reject) => {
        image.addEventListener("load", resolve, { once: true });
        image.addEventListener("error", reject, { once: true });
        image.src = objectUrl;
      });
      return {
        image,
        objectUrl,
        size: await this._getSourceSize(file, image),
      };
    } catch (error) {
      URL.revokeObjectURL(objectUrl);
      throw error;
    }
  }

  /** Read raster dimensions or an SVG's explicit dimensions and view box. */
  async _getSourceSize(file, image) {
    const fileName = file.name.toLowerCase();
    const fileType = file.type.toLowerCase();
    if (fileType !== "image/svg+xml" && !fileName.endsWith(".svg")) {
      return { height: image.naturalHeight, width: image.naturalWidth };
    }

    const documentElement = new DOMParser().parseFromString(
      await file.text(),
      "image/svg+xml",
    ).documentElement;
    const explicitHeight = parseSvgAbsoluteLength(documentElement.getAttribute("height"));
    const explicitWidth = parseSvgAbsoluteLength(documentElement.getAttribute("width"));
    const viewBox = (documentElement.getAttribute("viewBox") || "")
      .trim()
      .split(/[\s,]+/)
      .map(Number);
    const viewBoxHeight = viewBox.length === 4 ? viewBox[3] : 0;
    const viewBoxWidth = viewBox.length === 4 ? viewBox[2] : 0;
    const hasExplicitHeight = explicitHeight !== null;
    const hasExplicitWidth = explicitWidth !== null;
    const hasViewBox = viewBoxWidth > 0 && viewBoxHeight > 0;

    if (hasExplicitHeight && hasExplicitWidth) {
      return { height: explicitHeight, width: explicitWidth };
    }
    if (hasExplicitWidth && hasViewBox) {
      return { height: (explicitWidth * viewBoxHeight) / viewBoxWidth, width: explicitWidth };
    }
    if (hasExplicitHeight && hasViewBox) {
      return { height: explicitHeight, width: (explicitHeight * viewBoxWidth) / viewBoxHeight };
    }
    if (hasViewBox) {
      return { height: viewBoxHeight, width: viewBoxWidth };
    }
    return { height: image.naturalHeight, width: image.naturalWidth };
  }

  /** Open the interactive editor for a source whose aspect ratio must change. */
  _openEditor(file, { focusOrigin = null } = {}) {
    this._errorMessage = "";
    this._focusOrigin =
      focusOrigin instanceof HTMLElement
        ? focusOrigin
        : document.activeElement instanceof HTMLElement
          ? document.activeElement
          : null;
    this._isOpen = openModalBodyScroll(this._isOpen);
    this._objectUrl = URL.createObjectURL(file);
    this._sourceFile = file;
    this._status = STATUS.LOADING;
    this._removeDismissListeners = bindModalDismissListeners({
      onKeydown: this._handleDocumentKeyDown,
    });

    const result = new Promise((resolve) => {
      this._resolveEdit = resolve;
    });

    this.updateComplete.then(() => {
      this.querySelector("[data-image-cropper-stage]")?.focus();
    });

    return result;
  }

  /** Mandatory output dimensions for the current target, or null when not croppable. */
  get _requiredSize() {
    return IMAGE_TARGET_SIZES[this.target] || null;
  }

  /** Export the selection at the required size and resolve the edit with the file. */
  async _applyCrop() {
    if (this._status !== STATUS.READY || !this._selection || !this._requiredSize) {
      return;
    }

    const editToken = this._editToken;
    this._errorMessage = "";
    this._status = STATUS.PROCESSING;
    this._setCropperDisabled(true);

    try {
      const canvas = await this._selection.$toCanvas({
        height: this._requiredSize.height,
        width: this._requiredSize.width,
      });
      const outputFile = await this._createOutputFile(canvas, this._sourceFile);

      if (this._isOpen && editToken === this._editToken) {
        this._close(outputFile);
      }
    } catch (error) {
      if (this._isOpen && editToken === this._editToken) {
        this._setCropperDisabled(false);
        // Keep the actionable size-limit copy; other failures get generic retry guidance.
        this._errorMessage =
          error instanceof Error && error.message === OUTPUT_SIZE_ERROR_MESSAGE
            ? OUTPUT_SIZE_ERROR_MESSAGE
            : "We couldn't prepare this image. Adjust the crop and try again.";
        this._status = STATUS.READY;
      }
    }
  }

  /** Encode a canvas as a blob, rejecting when the browser cannot export it. */
  async _canvasToBlob(canvas, type, quality) {
    return new Promise((resolve, reject) => {
      canvas.toBlob(
        (blob) => {
          if (blob) {
            resolve(blob);
          } else {
            reject(new Error("Image export failed"));
          }
        },
        type,
        quality,
      );
    });
  }

  /** Scale and center the source image around the fixed crop selection. */
  _centerImageOnSelection() {
    if (!this._cropperImage || !this._selection) {
      return;
    }

    this._cropperImage.$resetTransform().$center("contain");
    const imageRect = this._cropperImage.getBoundingClientRect();
    const selectionRect = this._selection.getBoundingClientRect();
    if (
      imageRect.width <= 0 ||
      imageRect.height <= 0 ||
      selectionRect.width <= 0 ||
      selectionRect.height <= 0
    ) {
      return;
    }

    const selectionScale = Math.max(
      selectionRect.width / imageRect.width,
      selectionRect.height / imageRect.height,
    );
    this._cropperImage.$scale(selectionScale);
    this._initialImageTransform = this._cropperImage.$getTransform();
    const [scaleX, scaleY] = this._initialImageTransform;
    this._initialImageScale = Math.hypot(scaleX, scaleY);
    this._zoomPercent = 100;
  }

  /** Resolve the pending edit, tear down modal state, and restore the opener's focus. */
  _close(result, { restoreFocus = true } = {}) {
    const wasOpen = this._isOpen;
    const resolveEdit = this._resolveEdit;
    const focusOrigin = this._focusOrigin;

    this._editToken += 1;
    this._destroyCropper();
    this._isOpen = closeModalBodyScroll(this._isOpen);
    this._removeDismissListeners?.();
    this._removeDismissListeners = null;
    this._resolveEdit = null;
    this._sourceFile = null;
    this._focusOrigin = null;
    this._errorMessage = "";

    if (this._objectUrl) {
      URL.revokeObjectURL(this._objectUrl);
      this._objectUrl = "";
    }

    resolveEdit?.(result);

    if (wasOpen && restoreFocus && focusOrigin && document.contains(focusOrigin)) {
      this.updateComplete.then(() => {
        focusOrigin.focus();
      });
    }
  }

  /**
   * Build the upload file from the cropped canvas. Keeps the source type when
   * supported and falls back to WEBP at decreasing qualities to fit the limit.
   */
  async _createOutputFile(canvas, sourceFile) {
    const sourceType = sourceFile?.type.toLowerCase();
    const preferredType = Object.hasOwn(OUTPUT_TYPE_EXTENSIONS, sourceType) ? sourceType : "image/webp";
    let outputType = preferredType;
    let blob = await this._canvasToBlob(canvas, outputType, OUTPUT_QUALITIES[0]);

    if (blob.size > MAX_OUTPUT_SIZE_BYTES) {
      outputType = "image/webp";
      for (const quality of OUTPUT_QUALITIES) {
        blob = await this._canvasToBlob(canvas, outputType, quality);
        if (blob.size <= MAX_OUTPUT_SIZE_BYTES) {
          break;
        }
      }
    }

    if (blob.size > MAX_OUTPUT_SIZE_BYTES) {
      throw new Error(OUTPUT_SIZE_ERROR_MESSAGE);
    }

    const sourceName = sourceFile?.name || "image";
    const baseName = sourceName.replace(/\.[^.]+$/, "") || "image";
    const extension = OUTPUT_TYPE_EXTENSIONS[outputType];

    return new File([blob], `${baseName}-cropped.${extension}`, {
      lastModified: Date.now(),
      type: outputType,
    });
  }

  /** Resize a decoded image to the mandatory output dimensions without cropping. */
  async _resizeImage(image, sourceFile) {
    const canvas = document.createElement("canvas");
    canvas.height = this._requiredSize.height;
    canvas.width = this._requiredSize.width;
    const context = canvas.getContext("2d");
    if (!context) {
      throw new Error("Image canvas is unavailable");
    }
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    return this._createOutputFile(canvas, sourceFile);
  }

  /** Detach vendor listeners and drop the cropper instance references. */
  _destroyCropper() {
    this._cropperImage?.removeEventListener("transform", this._handleImageTransform);
    this._cropper?.destroy();
    this._cropper = null;
    this._cropperImage = null;
    this._initialImageTransform = null;
    this._selection = null;
  }

  /** Close on Escape and keep Tab focus inside the dialog while it is open. */
  _handleDocumentKeyDown(event) {
    if (!this._isOpen) {
      return;
    }

    if (isEscapeEvent(event)) {
      event.preventDefault();
      this._close(null);
      return;
    }

    if (event.key === "Tab") {
      this._trapFocus(event);
    }
  }

  /** Surface a source image load failure for the active edit session. */
  _handleImageError(event) {
    // Ignore stale error events from closed sessions or replaced image elements.
    if (event && !this._isActiveSourceImage(event.currentTarget)) {
      return;
    }

    this._errorMessage =
      "This image couldn't be opened in the editor. Choose a different image in a supported format.";
    this._status = STATUS.ERROR;
  }

  /** Initialize the vendored cropper once the source image has been decoded. */
  async _handleImageLoad(event) {
    if (!this._isActiveSourceImage(event.currentTarget)) {
      return;
    }

    const sourceImage = event.currentTarget;
    const requiredSize = this._requiredSize;
    if (
      requiredSize &&
      (sourceImage.naturalWidth < requiredSize.width || sourceImage.naturalHeight < requiredSize.height)
    ) {
      const errorMessage =
        `The selected image (${sourceImage.naturalWidth} × ${sourceImage.naturalHeight} px) is smaller ` +
        `than the required size (${requiredSize.width} × ${requiredSize.height} px). ` +
        "Please choose a larger image.";
      this._close(null);
      await this.updateComplete;
      showErrorAlert(errorMessage);
      return;
    }

    const container = this.querySelector("[data-image-cropper-container]");
    if (!container) {
      return;
    }

    const editToken = this._editToken;
    let cropper = null;

    try {
      cropper = new Cropper(event.currentTarget, {
        container,
        template: CROPPER_TEMPLATE,
      });

      const cropperCanvas = cropper.getCropperCanvas();
      const cropperImage = cropper.getCropperImage();
      const selection = cropper.getCropperSelection();

      if (!cropperCanvas || !cropperImage || !selection) {
        throw new Error("Cropper initialization failed");
      }

      this._cropper = cropper;
      this._cropperImage = cropperImage;
      this._selection = selection;
      cropperCanvas.style.height = "100%";
      cropperCanvas.style.width = "100%";
      await cropperImage.$ready();
      await new Promise((resolve) => requestAnimationFrame(resolve));

      if (!this._isOpen || editToken !== this._editToken || this._cropper !== cropper) {
        cropper.destroy();
        return;
      }

      this._positionSelection(cropperCanvas);
      this._centerImageOnSelection();
      cropperImage.addEventListener("transform", this._handleImageTransform);
      this._status = STATUS.READY;
    } catch {
      // Release the failed vendor instance before surfacing or discarding the error.
      if (this._cropper === cropper) {
        this._destroyCropper();
      } else {
        cropper?.destroy();
      }

      if (this._isOpen && editToken === this._editToken) {
        this._handleImageError();
      }
    }
  }

  /**
   * Keep the selection covered by the image by measuring the proposed transform
   * on an invisible clone and clamping movement on each constrained axis.
   */
  _handleImageTransform(event) {
    const cropperCanvas = this._cropper?.getCropperCanvas();
    if (!cropperCanvas || !this._cropperImage || !this._selection) {
      return;
    }

    const imageClone = this._cropperImage.cloneNode();
    imageClone.style.opacity = "0";
    imageClone.style.transform = `matrix(${event.detail.matrix.join(", ")})`;
    cropperCanvas.append(imageClone);

    const imageRect = imageClone.getBoundingClientRect();
    const selectionRect = this._selection.getBoundingClientRect();
    imageClone.remove();

    const hasMeasurableBounds = imageRect.width > 0 && imageRect.height > 0;
    const isImageTooSmall =
      imageRect.width < selectionRect.width - CROP_BOUNDARY_TOLERANCE ||
      imageRect.height < selectionRect.height - CROP_BOUNDARY_TOLERANCE;
    if (hasMeasurableBounds && isImageTooSmall) {
      this._wasTransformRejected = true;
      event.preventDefault();
      return;
    }

    let horizontalCorrection = 0;
    let verticalCorrection = 0;
    if (selectionRect.left < imageRect.left - CROP_BOUNDARY_TOLERANCE) {
      horizontalCorrection = selectionRect.left - imageRect.left;
    } else if (selectionRect.right > imageRect.right + CROP_BOUNDARY_TOLERANCE) {
      horizontalCorrection = selectionRect.right - imageRect.right;
    }
    if (selectionRect.top < imageRect.top - CROP_BOUNDARY_TOLERANCE) {
      verticalCorrection = selectionRect.top - imageRect.top;
    } else if (selectionRect.bottom > imageRect.bottom + CROP_BOUNDARY_TOLERANCE) {
      verticalCorrection = selectionRect.bottom - imageRect.bottom;
    }

    if (hasMeasurableBounds && (horizontalCorrection !== 0 || verticalCorrection !== 0)) {
      const correctedMatrix = [...event.detail.matrix];
      correctedMatrix[4] += horizontalCorrection;
      correctedMatrix[5] += verticalCorrection;
      event.preventDefault();
      this._cropperImage.removeEventListener("transform", this._handleImageTransform);
      this._cropperImage.$setTransform(correctedMatrix);
      this._cropperImage.addEventListener("transform", this._handleImageTransform);
    }

    const [scaleX, scaleY] = event.detail.matrix;
    const proposedScale = Math.hypot(scaleX, scaleY);
    if (this._initialImageScale > 0 && proposedScale > 0) {
      this._zoomPercent = Math.max(100, Math.round((proposedScale / this._initialImageScale) * 100));
    }
  }

  /** Move the image with the arrow keys and zoom with + or - from the crop stage. */
  _handleStageKeyDown(event) {
    if (this._status !== STATUS.READY || !this._cropperImage) {
      return;
    }

    const movement = {
      ArrowDown: [0, PAN_STEP],
      ArrowLeft: [-PAN_STEP, 0],
      ArrowRight: [PAN_STEP, 0],
      ArrowUp: [0, -PAN_STEP],
    }[event.key];

    if (movement) {
      event.preventDefault();
      this._cropperImage.$move(...movement);
    } else if (event.key === "+" || event.key === "=") {
      event.preventDefault();
      this._zoom(0.1);
    } else if (event.key === "-") {
      event.preventDefault();
      this._zoom(-0.1);
    }
  }

  /** Return whether an image event belongs to the active edit session. */
  _isActiveSourceImage(sourceImage) {
    return (
      this._isOpen &&
      sourceImage instanceof HTMLImageElement &&
      sourceImage.isConnected &&
      sourceImage.src === this._objectUrl
    );
  }

  /** Center the largest selection with the target aspect ratio on the canvas. */
  _positionSelection(cropperCanvas) {
    const canvasRect = cropperCanvas.getBoundingClientRect();
    const aspectRatio = this._requiredSize.width / this._requiredSize.height;
    const maximumWidth = canvasRect.width * 0.9;
    const maximumHeight = canvasRect.height * 0.9;
    let width = maximumWidth;
    let height = width / aspectRatio;

    if (height > maximumHeight) {
      height = maximumHeight;
      width = height * aspectRatio;
    }

    this._selection.aspectRatio = aspectRatio;
    this._selection.$change(
      (canvasRect.width - width) / 2,
      (canvasRect.height - height) / 2,
      width,
      height,
      aspectRatio,
    );
  }

  /** Restore the initial image transform without re-triggering the boundary guard. */
  _resetCrop() {
    if (!this._cropperImage || !this._initialImageTransform) {
      return;
    }

    this._cropperImage.removeEventListener("transform", this._handleImageTransform);
    this._cropperImage.$setTransform(this._initialImageTransform);
    this._cropperImage.addEventListener("transform", this._handleImageTransform);
    this._zoomPercent = 100;
  }

  /** Enable or disable pointer interactions on the vendor crop surface. */
  _setCropperDisabled(isDisabled) {
    const cropperCanvas = this._cropper?.getCropperCanvas();
    if (cropperCanvas) {
      cropperCanvas.disabled = isDisabled;
    }
  }

  /** Keep Tab and Shift+Tab cycling within the dialog's focusable controls. */
  _trapFocus(event) {
    const dialog = this.querySelector("[data-image-cropper-dialog]");
    const focusableElements = [...(dialog?.querySelectorAll(FOCUSABLE_SELECTOR) || [])];
    if (focusableElements.length === 0) {
      return;
    }

    const firstElement = focusableElements[0];
    const lastElement = focusableElements.at(-1);
    if (!focusableElements.includes(document.activeElement)) {
      event.preventDefault();
      (event.shiftKey ? lastElement : firstElement).focus();
    } else if (event.shiftKey && document.activeElement === firstElement) {
      event.preventDefault();
      lastElement.focus();
    } else if (!event.shiftKey && document.activeElement === lastElement) {
      event.preventDefault();
      firstElement.focus();
    }
  }

  /** Zoom the image by the given amount while the editor is ready. */
  _zoom(amount) {
    if (this._status === STATUS.READY && this._cropperImage && (amount >= 0 || this._zoomPercent > 100)) {
      const previousZoomPercent = this._zoomPercent;
      this._wasTransformRejected = false;
      this._cropperImage.$zoom(amount);

      if (!this._wasTransformRejected && this._zoomPercent === previousZoomPercent) {
        const zoomFactor = amount < 0 ? 1 / (1 - amount) : 1 + amount;
        this._zoomPercent = Math.max(100, Math.round(previousZoomPercent * zoomFactor));
      }
    }
  }

  /** Render the modal editor while an edit is open; render nothing when closed. */
  render() {
    if (!this._isOpen || !this._requiredSize) {
      return nothing;
    }

    const isLoading = this._status === STATUS.LOADING;
    const isProcessing = this._status === STATUS.PROCESSING;
    const titleId = `${this._uniqueId}-title`;
    const instructionsId = `${this._uniqueId}-instructions`;
    const zoomLabel = this._zoomPercent === 100 ? "Fit" : `${this._zoomPercent}%`;

    return html`
      <div
        class="fixed inset-0 z-1300 flex items-center justify-center overflow-y-auto overflow-x-hidden"
        role="dialog"
        aria-modal="true"
        aria-labelledby=${titleId}
        aria-describedby=${instructionsId}
        data-image-cropper-dialog
      >
        <div
          class="modal-overlay absolute w-full h-full bg-stone-950 opacity-[0.35]"
          @click=${() => this._close(null)}
        ></div>

        <div class="modal-panel max-w-4xl p-4">
          <div class="modal-card rounded-lg">
            <div class="flex items-center justify-between gap-3 border-b border-stone-200 rounded-t p-5">
              <div class="min-w-0">
                <h2 id=${titleId} class="text-lg font-semibold text-stone-900">Crop ${this.label}</h2>
                <p class="mt-2 flex flex-wrap items-center gap-2 text-sm text-stone-500">
                  <span>Required size</span>
                  <span
                    class="custom-badge bg-stone-50 px-2.5 py-1 text-sm font-semibold normal-case text-stone-700"
                  >
                    ${this._requiredSize.width} × ${this._requiredSize.height} px
                  </span>
                </p>
              </div>
              <button
                type="button"
                class="group shrink-0 text-stone-400 bg-transparent hover:bg-stone-200 hover:text-stone-900 transition-colors rounded-lg text-sm w-10 h-10 inline-flex justify-center items-center"
                aria-label="Close image editor"
                @click=${() => this._close(null)}
              >
                <div
                  class="svg-icon w-6 h-6 bg-stone-500 group-hover:bg-stone-900 transition-colors icon-close"
                  aria-hidden="true"
                ></div>
              </button>
            </div>

            <div class="modal-body p-5">
              <div
                id=${instructionsId}
                class="mb-3 rounded-lg border border-stone-200 bg-stone-50 px-4 py-3 text-sm text-stone-700"
              >
                <p class="leading-6">
                  Animation is not preserved. Drag the image to position it. Use the arrow keys to move and
                  <kbd
                    class="mx-1 inline-flex min-w-6 items-center justify-center rounded-md border border-stone-300 bg-white px-1.5 py-0.5 font-sans text-xs font-semibold leading-4 text-stone-700 shadow-sm"
                    >+</kbd
                  >
                  /
                  <kbd
                    class="mx-1 inline-flex min-w-6 items-center justify-center rounded-md border border-stone-300 bg-white px-1.5 py-0.5 font-sans text-xs font-semibold leading-4 text-stone-700 shadow-sm"
                    >−</kbd
                  >
                  to zoom.
                </p>
              </div>
              <div
                class="relative h-[500px] md:h-[600px] w-full overflow-hidden rounded-lg bg-stone-900 focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-stone-400"
                role="application"
                tabindex="0"
                aria-label="Image crop area"
                aria-busy=${isLoading || isProcessing ? "true" : "false"}
                data-image-cropper-stage
                @keydown=${this._handleStageKeyDown}
              >
                <div class="size-full" data-image-cropper-container>
                  <img
                    class="hidden"
                    src=${this._objectUrl}
                    alt="${this.label} crop source"
                    @load=${this._handleImageLoad}
                    @error=${this._handleImageError}
                  />
                </div>
                ${
                  isLoading
                    ? html`
                        <div class="absolute inset-0 z-20 flex items-center justify-center bg-white/75">
                          <svg-spinner
                            size="size-8"
                            background-color="var(--color-primary-100)"
                            label="Loading image editor..."
                          ></svg-spinner>
                        </div>
                      `
                    : nothing
                }
                <div
                  class="absolute bottom-4 left-1/2 z-10 flex -translate-x-1/2 items-center rounded-full border border-stone-200 bg-white p-1 shadow-md"
                  role="group"
                  aria-label="Image zoom"
                >
                  <button
                    type="button"
                    class="btn-tertiary flex size-10 items-center justify-center p-0 text-lg"
                    aria-label="Zoom out"
                    ?disabled=${
                      this._status !== STATUS.READY || !this._cropperImage || this._zoomPercent <= 100
                    }
                    @click=${() => this._zoom(-0.1)}
                  >
                    <span aria-hidden="true">−</span>
                  </button>
                  <span
                    class="min-w-14 text-center text-sm font-semibold text-stone-700"
                    aria-live="polite"
                    aria-atomic="true"
                  >
                    ${zoomLabel}
                  </span>
                  <button
                    type="button"
                    class="btn-tertiary flex size-10 items-center justify-center p-0 text-lg"
                    aria-label="Zoom in"
                    ?disabled=${this._status !== STATUS.READY || !this._cropperImage}
                    @click=${() => this._zoom(0.1)}
                  >
                    <span aria-hidden="true">+</span>
                  </button>
                </div>
              </div>

              ${
                this._errorMessage
                  ? html` <p class="mt-3 text-sm text-red-700" role="alert">${this._errorMessage}</p> `
                  : nothing
              }
            </div>

            <div
              class="flex flex-col-reverse items-stretch justify-between gap-3 border-t border-stone-200 p-5 sm:flex-row sm:items-center"
            >
              <button
                type="button"
                class="btn-primary-outline inline-flex items-center justify-center gap-2 disabled:cursor-not-allowed disabled:opacity-50 sm:justify-start"
                ?disabled=${this._status !== STATUS.READY}
                @click=${this._resetCrop}
              >
                <span class="svg-icon size-4 icon-refresh" aria-hidden="true"></span>
                Reset position
              </button>

              <div class="flex flex-wrap justify-end gap-3">
                <button type="button" class="btn-primary-outline" @click=${() => this._close(null)}>
                  Cancel
                </button>
                <button
                  type="button"
                  class="btn-primary inline-flex min-w-32 items-center justify-center"
                  ?disabled=${this._status !== STATUS.READY}
                  @click=${this._applyCrop}
                >
                  ${isProcessing ? "Preparing image..." : "Apply crop"}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    `;
  }
}

/** Parse an absolute SVG length into CSS pixels, or null for relative lengths. */
const parseSvgAbsoluteLength = (value) => {
  const match = value?.trim().match(SVG_ABSOLUTE_LENGTH_PATTERN);
  if (!match) {
    return null;
  }

  const length = Number.parseFloat(match[1]);
  const unitScale = SVG_LENGTH_UNIT_TO_PIXELS[match[2]?.toLowerCase() || "px"];
  const pixelLength = length * unitScale;
  return Number.isFinite(pixelLength) && pixelLength > 0 ? pixelLength : null;
};

customElements.define("image-cropper", ImageCropper);
