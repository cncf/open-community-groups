import { expect } from "@open-wc/testing";

import { initializeGroupCheckInScanner } from "/static/js/dashboard/group/check-in/scanner.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("group check-in scanner controls", () => {
  beforeEach(() => {
    resetDom();
  });
  afterEach(() => {
    window.dispatchEvent(new Event("beforeunload"));
    delete window.__OCG_E2E_QR_SCANNER__;
    resetDom();
  });

  const renderFixture = () => {
    document.body.innerHTML = `
      <section data-group-check-in-root>
        <div data-group-check-in-scanner-view>
          <button data-group-check-in-open data-refresh-attendees-on-close data-event-id="event-a" data-event-date="Aug 24, 2026 · 9:00 AM CEST" data-event-location="Madrid" data-event-name="Event A" data-scan-url="/scan-a">A</button>
          <button data-group-check-in-open data-event-id="event-b" data-event-date="Aug 25, 2026 · 10:00 AM CEST" data-event-location="Virtual" data-event-name="Event B" data-scan-url="/scan-b">B</button>
        </div>
        <div id="group-check-in-scanner-modal" class="hidden" aria-hidden="true">
          <button data-group-check-in-close tabindex="-1">Overlay</button>
          <button data-group-check-in-close>Close</button>
          <label>
            <input type="checkbox" data-group-check-in-mute>
            <span data-group-check-in-mute-label>Mute sounds</span>
          </label>
          <h2 id="group-check-in-scanner-title">Scan attendees</h2>
          <h4 id="group-check-in-event-name"></h4>
          <p id="group-check-in-event-date"></p>
          <p id="group-check-in-event-location"></p>
          <video data-group-check-in-video></video>
          <div data-group-check-in-camera-unavailable class="hidden">
            <span data-group-check-in-camera-unavailable-message></span>
          </div>
          <div id="group-check-in-scanner-status" data-group-check-in-status></div>
          <div data-group-check-in-result class="hidden"></div>
          <select data-group-check-in-camera disabled>
            <option>Finding cameras...</option>
          </select>
          <label data-group-check-in-torch-control class="hidden">
            <input type="checkbox" data-group-check-in-torch disabled>
            <span>Torch</span>
          </label>
        </div>
      </section>
    `;
  };

  it("initializes lazy scanner content from its HTMX load target", () => {
    // Capture the scanner controls loaded by the attendees HTMX request.
    renderFixture();
    const scannerContent = document.querySelector("[data-group-check-in-root]").innerHTML;
    document.body.innerHTML = '<div id="attendees-content" data-group-check-in-root></div>';
    const attendeesRoot = document.getElementById("attendees-content");

    // Initialize the placeholder, then load scanner controls beneath the persistent root.
    initializeGroupCheckInScanner(attendeesRoot);
    expect(attendeesRoot.dataset.groupCheckInReady).to.equal(undefined);
    attendeesRoot.innerHTML = scannerContent;
    initializeGroupCheckInScanner(attendeesRoot.firstElementChild);

    // Verify the descendant HTMX target binds the opener on the attendees root.
    expect(attendeesRoot.dataset.groupCheckInReady).to.equal("true");
    window.__OCG_E2E_QR_SCANNER__ = class {
      constructor() {
        throw new Error("Scanner initialization failed");
      }
    };
    attendeesRoot.querySelector("[data-group-check-in-open]").click();
    expect(
      attendeesRoot.querySelector("#group-check-in-scanner-modal").classList.contains("hidden"),
    ).to.equal(false);
  });

  it("renders already checked-in feedback with the site error alert style", async () => {
    // Provide a scanner that exposes its decode callback.
    class FakeScanner {
      static instance;

      static async hasCamera() {
        return true;
      }
      static async listCameras() {
        return [];
      }

      constructor(_video, onDecode) {
        this.onDecode = onDecode;
        FakeScanner.instance = this;
      }

      destroy() {}
      async hasFlash() {
        return false;
      }
      async start() {}
    }

    const fetchMock = mockFetch({
      response: new Response(
        JSON.stringify({
          attendee: { name: "Paula Webb" },
          outcome: "already-checked-in",
          ticket_title: "Expo Pass",
        }),
        { headers: { "Content-Type": "application/json" } },
      ),
    });

    try {
      // Scan an attendee who was already checked in.
      renderFixture();
      let refreshCount = 0;
      document.querySelector("[data-group-check-in-root]").addEventListener(
        "refresh-event-attendees",
        () => {
          refreshCount += 1;
        },
      );
      window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
      initializeGroupCheckInScanner();
      document.querySelector("[data-group-check-in-open]").click();
      await new Promise((resolve) => setTimeout(resolve, 0));
      await FakeScanner.instance.onDecode({ data: "ocg-check-in:v1:event-a:credential" });

      // Verify the result uses a compact, centered, normal-weight error alert.
      const result = document.querySelector("[data-group-check-in-result]");
      const message = result.querySelector("p");
      expect(result.classList.contains("border")).to.equal(true);
      expect(result.classList.contains("border-red-800")).to.equal(true);
      expect(result.classList.contains("bg-red-100")).to.equal(true);
      expect(result.classList.contains("text-red-800")).to.equal(true);
      expect(result.classList.contains("text-center")).to.equal(true);
      expect(message.classList.contains("text-sm")).to.equal(true);
      expect(message.classList.contains("md:text-base")).to.equal(true);
      expect(message.classList.contains("font-normal")).to.equal(true);
      expect(result.textContent).to.include("Already checked in");
      expect(result.textContent).to.include("Paula Webb · Expo Pass");

      // Closing an unchanged session leaves the attendees list untouched.
      document.querySelector("[data-group-check-in-close]").click();
      expect(refreshCount).to.equal(0);
    } finally {
      fetchMock.restore();
    }
  });

  it("does not refresh attendees after a failed scan", async () => {
    // Provide a scanner that exposes its decode callback.
    class FakeScanner {
      static instance;

      static async hasCamera() {
        return true;
      }
      static async listCameras() {
        return [];
      }

      constructor(_video, onDecode) {
        this.onDecode = onDecode;
        FakeScanner.instance = this;
      }

      destroy() {}
      async hasFlash() {
        return false;
      }
      async start() {}
    }

    // Submit an invalid code and close its unchanged scanner session.
    renderFixture();
    const root = document.querySelector("[data-group-check-in-root]");
    let refreshCount = 0;
    root.addEventListener("refresh-event-attendees", () => {
      refreshCount += 1;
    });
    window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
    initializeGroupCheckInScanner();
    root.querySelector("[data-group-check-in-open]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    await FakeScanner.instance.onDecode({ data: "invalid-code" });
    root.querySelector("[data-group-check-in-close]").click();

    // Failed scans do not request an attendee refresh.
    expect(refreshCount).to.equal(0);
  });

  it("refreshes attendees only after closing a changed event-tab scanner", async () => {
    // Provide a scanner that exposes its decode callback.
    class FakeScanner {
      static instance;

      static async hasCamera() {
        return true;
      }
      static async listCameras() {
        return [];
      }

      constructor(_video, onDecode) {
        this.onDecode = onDecode;
        FakeScanner.instance = this;
      }

      destroy() {}
      async hasFlash() {
        return false;
      }
      async start() {}
    }

    const fetchMock = mockFetch({
      impl: async () =>
        new Response(
          JSON.stringify({
            attendee: { name: "Paula Webb" },
            outcome: "checked-in",
            ticket_title: "Expo Pass",
          }),
          { headers: { "Content-Type": "application/json" } },
        ),
    });

    try {
      // Open the scanner and observe attendee refresh requests.
      renderFixture();
      const root = document.querySelector("[data-group-check-in-root]");
      let refreshCount = 0;
      root.addEventListener("refresh-event-attendees", () => {
        refreshCount += 1;
      });
      window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
      initializeGroupCheckInScanner();
      root.querySelector("[data-group-check-in-open]").click();
      await new Promise((resolve) => setTimeout(resolve, 0));

      // Complete a new check-in without interrupting the active scanner.
      await FakeScanner.instance.onDecode({ data: "ocg-check-in:v1:event-a:credential" });
      expect(refreshCount).to.equal(0);

      // Closing refreshes the attendees region once and clears the dirty state.
      root.querySelector("[data-group-check-in-close]").click();
      expect(refreshCount).to.equal(1);
      root.querySelector("[data-group-check-in-close]").click();
      expect(refreshCount).to.equal(1);

      // The mobile Check-In opener closes without emitting the desktop refresh.
      root.querySelectorAll("[data-group-check-in-open]")[1].click();
      await new Promise((resolve) => setTimeout(resolve, 0));
      await FakeScanner.instance.onDecode({ data: "ocg-check-in:v1:event-b:credential" });
      root.querySelector("[data-group-check-in-close]").click();
      expect(refreshCount).to.equal(1);
    } finally {
      fetchMock.restore();
    }
  });

  it("does not refresh attendees when HTMX cleans up a changed scanner", async () => {
    // Provide a scanner that exposes its decode callback.
    class FakeScanner {
      static instance;

      static async hasCamera() {
        return true;
      }
      static async listCameras() {
        return [];
      }

      constructor(_video, onDecode) {
        this.onDecode = onDecode;
        FakeScanner.instance = this;
      }

      destroy() {}
      async hasFlash() {
        return false;
      }
      async start() {}
    }

    const fetchMock = mockFetch({
      response: new Response(
        JSON.stringify({
          attendee: { name: "Paula Webb" },
          outcome: "checked-in",
          ticket_title: "Expo Pass",
        }),
        { headers: { "Content-Type": "application/json" } },
      ),
    });

    try {
      // Change attendee state in an active scanner session.
      renderFixture();
      const root = document.querySelector("[data-group-check-in-root]");
      let refreshCount = 0;
      root.addEventListener("refresh-event-attendees", () => {
        refreshCount += 1;
      });
      window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
      initializeGroupCheckInScanner();
      root.querySelector("[data-group-check-in-open]").click();
      await new Promise((resolve) => setTimeout(resolve, 0));
      await FakeScanner.instance.onDecode({ data: "ocg-check-in:v1:event-a:credential" });

      // HTMX cleanup closes the modal without starting a redundant refresh.
      root.dispatchEvent(new Event("htmx:beforeCleanupElement", { bubbles: true }));
      expect(refreshCount).to.equal(0);
      expect(
        document.getElementById("group-check-in-scanner-modal").classList.contains("hidden"),
      ).to.equal(true);
    } finally {
      fetchMock.restore();
    }
  });

  it("continues scanning when audio initialization fails", async () => {
    // Provide a scanner that can start without audio feedback.
    class FakeScanner {
      static startCount = 0;

      static async hasCamera() {
        return true;
      }
      static async listCameras() {
        return [];
      }

      destroy() {}
      async hasFlash() {
        return false;
      }
      async start() {
        FakeScanner.startCount += 1;
      }
    }

    // Make audio setup fail while leaving camera setup available.
    const OriginalAudioContext = window.AudioContext;
    Object.defineProperty(window, "AudioContext", {
      configurable: true,
      value: class {
        constructor() {
          throw new Error("Audio context unavailable");
        }
      },
    });

    try {
      // Open the scanner with the failing audio implementation.
      renderFixture();
      window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
      initializeGroupCheckInScanner();
      document.querySelector("[data-group-check-in-open]").click();
      await new Promise((resolve) => setTimeout(resolve, 0));

      // Verify camera scanning reaches its ready state.
      expect(FakeScanner.startCount).to.equal(1);
      expect(document.querySelector("[data-group-check-in-status]").textContent).to.equal(
        "Hold an attendee QR code inside the frame.",
      );
    } finally {
      // Restore the browser audio constructor.
      Object.defineProperty(window, "AudioContext", {
        configurable: true,
        value: OriginalAudioContext,
      });
    }
  });

  it("continues scanning when optional camera controls fail", async () => {
    // Provide a working decoder whose optional camera capabilities reject.
    class FakeScanner {
      static instance;

      static async hasCamera() {
        return true;
      }
      static async listCameras() {
        throw new Error("Camera enumeration unavailable");
      }

      constructor() {
        this.destroyCount = 0;
        this.startCount = 0;
        FakeScanner.instance = this;
      }

      destroy() {
        this.destroyCount += 1;
      }
      async hasFlash() {
        throw new Error("Flash capability unavailable");
      }
      async start() {
        this.startCount += 1;
      }
    }

    // Open the scanner and allow optional capability discovery to finish.
    renderFixture();
    window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
    initializeGroupCheckInScanner();
    document.querySelector("[data-group-check-in-open]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    // Verify decoding stays active while unavailable controls remain disabled.
    expect(FakeScanner.instance.startCount).to.equal(1);
    expect(FakeScanner.instance.destroyCount).to.equal(0);
    expect(document.querySelector("[data-group-check-in-status]").textContent).to.equal(
      "Hold an attendee QR code inside the frame.",
    );
    expect(document.querySelector("[data-group-check-in-camera]").disabled).to.equal(true);
    expect(document.querySelector("[data-group-check-in-torch]").disabled).to.equal(true);
  });

  it("keeps delayed startup from replacing a newer scanner session", async () => {
    // Delay the first camera check while allowing the next session to start.
    let releaseFirstCameraCheck;
    const firstCameraCheck = new Promise((resolve) => {
      releaseFirstCameraCheck = resolve;
    });

    class FakeScanner {
      static cameraCheckCount = 0;
      static instances = [];

      static async hasCamera() {
        FakeScanner.cameraCheckCount += 1;
        return FakeScanner.cameraCheckCount === 1 ? firstCameraCheck : true;
      }

      static async listCameras() {
        return [{ id: "new-camera", label: "New camera" }];
      }

      constructor(video) {
        this.destroyCount = 0;
        this.startCount = 0;
        this.video = video;
        FakeScanner.instances.push(this);
      }

      destroy() {
        this.destroyCount += 1;
      }
      async hasFlash() {
        return false;
      }
      async start() {
        this.startCount += 1;
      }
    }

    // Initialize two event triggers against the controllable scanner.
    renderFixture();
    window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
    initializeGroupCheckInScanner();
    const triggers = document.querySelectorAll("[data-group-check-in-open]");
    const mute = document.querySelector("[data-group-check-in-mute]");

    // Mute sound, then open a second event before the first camera check resolves.
    triggers[0].click();
    expect(mute.checked).to.equal(false);
    mute.click();
    expect(mute.checked).to.equal(true);
    expect(document.querySelector("[data-group-check-in-mute-label]").textContent).to.equal("Mute sounds");
    triggers[1].click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    releaseFirstCameraCheck(true);
    await new Promise((resolve) => setTimeout(resolve, 0));

    // Verify only the newer session starts and owns the modal state.
    expect(FakeScanner.instances[0].destroyCount).to.equal(1);
    expect(FakeScanner.instances[0].startCount).to.equal(0);
    expect(FakeScanner.instances[1].startCount).to.equal(1);
    expect(FakeScanner.instances[0].video).to.not.equal(FakeScanner.instances[1].video);
    expect(FakeScanner.instances[0].video.isConnected).to.equal(false);
    expect(FakeScanner.instances[1].video).to.equal(document.querySelector("[data-group-check-in-video]"));
    expect(document.querySelector("[data-group-check-in-camera]").value).to.equal("new-camera");
    expect(document.getElementById("group-check-in-scanner-title").textContent).to.equal(
      "Scan attendees",
    );
    expect(document.getElementById("group-check-in-event-name").textContent).to.equal("Event B");
    expect(document.getElementById("group-check-in-event-date").textContent).to.equal(
      "Aug 25, 2026 · 10:00 AM CEST",
    );
    expect(document.getElementById("group-check-in-event-location").textContent).to.equal("Virtual");
    expect(mute.checked).to.equal(false);
    expect(document.activeElement).to.equal(
      document.querySelector('[data-group-check-in-close]:not([tabindex="-1"])'),
    );

    // Close the current session and restore focus to its trigger.
    document.querySelector("[data-group-check-in-close]").click();
    expect(document.activeElement).to.equal(triggers[1]);
  });

  it("keeps scanner constructor failures dismissible", async () => {
    // Provide a scanner that fails during construction.
    class FakeScanner {
      constructor() {
        throw new Error("Scanner initialization failed");
      }
    }

    // Open the event scanner with the failing implementation.
    renderFixture();
    window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
    initializeGroupCheckInScanner();
    const trigger = document.querySelector("[data-group-check-in-open]");
    trigger.click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    // Verify the modal remains open with actionable failure guidance.
    const modal = document.getElementById("group-check-in-scanner-modal");
    const unavailable = document.querySelector("[data-group-check-in-camera-unavailable]");
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(document.querySelector("[data-group-check-in-status]").textContent).to.equal(
      "Camera unavailable.",
    );
    expect(unavailable.classList.contains("hidden")).to.equal(false);
    expect(unavailable.textContent.trim()).to.equal(
      "The camera could not be started. Try another camera or use manual check-in.",
    );
    expect(document.querySelector("[data-group-check-in-camera]").textContent.trim()).to.equal(
      "No cameras detected",
    );

    // Close the failed scanner and restore page state.
    document.querySelector("[data-group-check-in-close]").click();
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(document.body.style.overflow).to.equal("");
    expect(document.activeElement).to.equal(trigger);
  });

  it("renders a waiting state when no camera is available", async () => {
    // Provide a scanner implementation without an available camera.
    class FakeScanner {
      static async hasCamera() {
        return false;
      }

      destroy() {}
    }

    // Open the scanner and allow camera discovery to settle.
    renderFixture();
    window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
    initializeGroupCheckInScanner();
    document.querySelector("[data-group-check-in-open]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    // Verify the modal preserves the manual fallback with explicit camera states.
    expect(document.querySelector("[data-group-check-in-status]").textContent).to.equal(
      "Waiting for a camera...",
    );
    expect(document.querySelector("[data-group-check-in-camera-unavailable-message]").textContent).to.equal(
      "No camera was found. Connect a camera or use manual check-in.",
    );
    expect(document.querySelector("[data-group-check-in-camera]").disabled).to.equal(true);
    expect(document.querySelector("[data-group-check-in-camera]").textContent.trim()).to.equal(
      "No cameras detected",
    );
    expect(document.querySelector("[data-group-check-in-mute]").disabled).to.equal(true);
  });

  it("rebinds controls from an HTMX history snapshot", async () => {
    // Provide a scanner that records successful startup.
    class FakeScanner {
      static startCount = 0;

      static async hasCamera() {
        return true;
      }
      static async listCameras() {
        return [];
      }

      destroy() {}
      async hasFlash() {
        return false;
      }
      async start() {
        FakeScanner.startCount += 1;
      }
    }

    // Capture initialized markup as an HTMX history snapshot.
    renderFixture();
    window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
    initializeGroupCheckInScanner();
    const cachedRoot = document.querySelector("[data-group-check-in-root]").cloneNode(true);
    document.querySelector("[data-group-check-in-root]").replaceWith(cachedRoot);

    // Restore the cached root and reopen its scanner.
    cachedRoot.dispatchEvent(new Event("htmx:historyRestore", { bubbles: true }));
    cachedRoot.querySelector("[data-group-check-in-open]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    // Verify restored controls start a fresh scanner session.
    expect(FakeScanner.startCount).to.equal(1);
  });

  it("uses checked state for the torch toggle", async () => {
    // Provide a scanner with controllable flash state.
    class FakeScanner {
      static async hasCamera() {
        return true;
      }
      static async listCameras() {
        return [{ id: "camera", label: "Camera" }];
      }

      constructor() {
        this.flashOn = false;
      }

      destroy() {}
      async hasFlash() {
        return true;
      }
      isFlashOn() {
        return this.flashOn;
      }
      async start() {}
      async toggleFlash() {
        this.flashOn = !this.flashOn;
      }
    }

    // Open a flash-capable scanner and read its torch control.
    renderFixture();
    window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
    initializeGroupCheckInScanner();
    document.querySelector("[data-group-check-in-open]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    const torch = document.querySelector("[data-group-check-in-torch]");
    const torchControl = document.querySelector("[data-group-check-in-torch-control]");

    // Toggle the torch and verify its native checked state.
    expect(torchControl.classList.contains("hidden")).to.equal(false);
    expect(torchControl.classList.contains("inline-flex")).to.equal(true);
    expect(torch.disabled).to.equal(false);
    expect(torch.checked).to.equal(false);
    torch.click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(torch.checked).to.equal(true);
    expect(torchControl.textContent.trim()).to.equal("Torch");

    // Close the scanner and verify the switch resets and is hidden.
    document.querySelector("[data-group-check-in-close]").click();
    expect(torch.checked).to.equal(false);
    expect(torch.disabled).to.equal(true);
    expect(torchControl.classList.contains("hidden")).to.equal(true);
  });

  it("serializes camera and torch hardware changes", async () => {
    // Hold camera and torch changes open with controllable promises.
    let releaseCameraChange;
    let releaseTorchToggle;
    const cameraChange = new Promise((resolve) => {
      releaseCameraChange = resolve;
    });
    const torchToggle = new Promise((resolve) => {
      releaseTorchToggle = resolve;
    });

    // Provide a scanner that records requested hardware changes.
    class FakeScanner {
      static cameraChanges = [];
      static toggleCount = 0;

      static async hasCamera() {
        return true;
      }
      static async listCameras() {
        return [
          { id: "camera-a", label: "Camera A" },
          { id: "camera-b", label: "Camera B" },
        ];
      }

      constructor() {
        this.flashOn = false;
      }

      destroy() {}
      async hasFlash() {
        return true;
      }
      isFlashOn() {
        return this.flashOn;
      }
      async setCamera(cameraId) {
        FakeScanner.cameraChanges.push(cameraId);
        await cameraChange;
      }
      async start() {}
      async toggleFlash() {
        FakeScanner.toggleCount += 1;
        await torchToggle;
        this.flashOn = !this.flashOn;
      }
    }

    // Open the scanner with both hardware controls available.
    renderFixture();
    window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
    initializeGroupCheckInScanner();
    document.querySelector("[data-group-check-in-open]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    const camera = document.querySelector("[data-group-check-in-camera]");
    const torch = document.querySelector("[data-group-check-in-torch]");

    // Start a torch change and attempt overlapping hardware actions.
    torch.click();
    expect(camera.disabled).to.equal(true);
    expect(torch.disabled).to.equal(true);
    torch.click();
    camera.value = "camera-b";
    camera.dispatchEvent(new Event("change", { bubbles: true }));
    expect(FakeScanner.toggleCount).to.equal(1);
    expect(FakeScanner.cameraChanges).to.deep.equal([]);

    // Finish the torch change and verify both controls recover.
    releaseTorchToggle();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(camera.disabled).to.equal(false);
    expect(torch.disabled).to.equal(false);

    // Start a camera change and attempt an overlapping torch action.
    camera.dispatchEvent(new Event("change", { bubbles: true }));
    expect(FakeScanner.cameraChanges).to.deep.equal(["camera-b"]);
    expect(camera.disabled).to.equal(true);
    expect(torch.disabled).to.equal(true);
    torch.click();
    expect(FakeScanner.toggleCount).to.equal(1);

    // Finish the camera change and verify both controls recover.
    releaseCameraChange();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(camera.disabled).to.equal(false);
    expect(torch.disabled).to.equal(false);
  });

  it("tears down an open scanner restored from the browser cache", async () => {
    // Provide a scanner that records lifecycle teardown.
    class FakeScanner {
      static instance;

      static async hasCamera() {
        return true;
      }
      static async listCameras() {
        return [];
      }

      constructor() {
        this.destroyCount = 0;
        FakeScanner.instance = this;
      }

      destroy() {
        this.destroyCount += 1;
      }
      async hasFlash() {
        return false;
      }
      async start() {}
    }

    // Open the scanner before simulating a browser cache restore.
    renderFixture();
    window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
    initializeGroupCheckInScanner();
    document.querySelector("[data-group-check-in-open]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    // Restore the page from cache while the scanner is active.
    window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }));

    // Verify the scanner, modal, and scroll lock are cleaned up.
    expect(FakeScanner.instance.destroyCount).to.equal(1);
    expect(document.getElementById("group-check-in-scanner-modal").classList.contains("hidden")).to.equal(
      true,
    );
    expect(document.body.style.overflow).to.equal("");
  });
});
