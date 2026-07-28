import { isSuccessfulXHRStatus } from "/static/js/common/utils.js";
import { ocgFetch } from "/static/js/common/fetch.js";

export const CROP_IMAGE_ACCEPTED_FORMATS = ".svg,.png,.jpg,.jpeg,.webp";
export const CROP_IMAGE_SUPPORTED_FORMATS_TEXT = "Supported formats: SVG, PNG, JPEG and WEBP.";
export const DEFAULT_IMAGE_ACCEPTED_FORMATS = ".svg,.png,.jpg,.jpeg,.gif,.webp,.tif,.tiff";
export const IMAGE_UPLOAD_MAX_SIZE_TEXT = "Maximum size: 1MB.";
export const IMAGE_UPLOAD_SUPPORTED_FORMATS_TEXT = "Supported formats: SVG, PNG, JPEG, GIF, WEBP and TIFF.";
export const IMAGE_UPLOAD_ERROR_DETAILS = `${IMAGE_UPLOAD_MAX_SIZE_TEXT} ${IMAGE_UPLOAD_SUPPORTED_FORMATS_TEXT}`;
export const OPEN_GRAPH_IMAGE_ACCEPTED_FORMATS = ".png,.jpg,.jpeg,.webp";
export const OPEN_GRAPH_IMAGE_SUPPORTED_FORMATS_TEXT = "Supported formats: PNG, JPEG and WEBP.";

/**
 * Escapes user-controlled text before it is inserted into alert HTML.
 * @param {string} value - Text to escape
 * @returns {string} HTML-safe text
 */
const escapeHtml = (value) =>
  value.replace(
    /[&<>"']/g,
    (character) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
      })[character],
  );

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
