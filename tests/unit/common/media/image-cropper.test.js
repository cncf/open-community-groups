import { expect, waitUntil } from "@open-wc/testing";

import { ImageCropper } from "/static/js/common/media/image-cropper.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

const createPngFile = async ({ height, name, width }) => {
  const canvas = document.createElement("canvas");
  canvas.height = height;
  canvas.width = width;
  const context = canvas.getContext("2d");
  context.fillStyle = "#0094ff";
  context.fillRect(0, 0, width, height);
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/png"));
  return new File([blob], name, { type: "image/png" });
};

describe("image-cropper", () => {
  const env = useDashboardTestEnv({ withSwal: true });
  useMountedElementsCleanup("image-cropper");

  it("supports every target with mandatory dimensions", () => {
    expect(ImageCropper.hasRequiredSize("ad_banner")).to.equal(true);
    expect(ImageCropper.hasRequiredSize("banner")).to.equal(true);
    expect(ImageCropper.hasRequiredSize("banner_mobile")).to.equal(true);
    expect(ImageCropper.hasRequiredSize("logo")).to.equal(true);
    expect(ImageCropper.hasRequiredSize("open_graph")).to.equal(true);
    expect(ImageCropper.hasRequiredSize("badge")).to.equal(false);
    expect(ImageCropper.hasRequiredSize("")).to.equal(false);
  });

  it("uses the required advertisement banner dimensions", async () => {
    // Open the advertisement cropper and inspect its user-facing size contract.
    const element = await mountLitComponent("image-cropper", {
      label: "Banner Image",
      target: "ad_banner",
    });
    const resultPromise = element.edit(
      new File(["not-an-image"], "advertisement.png", {
        type: "image/png",
      }),
    );
    await waitUntil(() => element._isOpen, "the crop editor should open");
    await element.updateComplete;

    // Verify the required size is shown and the edit closes without a result.
    expect(element.textContent).to.include("2400 × 300 px");
    element._close(null, { restoreFocus: false });
    expect(await resultPromise).to.equal(null);
  });

  it("opens an accessible dialog and restores focus when cancelled", async () => {
    // Render the editor and focus the upload control that opened it.
    const trigger = document.createElement("button");
    trigger.textContent = "Upload image";
    document.body.append(trigger);
    trigger.focus();
    const element = await mountLitComponent("image-cropper", {
      label: "Banner",
      target: "banner",
    });

    // Open the editor for a selected file.
    const resultPromise = element.edit(new File(["not-an-image"], "banner.png", { type: "image/png" }));
    await waitUntil(() => element._isOpen, "the crop editor should open");
    await element.updateComplete;

    // The required size and modal state are exposed to the user.
    const dialog = element.querySelector('[role="dialog"]');
    expect(dialog).to.not.equal(null);
    expect(dialog.getAttribute("aria-modal")).to.equal("true");
    expect(element.textContent).to.include("2428 × 192 px");
    expect(document.body.style.overflow).to.equal("hidden");
    const requiredSizeBadge = element.querySelector(".custom-badge");
    expect(requiredSizeBadge.textContent).to.include("2428 × 192 px");
    expect(requiredSizeBadge.classList.contains("normal-case")).to.equal(true);
    const instructions = document.getElementById(dialog.getAttribute("aria-describedby"));
    expect(instructions.textContent).to.include("Animation is not preserved.");
    expect(instructions.querySelectorAll("p")).to.have.length(1);
    expect(instructions.classList.contains("border-stone-200")).to.equal(true);
    expect(instructions.classList.contains("bg-stone-50")).to.equal(true);
    expect(instructions.querySelector(".svg-icon")).to.equal(null);
    expect(instructions.querySelectorAll("kbd")).to.have.length(2);
    const stage = element.querySelector("[data-image-cropper-stage]");
    expect(stage.getAttribute("role")).to.equal("application");
    expect(stage.classList.contains("focus-visible:outline-stone-400")).to.equal(true);
    expect(stage.classList.contains("focus-visible:ring-primary-500")).to.equal(false);
    expect(document.activeElement).to.equal(stage);

    // Cancel the edit and verify the original trigger regains focus.
    [...element.querySelectorAll("button")].find((button) => button.textContent.trim() === "Cancel").click();
    expect(await resultPromise).to.equal(null);
    await element.updateComplete;

    // Verify the dialog closes, scroll unlocks, and focus returns to the trigger.
    expect(element.querySelector('[role="dialog"]')).to.equal(null);
    expect(document.body.style.overflow).to.equal("");
    expect(document.activeElement).to.equal(trigger);
  });

  it("cleans up an open edit when disconnected", async () => {
    // Open an edit from a stable trigger and track its temporary object URL.
    const trigger = document.createElement("button");
    document.body.append(trigger);
    trigger.focus();
    const element = await mountLitComponent("image-cropper", {
      target: "logo",
    });
    const revokedUrls = [];
    const originalRevokeObjectUrl = URL.revokeObjectURL;
    URL.revokeObjectURL = (objectUrl) => revokedUrls.push(objectUrl);

    try {
      const resultPromise = element.edit(new File(["not-an-image"], "logo.png", { type: "image/png" }), {
        focusOrigin: trigger,
      });
      await waitUntil(() => element._isOpen, "the crop editor should open");
      await element.updateComplete;
      const objectUrl = element._objectUrl;
      expect(document.activeElement).to.equal(element.querySelector("[data-image-cropper-stage]"));

      // Removing an open component resolves its edit without restoring opener focus.
      element.remove();
      expect(await resultPromise).to.equal(null);
      expect(document.body.style.overflow).to.equal("");
      expect(document.body.dataset.modalOpenCount).to.equal("0");
      expect(revokedUrls).to.have.length(2);
      expect(revokedUrls).to.include(objectUrl);
      expect(document.activeElement).to.not.equal(trigger);

      // Its detached document listener no longer reacts to Escape.
      element._isOpen = true;
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
      expect(element._isOpen).to.equal(true);
      element._isOpen = false;
    } finally {
      // Restore the URL mock and remove the trigger fixture.
      URL.revokeObjectURL = originalRevokeObjectUrl;
      trigger.remove();
    }
  });

  it("shows an error when the selected image cannot be decoded", async () => {
    // Open the editor with a file the browser cannot decode.
    const element = await mountLitComponent("image-cropper", {
      target: "logo",
    });
    const resultPromise = element.edit(new File(["not-an-image"], "logo.png", { type: "image/png" }));
    await waitUntil(() => element._status === "error", "the editor should report the failure");

    // The failure is announced and the crop action stays unavailable.
    expect(element.querySelector('[role="alert"]').textContent).to.include("couldn't be opened");
    const applyButton = [...element.querySelectorAll("button")].find(
      (button) => button.textContent.trim() === "Apply crop",
    );
    expect(applyButton.disabled).to.equal(true);

    // Close the fixture without producing an upload file.
    element._close(null);
    expect(await resultPromise).to.equal(null);
  });

  it("rejects source images smaller than the required dimensions", async () => {
    // Open an undersized source image for a target with mandatory dimensions.
    const element = await mountLitComponent("image-cropper", {
      label: "Logo",
      target: "logo",
    });
    const source = `
      <svg xmlns="http://www.w3.org/2000/svg" width="359" height="360">
        <rect width="359" height="360" fill="#0094ff" />
      </svg>
    `;
    const resultPromise = element.edit(new File([source], "undersized-logo.svg", { type: "image/svg+xml" }));
    await waitUntil(() => env.current.swal.calls.length === 1, "the size alert should open");

    // The edit stops and the alert offers dismissal without a continue action.
    expect(await resultPromise).to.equal(null);
    expect(element.querySelector('[role="dialog"]')).to.equal(null);
    expect(env.current.swal.calls[0]).to.include({
      icon: "error",
      showConfirmButton: true,
      text: "The selected image (359 × 360 px) is smaller than the required size (360 × 360 px). Please choose a larger image.",
    });
    expect(env.current.swal.calls[0]).to.not.have.property("confirmButtonText");
    expect(env.current.swal.calls[0]).to.not.have.property("showCancelButton");
  });

  it("ignores stale image errors after the editor is closed", async () => {
    // Open the editor and keep a handle to the rendered image element.
    const element = await mountLitComponent("image-cropper", {
      target: "logo",
    });
    const resultPromise = element.edit(new File(["source"], "logo.png", { type: "image/png" }));
    await waitUntil(() => element._isOpen, "the crop editor should open");
    await element.updateComplete;
    const image = element.querySelector("img");

    // Cancel the edit before the image finishes loading.
    [...element.querySelectorAll("button")].find((button) => button.textContent.trim() === "Cancel").click();
    expect(await resultPromise).to.equal(null);
    await element.updateComplete;

    // A late error event from the removed image leaves the editor state untouched.
    image.dispatchEvent(new Event("error"));
    expect(element._errorMessage).to.equal("");
    expect(element.querySelector('[role="alert"]')).to.equal(null);
  });

  it("ignores stale image loads after a new edit opens", async () => {
    // Open and close an edit while retaining its detached source element.
    const element = await mountLitComponent("image-cropper", {
      target: "logo",
    });
    const source = `
      <svg xmlns="http://www.w3.org/2000/svg" width="720" height="360">
        <rect width="720" height="360" fill="#0094ff" />
      </svg>
    `;
    const firstResult = element.edit(new File([source], "first-logo.svg", { type: "image/svg+xml" }));
    await waitUntil(() => element._isOpen, "the first crop editor should open");
    await element.updateComplete;
    const staleImage = element.querySelector("img");
    element._close(null, { restoreFocus: false });
    expect(await firstResult).to.equal(null);
    await element.updateComplete;

    // Start another edit before the detached source reports a late load.
    const secondResult = element.edit(new File([source], "second-logo.svg", { type: "image/svg+xml" }));
    await waitUntil(() => element._isOpen, "the second crop editor should open");
    await element.updateComplete;
    const activeCropper = element._cropper;
    await element._handleImageLoad({ currentTarget: staleImage });

    // The late event cannot replace or initialize the active vendor instance.
    expect(staleImage.isConnected).to.equal(false);
    expect(element._cropper).to.equal(activeCropper);
    await waitUntil(() => element._status === "ready", "the active editor should initialize");

    // Close the active edit without producing an upload file.
    element._close(null);
    expect(await secondResult).to.equal(null);
  });

  it("initializes the vendored cropper with the required aspect ratio", async () => {
    // Open a real browser-decodable image through the vendored module.
    const element = await mountLitComponent("image-cropper", {
      target: "open_graph",
    });
    const source = `
      <svg xmlns="http://www.w3.org/2000/svg" width="1600" height="900">
        <rect width="1600" height="900" fill="#0094ff" />
      </svg>
    `;
    const resultPromise = element.edit(new File([source], "social-image.svg", { type: "image/svg+xml" }));
    await waitUntil(() => element._status === "ready", "the cropper should initialize");

    // Cropper.js creates its custom elements and applies the target ratio.
    const cropperCanvas = element.querySelector("cropper-canvas");
    const selectionCorners = element.querySelectorAll("[data-cropper-corner]");
    expect(cropperCanvas).to.not.equal(null);
    expect(element.querySelector("cropper-image")).to.not.equal(null);
    expect(element._selection.aspectRatio).to.equal(1200 / 630);
    expect(element._selection.getAttribute("theme-color")).to.equal("var(--color-primary-500)");
    expect(selectionCorners).to.have.length(4);
    selectionCorners.forEach((corner) => {
      expect(corner.classList.contains("border-primary-500")).to.equal(true);
      expect(corner.classList.contains("pointer-events-none")).to.equal(true);
      expect(corner.classList.contains("size-[10px]")).to.equal(true);
    });

    // The decorative crop surface stays hidden from assistive technology.
    expect(cropperCanvas.getAttribute("aria-hidden")).to.equal("true");
    expect(element.querySelector('[role="grid"]')).to.equal(null);

    // Close the fixture without producing an upload file.
    element._close(null);
    expect(await resultPromise).to.equal(null);
  });

  it("uploads an exact supported image without opening the crop editor", async () => {
    const element = await mountLitComponent("image-cropper", {
      target: "logo",
    });
    const file = await createPngFile({
      height: 360,
      name: "community-logo.png",
      width: 360,
    });

    const result = await element.edit(file);

    expect(result).to.equal(file);
    expect(result.size).to.be.lessThan(1_000_000);
    expect(element.querySelector('[role="dialog"]')).to.equal(null);
  });

  it("automatically resizes an image with the required aspect ratio", async () => {
    const element = await mountLitComponent("image-cropper", {
      target: "logo",
    });
    const source = `
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 720">
        <rect width="720" height="720" fill="#0094ff" />
      </svg>
    `;

    const result = await element.edit(new File([source], "community-logo.svg", { type: "image/svg+xml" }));
    const bitmap = await createImageBitmap(result);

    expect(result.name).to.equal("community-logo-cropped.webp");
    expect(result.type).to.equal("image/webp");
    expect(bitmap.width).to.equal(360);
    expect(bitmap.height).to.equal(360);
    expect(element.querySelector('[role="dialog"]')).to.equal(null);
    bitmap.close();
  });

  it("uses view boxes for relative SVG sizes and converts absolute units", async () => {
    // Define relative and physical SVG dimensions around stable source geometry.
    const element = await mountLitComponent("image-cropper", {
      target: "open_graph",
    });
    const relativeSource = `
      <svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" viewBox="0 0 1200 630">
        <rect width="1200" height="630" fill="#0094ff" />
      </svg>
    `;
    const absoluteSource = `
      <svg xmlns="http://www.w3.org/2000/svg" width="3.75in" height="95.25mm">
        <rect width="100%" height="100%" fill="#0094ff" />
      </svg>
    `;

    // Parse both forms through the source-size boundary used by preparation.
    const relativeSize = await element._getSourceSize(
      new File([relativeSource], "relative.svg", { type: "image/svg+xml" }),
      new Image(),
    );
    const absoluteSize = await element._getSourceSize(
      new File([absoluteSource], "absolute.svg", { type: "image/svg+xml" }),
      new Image(),
    );

    // Relative sizes use the view box and physical units resolve to CSS pixels.
    expect(relativeSize).to.deep.equal({ height: 630, width: 1200 });
    expect(absoluteSize.height).to.be.closeTo(360, 0.001);
    expect(absoluteSize.width).to.be.closeTo(360, 0.001);
  });

  it("discards an automatic resize superseded by a newer edit", async () => {
    // Hold the first same-ratio resize while a second exact image is prepared.
    const element = await mountLitComponent("image-cropper", {
      target: "logo",
    });
    const firstFile = new File(["first"], "first.png", { type: "image/png" });
    const secondFile = new File(["second"], "second.png", { type: "image/png" });
    element._decodeImage = async (file) => ({
      image: new Image(),
      objectUrl: `blob:${file.name}`,
      size: file === firstFile ? { height: 720, width: 720 } : { height: 360, width: 360 },
    });
    let resolveFirstResize;
    element._resizeImage = () =>
      new Promise((resolve) => {
        resolveFirstResize = resolve;
      });
    const firstResultPromise = element.edit(firstFile);
    await waitUntil(() => resolveFirstResize, "the first automatic resize should start");

    const secondResult = await element.edit(secondFile);
    resolveFirstResize(new File(["resized"], "first-cropped.png", { type: "image/png" }));

    // Only the latest edit can resolve with an uploadable file.
    expect(secondResult).to.equal(secondFile);
    expect(await firstResultPromise).to.equal(null);
  });

  it("restores focus when a small image is rejected", async () => {
    const focusOrigin = document.createElement("button");
    const displacedFocus = document.createElement("button");
    document.body.append(focusOrigin, displacedFocus);
    displacedFocus.focus();
    const element = await mountLitComponent("image-cropper", {
      target: "logo",
    });
    const source = `
      <svg xmlns="http://www.w3.org/2000/svg" width="180" height="180">
        <rect width="180" height="180" fill="#0094ff" />
      </svg>
    `;

    const result = await element.edit(new File([source], "small-logo.svg", { type: "image/svg+xml" }), {
      focusOrigin,
    });

    expect(result).to.equal(null);
    expect(element.querySelector('[role="dialog"]')).to.equal(null);
    expect(document.activeElement).to.equal(focusOrigin);
    expect(env.current.swal.calls.at(-1).icon).to.equal("error");
    focusOrigin.remove();
    displacedFocus.remove();
  });

  it("fits a mismatched source image around the crop selection", async () => {
    // Open a banner that needs interactive cropping in the real vendor module.
    const element = await mountLitComponent("image-cropper", {
      target: "banner",
    });
    const source = `
      <svg xmlns="http://www.w3.org/2000/svg" width="2500" height="300">
        <rect width="2500" height="300" fill="#0094ff" />
      </svg>
    `;
    const resultPromise = element.edit(new File([source], "banner.svg", { type: "image/svg+xml" }));
    await waitUntil(() => element._status === "ready", "the cropper should initialize");
    await element.updateComplete;

    // The source covers the fixed selection without being expanded to the full canvas.
    const canvasRect = element._cropper.getCropperCanvas().getBoundingClientRect();
    const imageRect = element._cropperImage.getBoundingClientRect();
    const initialImageTransform = element._cropperImage.$getTransform();
    const selectionRect = element._selection.getBoundingClientRect();
    expect(imageRect.width).to.be.at.least(selectionRect.width);
    expect(imageRect.height).to.be.at.least(selectionRect.height);
    expect(
      Math.min(imageRect.width - selectionRect.width, imageRect.height - selectionRect.height),
    ).to.be.lessThan(1);
    expect(imageRect.width).to.be.lessThan(canvasRect.width);

    // Move along the overflowing axis while keeping the fitted axis clamped.
    const stage = element.querySelector("[data-image-cropper-stage]");
    stage.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown" }));
    const keyboardTransform = element._cropperImage.$getTransform();
    expect(keyboardTransform[4]).to.be.closeTo(initialImageTransform[4], 0.1);
    expect(keyboardTransform[5]).to.be.closeTo(initialImageTransform[5] + 8, 0.1);

    element._resetCrop();
    element._cropperImage.$move(8, 8);
    const diagonalTransform = element._cropperImage.$getTransform();
    expect(diagonalTransform[4]).to.be.closeTo(initialImageTransform[4], 0.1);
    expect(diagonalTransform[5]).to.be.closeTo(initialImageTransform[5] + 8, 0.1);
    element._resetCrop();

    // Exporting the wide selection preserves both mandatory dimensions.
    const outputCanvas = await element._selection.$toCanvas({ height: 192, width: 2428 });
    expect(outputCanvas.width).to.equal(2428);
    expect(outputCanvas.height).to.equal(192);

    // The compact controls use project button styles and report zoom changes.
    const zoomControls = element.querySelector('[role="group"][aria-label="Image zoom"]');
    const zoomOutButton = element.querySelector('button[aria-label="Zoom out"]');
    const zoomInButton = element.querySelector('button[aria-label="Zoom in"]');
    const resetButton = [...element.querySelectorAll("button")].find(
      (button) => button.textContent.trim() === "Reset position",
    );
    const cancelButton = [...element.querySelectorAll("button")].find(
      (button) => button.textContent.trim() === "Cancel",
    );
    const applyButton = [...element.querySelectorAll("button")].find(
      (button) => button.textContent.trim() === "Apply crop",
    );
    expect(zoomControls.textContent).to.include("Fit");
    expect(zoomControls.querySelector('[aria-live="polite"]')).to.not.equal(null);
    expect(resetButton.classList.contains("btn-primary-outline")).to.equal(true);
    expect(cancelButton.classList.contains("btn-primary-outline")).to.equal(true);
    expect(applyButton.classList.contains("btn-primary")).to.equal(true);
    expect(zoomOutButton.disabled).to.equal(true);
    expect(zoomInButton.disabled).to.equal(false);

    zoomInButton.click();
    await element.updateComplete;
    expect(zoomControls.textContent).to.include("110%");
    expect(zoomOutButton.disabled).to.equal(false);

    zoomOutButton.click();
    await element.updateComplete;
    expect(zoomControls.textContent).to.include("Fit");
    expect(zoomOutButton.disabled).to.equal(true);

    zoomInButton.click();
    await element.updateComplete;
    expect(element._cropperImage.$getTransform()).to.not.deep.equal(initialImageTransform);
    resetButton.click();
    await element.updateComplete;
    expect(element._cropperImage.$getTransform()).to.deep.equal(initialImageTransform);
    expect(zoomControls.textContent).to.include("Fit");
    expect(zoomOutButton.disabled).to.equal(true);

    // Close the fixture without producing an upload file.
    element._close(null);
    expect(await resultPromise).to.equal(null);
  });

  it("exports the crop at the mandatory target dimensions", async () => {
    // Open the editor and replace the visual selection with a deterministic canvas.
    const element = await mountLitComponent("image-cropper", {
      label: "Logo",
      target: "logo",
    });
    const source = `
      <svg xmlns="http://www.w3.org/2000/svg" width="720" height="360">
        <rect width="720" height="360" fill="#0094ff" />
      </svg>
    `;
    const resultPromise = element.edit(new File([source], "community-logo.svg", { type: "image/svg+xml" }));
    await waitUntil(() => element._status === "ready", "the cropper should initialize");
    const requestedSize = {};
    element._selection = {
      async $toCanvas(options) {
        Object.assign(requestedSize, options);
        const canvas = document.createElement("canvas");
        canvas.width = options.width;
        canvas.height = options.height;
        return canvas;
      },
    };
    element._status = "ready";
    await element.updateComplete;

    // Apply the crop through the visible control.
    [...element.querySelectorAll("button")]
      .find((button) => button.textContent.trim() === "Apply crop")
      .click();
    const outputFile = await resultPromise;

    // The upload file uses the exact dimensions requested by the target.
    expect(requestedSize).to.deep.equal({ height: 360, width: 360 });
    expect(outputFile).to.be.instanceOf(File);
    expect(outputFile.name).to.equal("community-logo-cropped.webp");
    expect(outputFile.type).to.equal("image/webp");
    expect(outputFile.size).to.be.lessThan(1_000_000);
  });

  it("explains the size limit when the cropped image cannot fit under 1MB", async () => {
    // Open the editor and force every export attempt to exceed the upload limit.
    const element = await mountLitComponent("image-cropper", {
      label: "Logo",
      target: "logo",
    });
    const source = `
      <svg xmlns="http://www.w3.org/2000/svg" width="720" height="360">
        <rect width="720" height="360" fill="#0094ff" />
      </svg>
    `;
    const resultPromise = element.edit(new File([source], "community-logo.svg", { type: "image/svg+xml" }));
    await waitUntil(() => element._status === "ready", "the cropper should initialize");
    element._selection = {
      async $toCanvas() {
        return document.createElement("canvas");
      },
    };
    element._canvasToBlob = async () => new Blob([new Uint8Array(1_000_001)]);
    element._status = "ready";
    await element.updateComplete;

    // Apply the crop through the visible control.
    [...element.querySelectorAll("button")]
      .find((button) => button.textContent.trim() === "Apply crop")
      .click();
    await waitUntil(() => element._errorMessage !== "", "the editor should report the failure");

    // The size limit is called out and the user can adjust the crop and retry.
    expect(element.querySelector('[role="alert"]').textContent).to.include("1MB limit");
    expect(element._status).to.equal("ready");

    // Close the fixture without producing an upload file.
    element._close(null);
    expect(await resultPromise).to.equal(null);
  });

  it("disables pointer cropping while an export is processing", async () => {
    // Hold the canvas export open with a deterministic vendor surface.
    const element = await mountLitComponent("image-cropper", {
      target: "logo",
    });
    const cropperCanvas = { disabled: false };
    let rejectExport;
    element._cropper = {
      destroy() {},
      getCropperCanvas() {
        return cropperCanvas;
      },
    };
    element._selection = {
      $toCanvas() {
        return new Promise((resolve, reject) => {
          rejectExport = reject;
        });
      },
    };
    element._isOpen = true;
    element._status = "ready";
    await element.updateComplete;

    // Applying the crop disables vendor pointer and wheel handlers.
    const applyPromise = element._applyCrop();
    await element.updateComplete;
    expect(cropperCanvas.disabled).to.equal(true);

    // Tab from a displaced focus target returns to the busy modal.
    const outsideButton = document.createElement("button");
    document.body.prepend(outsideButton);
    outsideButton.focus();
    element._handleDocumentKeyDown(new KeyboardEvent("keydown", { cancelable: true, key: "Tab" }));
    expect(element.querySelector('[role="dialog"]').contains(document.activeElement)).to.equal(true);

    // A recoverable export failure restores crop interactions.
    rejectExport(new Error("Image export failed"));
    await applyPromise;
    expect(cropperCanvas.disabled).to.equal(false);
    expect(element._status).to.equal("ready");

    // Close the synthetic open state without restoring focus.
    element._close(null, { restoreFocus: false });
  });

  it("keeps the zoom level unchanged when the crop boundary rejects a zoom", async () => {
    // Arrange a zoom whose proposed image bounds no longer cover the selection.
    const element = await mountLitComponent("image-cropper", {
      target: "logo",
    });
    const cropperCanvas = document.createElement("div");
    let transformRejected = false;
    element._cropper = {
      destroy() {},
      getCropperCanvas() {
        return cropperCanvas;
      },
    };
    element._cropperImage = {
      $zoom() {
        element._handleImageTransform({
          detail: { matrix: [1, 0, 0, 1, 0, 0] },
          preventDefault() {
            transformRejected = true;
          },
        });
      },
      cloneNode() {
        const clone = document.createElement("div");
        clone.getBoundingClientRect = () => ({
          bottom: 90,
          height: 80,
          left: 10,
          right: 90,
          top: 10,
          width: 80,
        });
        return clone;
      },
      removeEventListener() {},
    };
    element._selection = {
      getBoundingClientRect: () => ({
        bottom: 100,
        height: 100,
        left: 0,
        right: 100,
        top: 0,
        width: 100,
      }),
    };
    element._status = "ready";
    element._zoomPercent = 110;

    // Apply the rejected zoom and preserve the last accepted visual state.
    element._zoom(-0.1);

    expect(transformRejected).to.equal(true);
    expect(element._zoomPercent).to.equal(110);
  });

  it("cancels an earlier edit when another image is selected", async () => {
    // Open two edits on the same reusable component.
    const element = await mountLitComponent("image-cropper", {
      target: "logo",
    });
    const firstResult = element.edit(new File(["first"], "first-logo.png", { type: "image/png" }));
    const secondResult = element.edit(new File(["second"], "second-logo.png", { type: "image/png" }));

    // The stale edit resolves without affecting the active modal.
    expect(await firstResult).to.equal(null);
    await waitUntil(() => element._isOpen, "the active crop editor should open");
    expect(element._isOpen).to.equal(true);

    // Close the active edit and verify modal scroll state is restored.
    element._close(null);
    expect(await secondResult).to.equal(null);
    expect(document.body.style.overflow).to.equal("");
  });

  it("supports keyboard positioning and Escape dismissal", async () => {
    // Open the cropper and provide deterministic image movement methods.
    const element = await mountLitComponent("image-cropper", {
      target: "open_graph",
    });
    const resultPromise = element.edit(new File(["source"], "social-image.png", { type: "image/png" }));
    await waitUntil(() => element._isOpen, "the crop editor should open");
    await element.updateComplete;
    const movements = [];
    const zooms = [];
    element._cropperImage = {
      $move(...movement) {
        movements.push(movement);
      },
      $zoom(amount) {
        zooms.push(amount);
      },
      removeEventListener() {},
    };
    element._status = "ready";
    await element.updateComplete;
    const stage = element.querySelector("[data-image-cropper-stage]");

    // Move and zoom from the keyboard while the crop area has focus.
    stage.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight" }));
    stage.dispatchEvent(new KeyboardEvent("keydown", { key: "+" }));

    // Verify keyboard input reaches the cropper movement methods.
    expect(movements).to.deep.equal([[8, 0]]);
    expect(zooms).to.deep.equal([0.1]);
    expect(element._zoomPercent).to.equal(110);

    stage.dispatchEvent(new KeyboardEvent("keydown", { key: "-" }));
    expect(zooms).to.deep.equal([0.1, -0.1]);
    expect(element._zoomPercent).to.equal(100);

    stage.dispatchEvent(new KeyboardEvent("keydown", { key: "-" }));
    expect(zooms).to.deep.equal([0.1, -0.1]);

    // Escape cancels the edit through the document-level modal listener.
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    expect(await resultPromise).to.equal(null);
    await element.updateComplete;
    expect(element.querySelector('[role="dialog"]')).to.equal(null);
  });
});
