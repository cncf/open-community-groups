import { expect, waitUntil } from "@open-wc/testing";

import "/static/js/common/media/image-field.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("image-field", () => {
  const env = useDashboardTestEnv({ withSwal: true, withScroll: true });
  useMountedElementsCleanup("image-field");

  let fetchMock;

  beforeEach(() => {
    fetchMock = mockFetch();
  });

  afterEach(() => {
    fetchMock.restore();
  });

  it("uploads an image and emits the new value", async () => {
    // Mock the fetch response.
    fetchMock.setImpl(async () => ({
      status: 201,
      async json() {
        return { url: "https://example.com/image.png" };
      },
    }));

    // Render the image-field fixture.
    const element = await mountLitComponent("image-field", {
      label: "Banner",
      name: "banner_image",
      target: "banner",
    });
    const values = [];

    // Listen for the emitted event.
    element.addEventListener("image-change", (event) => {
      values.push(event.detail.value);
    });

    // Upload the selected file and wait for the hidden input to update.
    await element._uploadFile(new File(["data"], "banner.png", { type: "image/png" }));
    await element.updateComplete;

    // Uploads an image and emits the new value.
    expect(values).to.deep.equal(["https://example.com/image.png"]);
    expect(element.value).to.equal("https://example.com/image.png");
    expect(element.querySelector('input[name="banner_image"]').value).to.equal(
      "https://example.com/image.png",
    );
    expect(fetchMock.calls).to.have.length(1);
    expect(fetchMock.calls[0][0]).to.equal("/images");
    expect(fetchMock.calls[0][1].method).to.equal("POST");
    expect(Array.from(fetchMock.calls[0][1].body.keys())).to.deep.equal(["target", "file"]);
    expect(fetchMock.calls[0][1].body.get("target")).to.equal("banner");
  });

  it("crops images with mandatory dimensions before uploading", async () => {
    // Mock the uploaded image URL.
    fetchMock.setImpl(async () => ({
      status: 201,
      async json() {
        return { url: "https://example.com/cropped-logo.webp" };
      },
    }));
    const element = await mountLitComponent("image-field", {
      label: "Logo",
      name: "logo_url",
      target: "logo",
    });
    const originalFile = new File(["original"], "logo.png", {
      type: "image/png",
    });
    const croppedFile = new File(["cropped"], "logo-cropped.webp", {
      type: "image/webp",
    });
    const cropper = element.querySelector("image-cropper");
    let selectedFile;
    cropper.edit = async (file) => {
      selectedFile = file;
      return croppedFile;
    };

    // Process the source image through the reusable cropper.
    await element._processFile(originalFile);

    // Only the cropped file is submitted through the existing upload contract.
    expect(selectedFile).to.equal(originalFile);
    expect(fetchMock.calls).to.have.length(1);
    const uploadedFile = fetchMock.calls[0][1].body.get("file");
    expect(uploadedFile.name).to.equal(croppedFile.name);
    expect(uploadedFile.type).to.equal(croppedFile.type);
    expect(await uploadedFile.text()).to.equal("cropped");
    expect(fetchMock.calls[0][1].body.get("target")).to.equal("logo");
  });

  it("keeps client-only crop targets out of the upload payload", async () => {
    // Mock the uploaded advertisement banner URL.
    fetchMock.setImpl(async () => ({
      status: 201,
      async json() {
        return { url: "https://example.com/advertisement.webp" };
      },
    }));
    const element = await mountLitComponent("image-field", {
      cropTarget: "ad_banner",
      label: "Banner Image",
      name: "ad_banner_url",
    });
    const croppedFile = new File(["cropped"], "advertisement-cropped.webp", {
      type: "image/webp",
    });
    const cropper = element.querySelector("image-cropper");
    cropper.edit = async () => croppedFile;

    // Crop the source while preserving the target-less upload contract.
    await element._processFile(new File(["source"], "advertisement.jpg", { type: "image/jpeg" }));

    expect(cropper.target).to.equal("ad_banner");
    expect(Array.from(fetchMock.calls[0][1].body.keys())).to.deep.equal(["file"]);
  });

  it("does not upload when mandatory cropping is cancelled", async () => {
    // Render a field that requires exact banner dimensions.
    const element = await mountLitComponent("image-field", {
      label: "Banner",
      name: "banner_url",
      target: "banner",
    });
    element.querySelector("image-cropper").edit = async () => null;
    let resetCalls = 0;

    // Cancel the crop instead of returning an uploadable file.
    await element._processFile(new File(["source"], "banner.png", { type: "image/png" }), () => {
      resetCalls += 1;
    });

    // The selected input can be reused without sending a request.
    expect(fetchMock.calls).to.have.length(0);
    expect(resetCalls).to.equal(1);
  });

  it("keeps focus on the upload control while a cropped image uploads", async () => {
    // Hold a successful upload open after the cropper restores its opener's focus.
    let resolveUpload;
    fetchMock.setImpl(
      () =>
        new Promise((resolve) => {
          resolveUpload = resolve;
        }),
    );
    const element = await mountLitComponent("image-field", {
      label: "Logo",
      target: "logo",
    });
    const uploadButton = element.querySelector("[data-image-upload-trigger]");
    const croppedFile = new File(["cropped"], "logo-cropped.webp", {
      type: "image/webp",
    });
    element.querySelector("image-cropper").edit = async (_file, { focusOrigin }) => {
      focusOrigin.focus();
      return croppedFile;
    };
    uploadButton.focus();

    const processingPromise = element._processFile(
      new File(["source"], "logo.png", { type: "image/png" }),
      undefined,
      uploadButton,
    );
    await waitUntil(() => element._isUploading, "the cropped image should start uploading");
    await element.updateComplete;

    // The busy control remains focusable but cannot reopen the picker.
    expect(document.activeElement).to.equal(uploadButton);
    expect(uploadButton.disabled).to.equal(false);
    expect(uploadButton.getAttribute("aria-disabled")).to.equal("true");

    resolveUpload({
      status: 201,
      async json() {
        return { url: "https://example.com/cropped-logo.webp" };
      },
    });
    await processingPromise;
    await element.updateComplete;

    expect(document.activeElement).to.equal(uploadButton);
    expect(uploadButton.getAttribute("aria-disabled")).to.equal("false");
  });

  it("rejects GIF files before mandatory cropping", async () => {
    // Drag-and-drop can bypass the file picker's accepted-format filter.
    const element = await mountLitComponent("image-field", {
      target: "banner",
    });
    let resetCalls = 0;
    await element._processFile(new File(["gif"], "animated.gif", { type: "image/gif" }), () => {
      resetCalls += 1;
    });

    // GIF animation is never silently flattened into the cropper's static output.
    expect(fetchMock.calls).to.have.length(0);
    expect(resetCalls).to.equal(1);
    expect(env.current.swal.calls.at(-1).html).to.include("animation would be lost");
  });

  it("discards a retained retry when another file begins preparation", async () => {
    // Retain a failed crop, then hold a replacement file in crop preparation.
    const element = await mountLitComponent("image-field", {
      target: "logo",
    });
    element._pendingUploadFile = new File(["old"], "old-logo.webp", {
      type: "image/webp",
    });
    await element.updateComplete;
    const replacementFile = new File(["replacement"], "replacement.png", {
      type: "image/png",
    });
    let resolveReplacementCrop;
    element.querySelector("image-cropper").edit = () =>
      new Promise((resolve) => {
        resolveReplacementCrop = resolve;
      });

    const preparationPromise = element._processFile(replacementFile);
    await element.updateComplete;

    // The obsolete retry cannot start an upload while the replacement is pending.
    expect(element._pendingUploadFile).to.equal(null);
    expect(element._isPreparing).to.equal(true);
    expect(element.textContent).to.not.include("Retry upload");
    expect(element.querySelector("[data-image-upload-preview]").getAttribute("aria-busy")).to.equal("true");
    expect(element.querySelector("svg-spinner").parentElement.getAttribute("aria-hidden")).to.equal("false");
    expect(element.querySelector("svg-spinner").getAttribute("label")).to.equal("Preparing image...");
    await element._retryUpload();
    expect(fetchMock.calls).to.have.length(0);

    // Ignore another drop without allowing the browser to navigate away.
    const pendingDragEvent = new Event("dragover", { cancelable: true });
    const pendingDropEvent = new Event("drop", { cancelable: true });
    element._handleDragOver(pendingDragEvent);
    await element._handleDrop(pendingDropEvent);
    expect(pendingDragEvent.defaultPrevented).to.equal(true);
    expect(pendingDropEvent.defaultPrevented).to.equal(true);

    resolveReplacementCrop(null);
    await preparationPromise;
    await element.updateComplete;
    expect(element._isPreparing).to.equal(false);
    expect(element.querySelector("[data-image-upload-preview]").getAttribute("aria-busy")).to.equal("false");
    expect(element.querySelector("svg-spinner").parentElement.getAttribute("aria-hidden")).to.equal("true");
  });

  it("ignores pending crop preparation after the field disconnects", async () => {
    // Hold file preparation open while the field and its cropper leave the document.
    const element = await mountLitComponent("image-field", {
      target: "logo",
    });
    const pendingFile = new File(["pending"], "pending.png", {
      type: "image/png",
    });
    let resolveCrop;
    let cropCalls = 0;
    element.querySelector("image-cropper").edit = () =>
      new Promise((resolve) => {
        resolveCrop = resolve;
        cropCalls += 1;
      });

    const processingPromise = element._processFile(pendingFile);
    await waitUntil(() => cropCalls === 1, "crop preparation should start");
    element.remove();
    resolveCrop(pendingFile);
    await processingPromise;

    expect(fetchMock.calls).to.have.length(0);
    expect(document.body.style.overflow).to.equal("");
  });

  it("retries a failed upload without repeating the crop", async () => {
    // Fail the first request, then accept the retained cropped file on retry.
    let uploadAttempts = 0;
    fetchMock.setImpl(async () => {
      uploadAttempts += 1;
      if (uploadAttempts === 1) {
        return {
          status: 503,
          async text() {
            return "Upload unavailable";
          },
        };
      }
      return {
        status: 201,
        async json() {
          return { url: "https://example.com/retried-logo.webp" };
        },
      };
    });
    const element = await mountLitComponent("image-field", {
      label: "Logo",
      target: "logo",
    });
    const croppedFile = new File(["cropped"], "logo-cropped.webp", {
      type: "image/webp",
    });
    let cropCalls = 0;
    element.querySelector("image-cropper").edit = async () => {
      cropCalls += 1;
      return croppedFile;
    };

    await element._processFile(new File(["source"], "logo.png", { type: "image/png" }));
    await element.updateComplete;
    const retryButton = [...element.querySelectorAll("button")].find(
      (button) => button.textContent.trim() === "Retry upload",
    );
    expect(retryButton).to.not.equal(undefined);
    expect(retryButton.getAttribute("aria-label")).to.equal("Retry upload for Logo");

    retryButton.click();
    await waitUntil(
      () => element.value === "https://example.com/retried-logo.webp",
      "the retained crop should upload",
    );

    expect(cropCalls).to.equal(1);
    expect(uploadAttempts).to.equal(2);
    expect(fetchMock.calls[1][1].body.get("file").name).to.equal("logo-cropped.webp");
  });

  it("restores focus to the upload control when cropping is cancelled", async () => {
    // Render the real image field and activate its visible upload control.
    const element = await mountLitComponent("image-field", {
      label: "Banner",
      name: "banner_url",
      target: "banner",
    });
    const uploadButton = [...element.querySelectorAll("button")].find(
      (button) => button.textContent.trim() === "Upload image",
    );
    const fileInput = element.querySelector('input[type="file"]');
    const selectedFiles = new DataTransfer();
    selectedFiles.items.add(new File(["source"], "banner.png", { type: "image/png" }));
    uploadButton.focus();
    expect(uploadButton.getAttribute("aria-label")).to.equal("Upload image for Banner");
    uploadButton.click();
    fileInput.files = selectedFiles.files;
    fileInput.dispatchEvent(new Event("change", { bubbles: true }));

    // Cancel the opened crop dialog and verify its actual trigger regains focus.
    const cropper = element.querySelector("image-cropper");
    await waitUntil(() => cropper._isOpen, "the crop editor should open");
    [...cropper.querySelectorAll("button")].find((button) => button.textContent.trim() === "Cancel").click();
    await waitUntil(() => document.activeElement === uploadButton, "the upload control should regain focus");

    expect(fileInput.value).to.equal("");
  });

  it("restores focus to the preview after keyboard picker activation", async () => {
    // Render a croppable field and prepare a browser-decodable source image.
    const element = await mountLitComponent("image-field", {
      label: "Banner",
      name: "banner_url",
      target: "banner",
    });
    const preview = element.querySelector("[data-image-upload-preview]");
    const fileInput = element.querySelector('input[type="file"]');
    const cropper = element.querySelector("image-cropper");
    const source = `
      <svg xmlns="http://www.w3.org/2000/svg" width="2500" height="300">
        <rect width="2500" height="300" fill="#0094ff" />
      </svg>
    `;

    for (const key of ["Enter", " "]) {
      // Open the native picker from the keyboard-operable preview.
      preview.focus();
      preview.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key }));
      const selectedFiles = new DataTransfer();
      selectedFiles.items.add(new File([source], "banner.svg", { type: "image/svg+xml" }));
      fileInput.files = selectedFiles.files;
      fileInput.dispatchEvent(new Event("change", { bubbles: true }));
      await waitUntil(() => cropper._isOpen, "the crop editor should open");

      // Cancelling returns focus to the preview that initiated the edit.
      [...cropper.querySelectorAll("button")]
        .find((button) => button.textContent.trim() === "Cancel")
        .click();
      await waitUntil(() => document.activeElement === preview, "the preview should regain focus");
    }
  });

  it("uses the preview as the fallback when the upload button is hidden", async () => {
    // Render a field whose preview is its only visible picker control.
    const element = await mountLitComponent("image-field", {
      hideUploadButton: true,
      target: "logo",
    });
    const preview = element.querySelector("[data-image-upload-preview]");
    const fileInput = element.querySelector('input[type="file"]');
    const selectedFiles = new DataTransfer();
    selectedFiles.items.add(new File(["source"], "logo.png", { type: "image/png" }));

    // A picker change without a recorded trigger falls back to the visible preview.
    fileInput.files = selectedFiles.files;
    fileInput.dispatchEvent(new Event("change", { bubbles: true }));
    const cropper = element.querySelector("image-cropper");
    await waitUntil(() => cropper._isOpen, "the crop editor should open");
    [...cropper.querySelectorAll("button")].find((button) => button.textContent.trim() === "Cancel").click();
    await waitUntil(() => document.activeElement === preview, "the preview should receive fallback focus");
  });

  it("renders the cropper only for targets with mandatory dimensions", async () => {
    // Render mandatory and unrestricted image targets.
    const bannerField = await mountLitComponent("image-field", {
      target: "banner_mobile",
    });
    const badgeField = await mountLitComponent("image-field", {
      target: "badge",
    });

    // Mandatory dimensions opt in while other upload flows stay unchanged.
    expect(bannerField.querySelector("image-cropper")).to.not.equal(null);
    expect(badgeField.querySelector("image-cropper")).to.equal(null);
  });

  it("clears the image value when remove is triggered", async () => {
    // Render the image-field fixture.
    const element = await mountLitComponent("image-field", {
      value: "https://example.com/image.png",
    });

    // Remove the current image and wait for the hidden input to update.
    element._handleRemove();
    await element.updateComplete;

    // The image value is cleared after removal.
    expect(element.value).to.equal("");
  });

  it("hides the remove button when hide-remove-button is set", async () => {
    // Render the image-field fixture without the remove button.
    const element = await mountLitComponent("image-field", {
      hideRemoveButton: true,
      value: "https://example.com/image.png",
    });

    // Collect the rendered button labels.
    const labels = [...element.querySelectorAll("button")].map((button) => button.textContent.trim());

    // The remove button is not rendered while the upload control remains.
    expect(labels).to.not.include("Remove image");
    expect(element.textContent).to.include("Upload image");
  });

  it("keeps selected and dropped direct-upload files in the submitted field", async () => {
    // Render the verification upload inside the form that owns its file submission.
    const form = document.createElement("form");
    document.body.append(form);
    const element = await mountLitComponent("image-field", {
      acceptedFormats: "image/png",
      directUpload: true,
      label: "Exported PNG",
      name: "png",
    });
    form.append(element);
    const input = element.querySelector('input[type="file"]');
    const selectedFile = new File(["selected"], "selected-badge.png", {
      type: "image/png",
    });
    const selectedFiles = new DataTransfer();
    selectedFiles.items.add(selectedFile);

    // Keep an empty file picker out of the parent form submission.
    expect(input.hasAttribute("name")).to.equal(false);
    expect(new FormData(form).has("png")).to.equal(false);

    // Select a file through the native input.
    input.files = selectedFiles.files;
    input.dispatchEvent(new Event("change", { bubbles: true }));
    await element.updateComplete;

    expect(input.name).to.equal("png");
    expect(new FormData(form).get("png").name).to.equal("selected-badge.png");

    // Drop a replacement file and retain it in the same submitted input.
    const droppedFiles = new DataTransfer();
    droppedFiles.items.add(new File(["dropped"], "dropped-badge.png", { type: "image/png" }));
    element._handleDrop({
      dataTransfer: droppedFiles,
      preventDefault() {},
    });
    await element.updateComplete;

    expect(new FormData(form).get("png").name).to.equal("dropped-badge.png");
    form.remove();
  });

  it("does not give direct-upload-only file inputs an empty name", async () => {
    // Render an image field that uploads through its component endpoint.
    const element = await mountLitComponent("image-field", {
      label: "Banner",
      name: "banner_image",
    });

    // Its temporary file picker is not included in parent form submissions.
    expect(element.querySelector('input[type="file"]').hasAttribute("name")).to.equal(false);
  });

  it("does not show the generic supported formats text for Open Graph images", async () => {
    // Mount an Open Graph image field with explicit format guidance.
    const element = await mountLitComponent("image-field", {
      helpPrefixText: "Size required 1200 x 630 px. Format must be PNG, JPEG, or WebP.",
      imageKind: "banner",
      target: "open_graph",
    });

    // Set up help text.
    const helpText = element.querySelector(".form-legend").textContent.trim();
    const fileInput = element.querySelector('input[type="file"]');

    // Verify does not show the generic supported formats text for Open Graph images.
    expect(helpText).to.equal(
      "Size required 1200 x 630 px. Format must be PNG, JPEG, or WebP. Maximum size: 1MB.",
    );
    expect(helpText).not.to.include("Supported formats");
    expect(fileInput.accept).to.equal(".png,.jpg,.jpeg,.webp");
  });

  it("limits croppable banner images to formats the editor can open", async () => {
    // Mount a banner image field whose target requires cropping.
    const element = await mountLitComponent("image-field", {
      helpPrefixText: "Size required 2428 x 192 px.",
      imageKind: "banner",
      target: "banner",
    });

    // Set up help text.
    const helpText = element.querySelector(".form-legend").textContent.trim();
    const fileInput = element.querySelector('input[type="file"]');

    // Assert the accepted image formats copy.
    expect(helpText).to.include("Supported formats: SVG, PNG, JPEG and WEBP.");
    expect(helpText).not.to.include("GIF");
    expect(helpText).not.to.include("TIFF");
    expect(fileInput.accept).to.equal(".svg,.png,.jpg,.jpeg,.webp");
  });

  it("shows the generic supported formats text for images without mandatory dimensions", async () => {
    // Mount a wide image field whose target does not require cropping.
    const element = await mountLitComponent("image-field", {
      imageKind: "banner",
    });

    // Set up help text.
    const helpText = element.querySelector(".form-legend").textContent.trim();
    const fileInput = element.querySelector('input[type="file"]');

    // Assert the accepted image formats copy.
    expect(helpText).to.include("Supported formats: SVG, PNG, JPEG, GIF, WEBP and TIFF.");
    expect(fileInput.accept).to.equal(".svg,.png,.jpg,.jpeg,.gif,.webp,.tif,.tiff");
  });

  it("shows escaped server messages when image uploads fail", async () => {
    // Mock the upload endpoint with a server validation message.
    fetchMock.setImpl(async () => ({
      status: 422,
      async text() {
        return "Logo must be square <script>";
      },
    }));

    // Render the image-field fixture.
    const element = await mountLitComponent("image-field", {
      label: "Logo",
      name: "logo_url",
    });

    // Upload the selected image and wait for the alert to be shown.
    await element._uploadFile(new File(["data"], "logo.png", { type: "image/png" }));
    await element.updateComplete;

    // The server message is escaped and shown before the generic upload copy.
    const alert = env.current.swal.calls.at(-1);
    expect(alert.html).to.include("Logo must be square &lt;script&gt;");
    expect(alert.html).to.include("Something went wrong adding the image.");
  });

  it("matches upload failure guidance to the croppable field formats", async () => {
    // Mock an upload endpoint failure for a croppable target.
    fetchMock.setImpl(async () => ({
      status: 500,
      async text() {
        return "";
      },
    }));

    // Render the image-field fixture.
    const element = await mountLitComponent("image-field", {
      label: "Banner",
      name: "banner_image",
      target: "banner",
    });

    // Upload the selected image and wait for the alert to be shown.
    await element._uploadFile(new File(["data"], "banner.png", { type: "image/png" }));
    await element.updateComplete;

    // The failure details list only the formats the editor can open.
    const alert = env.current.swal.calls.at(-1);
    expect(alert.html).to.include("Supported formats: SVG, PNG, JPEG and WEBP.");
    expect(alert.html).not.to.include("GIF");
    expect(alert.html).not.to.include("TIFF");
  });
});
