import { ocgFetch } from "/static/js/common/fetch.js";
import { escapeHtml } from "/static/js/common/trusted-html.js";
import { isSuccessfulXHRStatus } from "/static/js/common/utils.js";

export const ANIMATED_GIF_ERROR_MESSAGE = "Animated GIF images are not supported. Choose a static image.";
export const CROP_IMAGE_ACCEPTED_FORMATS = ".svg,.png,.jpg,.jpeg,.gif,.webp";
export const CROP_IMAGE_SUPPORTED_FORMATS_TEXT = "Supported formats: SVG, PNG, JPEG, GIF and WEBP.";
export const DEFAULT_IMAGE_ACCEPTED_FORMATS = ".svg,.png,.jpg,.jpeg,.gif,.webp,.tif,.tiff";
// Upload size limit shared with the server (1 MiB).
export const IMAGE_UPLOAD_MAX_SIZE_BYTES = 1024 * 1024;
export const IMAGE_UPLOAD_MAX_SIZE_TEXT = "Maximum size: 1MB.";
export const IMAGE_UPLOAD_SUPPORTED_FORMATS_TEXT = "Supported formats: SVG, PNG, JPEG, GIF, WEBP and TIFF.";
export const IMAGE_UPLOAD_ERROR_DETAILS = `${IMAGE_UPLOAD_MAX_SIZE_TEXT} ${IMAGE_UPLOAD_SUPPORTED_FORMATS_TEXT}`;
export const OPEN_GRAPH_IMAGE_ACCEPTED_FORMATS = ".png,.jpg,.jpeg,.webp";
export const OPEN_GRAPH_IMAGE_SUPPORTED_FORMATS_TEXT = "Supported formats: PNG, JPEG and WEBP.";

const GIF_BLOCK_EXTENSION = 0x21;
const GIF_BLOCK_IMAGE = 0x2c;
const GIF_BLOCK_TRAILER = 0x3b;
const GIF_COLOR_TABLE_FLAG = 0x80;
// Signature, version, and logical screen descriptor.
const GIF_HEADER_SIZE = 13;
// Separator, position, size, and packed fields.
const GIF_IMAGE_DESCRIPTOR_SIZE = 9;

/**
 * Uploads an image through the dashboard image endpoint and returns its URL.
 * @param {File} file - Image file to upload
 * @param {{target?: string}} options - Optional upload target for validation
 * @returns {Promise<string>} Uploaded image URL
 */
export const uploadImageFile = async (file, { target = "" } = {}) => {
  const formData = new FormData();

  if (target) {
    formData.append("target", target);
  }
  formData.append("file", file, file.name);

  const response = await ocgFetch("/images", {
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
};

/**
 * Returns whether a file is an SVG based on its MIME type or extension.
 * @param {File} file - File to inspect
 * @returns {boolean} Whether the file is an SVG
 */
export const isSvgFile = (file) =>
  file.type.toLowerCase() === "image/svg+xml" || file.name.toLowerCase().endsWith(".svg");

/**
 * Returns whether a file is a GIF based on its MIME type or extension.
 * @param {File} file - File to inspect
 * @returns {boolean} Whether the file is a GIF
 */
export const isGifFile = (file) =>
  file.type.toLowerCase() === "image/gif" || file.name.toLowerCase().endsWith(".gif");

/**
 * Returns whether a file is a GIF with more than one frame. Walks the block
 * structure without decoding pixels; non-GIF, unreadable or malformed data
 * is treated as static.
 * @param {File} file - File to inspect
 * @returns {Promise<boolean>} Whether the GIF is animated
 */
export const isAnimatedGif = async (file) => {
  if (!isGifFile(file)) {
    return false;
  }
  let bytes;
  try {
    bytes = new Uint8Array(await file.arrayBuffer());
  } catch {
    // Unreadable files are reported later by the decode or upload step.
    return false;
  }
  if (bytes.length < GIF_HEADER_SIZE || bytes[0] !== 0x47 || bytes[1] !== 0x49 || bytes[2] !== 0x46) {
    return false;
  }

  let offset = GIF_HEADER_SIZE;
  const screenPacked = bytes[GIF_HEADER_SIZE - 3];
  if (screenPacked & GIF_COLOR_TABLE_FLAG) {
    offset += gifColorTableSize(screenPacked);
  }

  let frames = 0;
  while (offset < bytes.length) {
    const blockType = bytes[offset];
    offset += 1;
    if (blockType === GIF_BLOCK_TRAILER) {
      break;
    }
    if (blockType === GIF_BLOCK_EXTENSION) {
      offset = skipGifSubBlocks(bytes, offset + 1);
      continue;
    }
    if (blockType !== GIF_BLOCK_IMAGE) {
      break;
    }

    frames += 1;
    if (frames > 1) {
      return true;
    }
    const imagePacked = bytes[offset + 8];
    offset += GIF_IMAGE_DESCRIPTOR_SIZE;
    if (imagePacked & GIF_COLOR_TABLE_FLAG) {
      offset += gifColorTableSize(imagePacked);
    }
    // Skip the LZW minimum code size before the image data sub-blocks.
    offset = skipGifSubBlocks(bytes, offset + 1);
  }

  return false;
};

/**
 * Builds the shared upload failure alert body.
 * @param {string} imageLabel - Human-facing noun for the failed upload
 * @param {string} serverMessage - Specific server error message when available
 * @param {string} [details=IMAGE_UPLOAD_ERROR_DETAILS] - Size and format guidance
 * @returns {string} HTML message accepted by the alert helper
 */
export const getImageUploadErrorMessage = (
  imageLabel,
  serverMessage = "",
  details = IMAGE_UPLOAD_ERROR_DETAILS,
) => {
  const specificMessage = serverMessage.trim();
  const escapedMessage = specificMessage ? escapeHtml(specificMessage) : "";
  const message = escapedMessage
    ? `${escapedMessage}<br /><br />Something went wrong adding the ${imageLabel}. Please try again later.`
    : `Something went wrong adding the ${imageLabel}. Please try again later.`;

  return `${message}<br /><br /><div class="text-sm text-stone-500">${details}</div>`;
};

/** Byte length of a colour table described by a packed field. */
const gifColorTableSize = (packed) => 3 * (1 << ((packed & 0x07) + 1));

/** Advance past length-prefixed sub-blocks up to and including the terminator. */
const skipGifSubBlocks = (bytes, offset) => {
  let position = offset;
  while (position < bytes.length) {
    const size = bytes[position];
    position += 1;
    if (size === 0) {
      break;
    }
    position += size;
  }
  return position;
};
