/**
 * Replaces the Screen Wake Lock API with a counter.
 * Tests read `window.__OCG_E2E_WAKE_LOCK__`, which holds the requests and live locks.
 * @param {import("@playwright/test").Page} page - Page before navigation.
 */
export const installFakeWakeLock = async (page) => {
  await page.addInitScript(() => {
    const state = { held: 0, requests: 0 };
    window.__OCG_E2E_WAKE_LOCK__ = state;
    Object.defineProperty(navigator, "wakeLock", {
      configurable: true,
      value: {
        request: async () => {
          state.requests += 1;
          state.held += 1;
          const lock = {
            release: async () => {
              if (!lock.released) state.held -= 1;
              lock.released = true;
            },
            released: false,
          };
          return lock;
        },
      },
    });
  });
};

/**
 * Replaces the browser QR scanner with a deterministic fake camera.
 * Tests decode codes through `window.__OCG_E2E_QR_SCANNER__.last.onDecode`.
 * @param {import("@playwright/test").Page} page - Page before navigation.
 * @param {{ cameras?: { id: string, label: string }[], startError?: string }} [options] - Cameras
 * the fake lists, and the error name its start rejects with.
 */
export const installFakeQrScanner = async (
  page,
  { cameras = [{ id: "test-camera", label: "Test camera" }], startError } = {},
) => {
  await page.addInitScript(
    ({ fakeCameras, fakeStartError }) => {
      class FakeQrScanner {
        static last;

        static async hasCamera() {
          return true;
        }

        static async listCameras() {
          return fakeCameras;
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
        async start() {
          if (fakeStartError) throw Object.assign(new Error("Camera failed"), { name: fakeStartError });
        }
        async toggleFlash() {}
      }

      window.__OCG_E2E_QR_SCANNER__ = FakeQrScanner;
    },
    { fakeCameras: cameras, fakeStartError: startError },
  );
};
