import { expect } from "@open-wc/testing";

import { initializeGroupCheckInScanner } from "/static/js/dashboard/group/check-in/scanner.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx } from "/tests/unit/test-utils/globals.js";

describe("group check-in scanner controls", () => {
  let htmx;

  beforeEach(() => {
    resetDom();
    htmx = mockHtmx();
  });
  afterEach(() => {
    window.dispatchEvent(new Event("beforeunload"));
    delete window.__OCG_E2E_QR_SCANNER__;
    htmx.restore();
    resetDom();
  });

  const renderFixture = () => {
    document.body.innerHTML = `
      <section data-group-check-in-root>
        <div data-group-check-in-scanner-view>
          <button data-group-check-in-open data-event-id="event-a" data-event-name="Event A" data-scan-url="/scan-a" data-attendees-url="/events/event-a/attendees">A</button>
          <button data-group-check-in-open data-event-id="event-b" data-event-name="Event B" data-scan-url="/scan-b" data-attendees-url="/events/event-b/attendees">B</button>
        </div>
        <div id="group-check-in-scanner-modal" class="hidden" aria-hidden="true">
          <button data-group-check-in-close tabindex="-1">Overlay</button>
          <button data-group-check-in-mute><span data-group-check-in-mute-label>Mute sounds</span></button>
          <h2 id="group-check-in-scanner-title"></h2>
          <video data-group-check-in-video></video>
          <div data-group-check-in-status></div>
          <div data-group-check-in-result class="hidden"></div>
          <select data-group-check-in-camera></select>
          <button data-group-check-in-torch class="hidden">Turn torch on</button>
          <a data-group-check-in-manual href="/dashboard/group?tab=events"></a>
        </div>
        <div class="hidden" data-group-check-in-manual-panel tabindex="-1">
          <h2 data-group-check-in-manual-title></h2>
          <button data-group-check-in-manual-back>Back to check-in events</button>
          <div class="hidden" data-group-check-in-manual-status role="status"></div>
          <div id="attendees-content"></div>
        </div>
      </section>
    `;
  };

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

    // Open a second event before the first camera check resolves.
    triggers[0].click();
    mute.click();
    expect(mute.textContent).to.equal("Unmute sounds");
    expect(mute.hasAttribute("aria-label")).to.equal(false);
    expect(mute.hasAttribute("aria-pressed")).to.equal(false);
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
    expect(document.getElementById("group-check-in-scanner-title").textContent).to.equal("Event B");
    expect(mute.textContent).to.equal("Mute sounds");
    expect(document.activeElement).to.equal(document.querySelector("[data-group-check-in-mute]"));

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
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(document.querySelector("[data-group-check-in-status]").textContent).to.equal(
      "The camera could not be started. Try another camera or use manual check-in.",
    );

    // Close the failed scanner and restore page state.
    document.querySelector("[data-group-check-in-close]").click();
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(document.body.style.overflow).to.equal("");
    expect(document.activeElement).to.equal(trigger);
  });

  it("loads selected attendees for manual check-in and returns to the scanner", async () => {
    // Provide a camera-less scanner so manual check-in remains available.
    class FakeScanner {
      static async hasCamera() {
        return false;
      }

      destroy() {}
    }

    // Open the scanner for the first event.
    renderFixture();
    window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
    initializeGroupCheckInScanner();
    const trigger = document.querySelector("[data-group-check-in-open]");
    trigger.click();

    // Switch to the selected event's manual attendee panel.
    document.querySelector("[data-group-check-in-manual]").click();
    const manualPanel = document.querySelector("[data-group-check-in-manual-panel]");
    const manualStatus = document.querySelector("[data-group-check-in-manual-status]");
    const attendeesContent = document.getElementById("attendees-content");

    // Verify HTMX loads the expected attendee table and transfers focus.
    expect(htmx.ajaxCalls).to.deep.equal([
      [
        "GET",
        "/events/event-a/attendees",
        {
          indicator: "#dashboard-spinner",
          swap: "innerHTML",
          target: "#attendees-content",
        },
      ],
    ]);
    expect(manualPanel.classList.contains("hidden")).to.equal(false);
    expect(
      document.querySelector("[data-group-check-in-scanner-view]").classList.contains("hidden"),
    ).to.equal(true);
    expect(document.activeElement).to.equal(manualPanel);
    expect(attendeesContent.hasAttribute("aria-live")).to.equal(false);
    expect(attendeesContent.getAttribute("aria-busy")).to.equal("true");
    expect(manualStatus.classList.contains("hidden")).to.equal(false);
    expect(manualStatus.textContent).to.equal("Loading attendees…");

    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(attendeesContent.hasAttribute("aria-busy")).to.equal(false);
    expect(manualStatus.classList.contains("hidden")).to.equal(true);

    // Return to the scanner view and restore focus to the event trigger.
    document.querySelector("[data-group-check-in-manual-back]").click();
    expect(manualPanel.classList.contains("hidden")).to.equal(true);
    expect(
      document.querySelector("[data-group-check-in-scanner-view]").classList.contains("hidden"),
    ).to.equal(false);
    expect(document.activeElement).to.equal(trigger);
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

  it("uses action labels for torch state", async () => {
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

    // Toggle the torch and verify the next action.
    torch.click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(torch.hasAttribute("aria-pressed")).to.equal(false);
    expect(torch.textContent).to.equal("Turn torch off");

    // Close the scanner and verify the action resets.
    document.querySelector("[data-group-check-in-close]").click();
    expect(torch.hasAttribute("aria-pressed")).to.equal(false);
    expect(torch.textContent).to.equal("Turn torch on");
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
    torch.dispatchEvent(new Event("click", { bubbles: true }));
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
    torch.dispatchEvent(new Event("click", { bubbles: true }));
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
