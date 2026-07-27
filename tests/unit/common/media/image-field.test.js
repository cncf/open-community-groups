import { expect } from "@open-wc/testing";

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
    const selectedFile = new File(["selected"], "selected-badge.png", { type: "image/png" });
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

  it("shows the generic supported formats text for banner images", async () => {
    // Mount a standard banner image field with generic guidance.
    const element = await mountLitComponent("image-field", {
      helpPrefixText: "Size required 2428 x 192 px.",
      imageKind: "banner",
      target: "banner",
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
});
