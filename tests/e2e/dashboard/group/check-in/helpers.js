/**
 * Replaces the browser QR scanner with a deterministic fake camera.
 * Tests decode codes through `window.__OCG_E2E_QR_SCANNER__.last.onDecode`.
 */
export const installFakeQrScanner = async (page) => {
  await page.addInitScript(() => {
    class FakeQrScanner {
      static last;

      static async hasCamera() {
        return true;
      }

      static async listCameras() {
        return [{ id: "test-camera", label: "Test camera" }];
      }

      constructor(_video, onDecode) {
        this.onDecode = onDecode;
        FakeQrScanner.last = this;
      }

      destroy() {}
      async hasFlash() {
        return false;
      }
      isFlashOn() {
        return false;
      }
      async setCamera() {}
      async start() {}
      async toggleFlash() {}
    }

    window.__OCG_E2E_QR_SCANNER__ = FakeQrScanner;
  });
};
