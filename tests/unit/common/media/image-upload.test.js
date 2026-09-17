import { expect } from "@open-wc/testing";

import { isAnimatedGif, isGifFile } from "/static/js/common/media/image-upload.js";

/** Builds a GIF file from a header and a list of block byte arrays. */
const createGifFile = (blocks, { name = "image.gif", type = "image/gif" } = {}) => {
  // Header, 2 × 2 logical screen, and a two-entry global colour table.
  const header = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 2, 0, 2, 0, 0x80, 0, 0, 0, 0, 0, 255, 255, 255];
  return new File([new Uint8Array([...header, ...blocks.flat(), 0x3b])], name, { type });
};

// Image descriptor covering the screen, minimum code size, one data sub-block, terminator.
const IMAGE_BLOCK = [0x2c, 0, 0, 0, 0, 2, 0, 2, 0, 0x00, 0x02, 0x02, 0x44, 0x01, 0x00];
// Graphic control extension with a short delay.
const GRAPHIC_CONTROL_BLOCK = [0x21, 0xf9, 0x04, 0x00, 0x0a, 0x00, 0x00, 0x00];
// Netscape looping application extension.
const LOOP_BLOCK = [0x21, 0xff, 0x0b, ...new TextEncoder().encode("NETSCAPE2.0"), 0x03, 0x01, 0, 0, 0];

describe("image-upload", () => {
  it("detects GIF files by type or extension", () => {
    expect(isGifFile(new File([""], "photo.GIF", { type: "" }))).to.equal(true);
    expect(isGifFile(new File([""], "photo", { type: "image/gif" }))).to.equal(true);
    expect(isGifFile(new File([""], "photo.png", { type: "image/png" }))).to.equal(false);
  });

  it("treats single-frame GIFs as static", async () => {
    const file = createGifFile([GRAPHIC_CONTROL_BLOCK, IMAGE_BLOCK]);

    expect(await isAnimatedGif(file)).to.equal(false);
  });

  it("detects multi-frame GIFs as animated", async () => {
    // Frames may carry local colour tables, which the scanner must skip.
    const localTableImage = [...IMAGE_BLOCK];
    localTableImage[9] = 0x80;
    localTableImage.splice(10, 0, 0, 0, 0, 255, 255, 255);
    const file = createGifFile([
      LOOP_BLOCK,
      GRAPHIC_CONTROL_BLOCK,
      IMAGE_BLOCK,
      GRAPHIC_CONTROL_BLOCK,
      localTableImage,
    ]);

    expect(await isAnimatedGif(file)).to.equal(true);
  });

  it("treats truncated or non-GIF data as static", async () => {
    // A frame cut off mid-stream and a PNG signature both fall back to the safe answer.
    const truncated = new File([new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 2, 0])], "cut.gif", {
      type: "image/gif",
    });
    const png = new File(
      [new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0, 0])],
      "a.gif",
      {
        type: "image/gif",
      },
    );

    expect(await isAnimatedGif(truncated)).to.equal(false);
    expect(await isAnimatedGif(png)).to.equal(false);
  });

  it("treats files that cannot be read as static", async () => {
    // A file removed after selection rejects on read; the later decode step reports it.
    const file = createGifFile([IMAGE_BLOCK, IMAGE_BLOCK]);
    file.arrayBuffer = () => Promise.reject(new DOMException("gone", "NotReadableError"));

    expect(await isAnimatedGif(file)).to.equal(false);
  });

  it("only inspects files identified as GIF", async () => {
    // Animated GIF bytes under another name and type are never read.
    const file = createGifFile([GRAPHIC_CONTROL_BLOCK, IMAGE_BLOCK, GRAPHIC_CONTROL_BLOCK, IMAGE_BLOCK], {
      name: "photo.png",
      type: "image/png",
    });
    file.arrayBuffer = () => {
      throw new Error("should not read non-GIF files");
    };

    expect(await isAnimatedGif(file)).to.equal(false);
  });
});
