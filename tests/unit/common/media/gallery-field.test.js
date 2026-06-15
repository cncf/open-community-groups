import { expect } from "@open-wc/testing";

import "/static/js/common/media/gallery-field.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("gallery-field", () => {
  useMountedElementsCleanup("gallery-field");

  let fetchMock;
  let swal;

  beforeEach(() => {
    fetchMock = mockFetch();
    swal = mockSwal();
  });

  afterEach(() => {
    fetchMock.restore();
    swal.restore();
  });

  it("reorders and removes gallery images while emitting updates", async () => {
    // Render the gallery-field fixture.
    const element = await mountLitComponent("gallery-field", {
      images: ["https://example.com/1.png", "https://example.com/2.png"],
      fieldName: "gallery",
    });
    const received = [];

    // Listen for the emitted event.
    element.addEventListener("images-change", (event) => {
      received.push(event.detail.images);
    });

    // Let the component finish rendering.
    element._reorderImages(0, 1);
    element._handleRemoveImage(0);
    await element.updateComplete;

    // The component stores the final order and emits each intermediate update.
    expect(element.images).to.deep.equal(["https://example.com/1.png"]);
    expect(received[0]).to.deep.equal(["https://example.com/2.png", "https://example.com/1.png"]);
    expect(received[1]).to.deep.equal(["https://example.com/1.png"]);
  });

  it("hides the add tile when the gallery reaches its limit", async () => {
    // Render the gallery-field fixture.
    const element = await mountLitComponent("gallery-field", {
      images: ["1", "2"],
      maxImages: 2,
    });

    // The add tile is unavailable once the max image count is reached.
    expect(element._showAddTile).to.equal(false);
    expect(element._remainingSlots).to.equal(0);
  });

  it("uploads gallery images through the shared image endpoint", async () => {
    // Mock the upload endpoint response.
    fetchMock.setImpl(async () => ({
      status: 201,
      async json() {
        return { url: "https://example.com/gallery.png" };
      },
    }));

    // Render the gallery-field fixture.
    const element = await mountLitComponent("gallery-field", {
      fieldName: "gallery",
    });
    const received = [];

    // Listen for image list updates.
    element.addEventListener("images-change", (event) => {
      received.push(event.detail.images);
    });

    // Upload a selected gallery image.
    await element._handleIncomingFiles([new File(["data"], "gallery.png", { type: "image/png" })]);
    await element.updateComplete;

    // The uploaded image is stored, emitted, and sent to the shared endpoint.
    expect(element.images).to.deep.equal(["https://example.com/gallery.png"]);
    expect(received).to.deep.equal([["https://example.com/gallery.png"]]);
    expect(fetchMock.calls).to.have.length(1);
    expect(fetchMock.calls[0][0]).to.equal("/images");
    expect(Array.from(fetchMock.calls[0][1].body.keys())).to.deep.equal(["file"]);
  });

  it("shows escaped server messages when gallery uploads fail", async () => {
    // Mock the upload endpoint with a server validation message.
    fetchMock.setImpl(async () => ({
      status: 422,
      async text() {
        return "Image is too large <strong>";
      },
    }));

    // Render the gallery-field fixture.
    const element = await mountLitComponent("gallery-field", {
      fieldName: "gallery",
    });

    // Upload a gallery image and wait for the alert to be shown.
    await element._handleIncomingFiles([new File(["data"], "gallery.png", { type: "image/png" })]);
    await element.updateComplete;

    // The server message is escaped and shown before the generic upload copy.
    const alert = swal.calls.at(-1);
    expect(alert.html).to.include("Image is too large &lt;strong&gt;");
    expect(alert.html).to.include("Something went wrong adding the images.");
  });
});
