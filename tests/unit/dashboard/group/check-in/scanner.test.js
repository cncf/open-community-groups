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
          <button data-group-check-in-mute aria-pressed="false"><span data-group-check-in-mute-label>Sound on</span></button>
          <h2 id="group-check-in-scanner-title"></h2>
          <video data-group-check-in-video></video>
          <div data-group-check-in-status></div>
          <div data-group-check-in-result class="hidden"></div>
          <select data-group-check-in-camera></select>
          <button data-group-check-in-torch class="hidden" aria-pressed="false">Turn torch on</button>
          <a data-group-check-in-manual href="/dashboard/group?tab=events"></a>
        </div>
        <div class="hidden" data-group-check-in-manual-panel tabindex="-1">
          <h2 data-group-check-in-manual-title></h2>
          <button data-group-check-in-manual-back>Back to scanner</button>
          <div id="attendees-content"></div>
        </div>
      </section>
    `;
  };

  it("continues scanning when audio initialization fails", async () => {
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
      renderFixture();
      window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
      initializeGroupCheckInScanner();
      document.querySelector("[data-group-check-in-open]").click();
      await new Promise((resolve) => setTimeout(resolve, 0));

      expect(FakeScanner.startCount).to.equal(1);
      expect(
        document.querySelector("[data-group-check-in-status]").textContent,
      ).to.equal("Hold an attendee QR code inside the frame.");
    } finally {
      Object.defineProperty(window, "AudioContext", {
        configurable: true,
        value: OriginalAudioContext,
      });
    }
  });

  it("keeps delayed startup from replacing a newer scanner session", async () => {
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

      constructor() {
        this.destroyCount = 0;
        this.startCount = 0;
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

    renderFixture();
    window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
    initializeGroupCheckInScanner();
    const triggers = document.querySelectorAll("[data-group-check-in-open]");
    const mute = document.querySelector("[data-group-check-in-mute]");

    triggers[0].click();
    mute.click();
    expect(mute.getAttribute("aria-pressed")).to.equal("true");
    triggers[1].click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    releaseFirstCameraCheck(true);
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(FakeScanner.instances[0].destroyCount).to.equal(1);
    expect(FakeScanner.instances[0].startCount).to.equal(0);
    expect(FakeScanner.instances[1].startCount).to.equal(1);
    expect(
      document.querySelector("[data-group-check-in-camera]").value,
    ).to.equal("new-camera");
    expect(
      document.getElementById("group-check-in-scanner-title").textContent,
    ).to.equal("Event B");
    expect(mute.getAttribute("aria-pressed")).to.equal("false");
    expect(mute.textContent).to.equal("Sound on");
    expect(document.activeElement).to.equal(
      document.querySelector("[data-group-check-in-mute]"),
    );
    document.querySelector("[data-group-check-in-close]").click();
    expect(document.activeElement).to.equal(triggers[1]);
  });

  it("keeps scanner constructor failures dismissible", async () => {
    class FakeScanner {
      constructor() {
        throw new Error("Scanner initialization failed");
      }
    }

    renderFixture();
    window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
    initializeGroupCheckInScanner();
    const trigger = document.querySelector("[data-group-check-in-open]");
    trigger.click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    const modal = document.getElementById("group-check-in-scanner-modal");
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(
      document.querySelector("[data-group-check-in-status]").textContent,
    ).to.equal(
      "The camera could not be started. Try another camera or use manual check-in.",
    );

    document.querySelector("[data-group-check-in-close]").click();
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(document.body.style.overflow).to.equal("");
    expect(document.activeElement).to.equal(trigger);
  });

  it("loads selected attendees for manual check-in and returns to the scanner", async () => {
    class FakeScanner {
      static async hasCamera() {
        return false;
      }

      destroy() {}
    }

    renderFixture();
    window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
    initializeGroupCheckInScanner();
    const trigger = document.querySelector("[data-group-check-in-open]");
    trigger.click();

    document.querySelector("[data-group-check-in-manual]").click();
    const manualPanel = document.querySelector(
      "[data-group-check-in-manual-panel]",
    );

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
      document
        .querySelector("[data-group-check-in-scanner-view]")
        .classList.contains("hidden"),
    ).to.equal(true);
    expect(document.activeElement).to.equal(manualPanel);

    document.querySelector("[data-group-check-in-manual-back]").click();
    expect(manualPanel.classList.contains("hidden")).to.equal(true);
    expect(
      document
        .querySelector("[data-group-check-in-scanner-view]")
        .classList.contains("hidden"),
    ).to.equal(false);
    expect(document.activeElement).to.equal(trigger);
  });

  it("rebinds controls from an HTMX history snapshot", async () => {
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

    renderFixture();
    window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
    initializeGroupCheckInScanner();
    const cachedRoot = document
      .querySelector("[data-group-check-in-root]")
      .cloneNode(true);
    document
      .querySelector("[data-group-check-in-root]")
      .replaceWith(cachedRoot);

    cachedRoot.dispatchEvent(
      new Event("htmx:historyRestore", { bubbles: true }),
    );
    cachedRoot.querySelector("[data-group-check-in-open]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(FakeScanner.startCount).to.equal(1);
  });

  it("reports and resets torch state", async () => {
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

    renderFixture();
    window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
    initializeGroupCheckInScanner();
    document.querySelector("[data-group-check-in-open]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    const torch = document.querySelector("[data-group-check-in-torch]");

    torch.click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(torch.getAttribute("aria-pressed")).to.equal("true");
    expect(torch.textContent).to.equal("Turn torch off");

    document.querySelector("[data-group-check-in-close]").click();
    expect(torch.getAttribute("aria-pressed")).to.equal("false");
    expect(torch.textContent).to.equal("Turn torch on");
  });

  it("tears down an open scanner restored from the browser cache", async () => {
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

    renderFixture();
    window.__OCG_E2E_QR_SCANNER__ = FakeScanner;
    initializeGroupCheckInScanner();
    document.querySelector("[data-group-check-in-open]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    window.dispatchEvent(
      new PageTransitionEvent("pageshow", { persisted: true }),
    );

    expect(FakeScanner.instance.destroyCount).to.equal(1);
    expect(
      document
        .getElementById("group-check-in-scanner-modal")
        .classList.contains("hidden"),
    ).to.equal(true);
    expect(document.body.style.overflow).to.equal("");
  });
});
