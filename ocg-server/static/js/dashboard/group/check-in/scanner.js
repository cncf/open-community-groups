import { initializeOnReadyAndHtmxLoad, isElementHidden, markDatasetReady } from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { toggleModalVisibility, trapModalFocus } from "/static/js/common/modals/modal-lifecycle.js";
import { createScanStateMachine } from "/static/js/dashboard/group/check-in/state-machine.js";
import QrScanner from "/static/vendor/js/qr-scanner.min.js";

const MODAL_ID = "group-check-in-scanner-modal";
let activeSession = null;

/** Initializes group check-in card and scanner controls. */
export const initializeGroupCheckInScanner = (container = document, { historyRestore = false } = {}) => {
  const root = container.matches?.("[data-group-check-in-root]")
    ? container
    : container.querySelector?.("[data-group-check-in-root]");
  if (!(root instanceof HTMLElement)) return;
  if (historyRestore) {
    activeSession?.teardown();
    delete root.dataset.groupCheckInReady;
  }
  if (!markDatasetReady(root, "groupCheckInReady")) return;

  root.addEventListener("click", (event) => {
    const manualLink = event.target.closest?.("[data-group-check-in-manual]");
    if (manualLink instanceof HTMLAnchorElement && typeof window.htmx?.ajax === "function") {
      event.preventDefault();
      void openManualCheckIn(root, manualLink);
      return;
    }
    if (event.target.closest?.("[data-group-check-in-manual-back]")) {
      closeManualCheckIn(root);
      return;
    }
    const trigger = event.target.closest?.("[data-group-check-in-open]");
    if (trigger instanceof HTMLElement) {
      void startScannerSession(root, trigger);
      return;
    }
    if (event.target.closest?.("[data-group-check-in-close]") && activeSession?.root === root) {
      activeSession.close();
      return;
    }
    const mute = event.target.closest?.("[data-group-check-in-mute]");
    if (
      mute instanceof HTMLInputElement &&
      mute.type === "checkbox" &&
      activeSession?.root === root &&
      activeSession.controller
    ) {
      const muted = activeSession.controller.setMuted(mute.checked);
      setMuteState(mute, muted);
    }
  });
  root.addEventListener("keydown", (event) => {
    if (activeSession?.root !== root) return;
    if (isEscapeEvent(event)) {
      activeSession.close();
      return;
    }
    trapModalFocus(event, activeSession.modal);
  });
};

/** Returns actionable text for camera initialization failures. */
const cameraErrorMessage = (error) => {
  if (!window.isSecureContext) {
    return "Camera access requires a secure HTTPS connection. Use manual check-in instead.";
  }
  if (error?.name === "NotAllowedError") {
    return "Camera permission was denied. Allow camera access in your browser or use manual check-in.";
  }
  if (error?.name === "NotFoundError" || error?.name === "DevicesNotFoundError") {
    return "No camera was found. Connect a camera or use manual check-in.";
  }
  return "The camera could not be started. Try another camera or use manual check-in.";
};

/** Returns the compact scanner status shown beside camera failure details. */
const cameraStatusMessage = (error) =>
  error?.name === "NotFoundError" || error?.name === "DevicesNotFoundError"
    ? "Waiting for a camera…"
    : "Camera unavailable.";

/** Returns from manual attendee check-in to the scanner event cards. */
const closeManualCheckIn = (root) => {
  const panel = root.querySelector("[data-group-check-in-manual-panel]");
  if (!(panel instanceof HTMLElement)) return;

  const eventId = panel.dataset.eventId || "";
  panel.classList.add("hidden");
  root.querySelectorAll("[data-group-check-in-scanner-view]").forEach((element) => {
    element.classList.remove("hidden");
  });
  const origin = [...root.querySelectorAll("[data-group-check-in-open]")].find(
    (element) => element.dataset.eventId === eventId,
  );
  origin?.focus();
};

/** Creates synthesized scanner feedback without shipping audio assets. */
const createScannerAudio = () => {
  const AudioContext = window.AudioContext || window.webkitAudioContext;
  let context = null;
  try {
    context = AudioContext ? new AudioContext() : null;
  } catch {
    // Sound feedback is optional; camera scanning must remain available.
  }

  return {
    close: () => context?.close?.().catch(() => {}),
    play: (kind) => {
      if (!context) return;
      context.resume().catch(() => {});
      const oscillator = context.createOscillator();
      const gain = context.createGain();
      const frequencies = { error: 170, neutral: 480, success: 880 };
      oscillator.frequency.value = frequencies[kind] || frequencies.neutral;
      oscillator.type = kind === "error" ? "sawtooth" : "sine";
      gain.gain.setValueAtTime(0.0001, context.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.18, context.currentTime + 0.015);
      gain.gain.exponentialRampToValueAtTime(0.0001, context.currentTime + 0.2);
      oscillator.connect(gain).connect(context.destination);
      oscillator.start();
      oscillator.stop(context.currentTime + 0.21);
    },
    unlock: () => context?.resume?.().catch(() => {}),
  };
};

/**
 * Loads the selected event's attendee table without leaving the mobile check-in
 * surface.
 */
const openManualCheckIn = async (root, link) => {
  const attendeesUrl = link.dataset.attendeesUrl || "";
  const content = root.querySelector("#attendees-content");
  const panel = root.querySelector("[data-group-check-in-manual-panel]");
  const status = root.querySelector("[data-group-check-in-manual-status]");
  if (!attendeesUrl || !(content instanceof HTMLElement) || !(panel instanceof HTMLElement)) return;

  activeSession?.close();
  root.querySelectorAll("[data-group-check-in-scanner-view]").forEach((element) => {
    element.classList.add("hidden");
  });
  const title = panel.querySelector("[data-group-check-in-manual-title]");
  if (title) title.textContent = link.dataset.eventName || "Event attendees";
  panel.dataset.eventId = link.dataset.eventId || "";
  panel.classList.remove("hidden");
  panel.focus();
  content.replaceChildren();
  content.setAttribute("aria-busy", "true");
  setManualCheckInStatus(status, "Loading attendees…");

  try {
    await window.htmx.ajax("GET", attendeesUrl, {
      indicator: "#dashboard-spinner",
      swap: "innerHTML",
      target: "#attendees-content",
    });
    setManualCheckInStatus(status, "");
  } catch {
    setManualCheckInStatus(
      status,
      "The attendee list could not be loaded. Return to the scanner and try again.",
    );
  } finally {
    content.removeAttribute("aria-busy");
  }
};

/** Populates the available camera selector after access has been granted. */
const populateCameras = async (select, scanner, isCurrent, torch, runHardwareControl) => {
  const cameras = await scannerImplementation().listCameras(true);
  if (!isCurrent()) return () => {};
  if (cameras.length === 0) {
    setCameraSelectPlaceholder(select, "Camera selection unavailable");
    return () => {};
  }
  select.replaceChildren();
  cameras.forEach((camera, index) => {
    const option = document.createElement("option");
    option.textContent = camera.label || `Camera ${index + 1}`;
    option.value = camera.id;
    select.append(option);
  });
  select.disabled = cameras.length < 2;
  const changeHandler = () => {
    void runHardwareControl(async () => {
      setTorchAvailable(torch, false);
      try {
        await scanner.setCamera(select.value);
        if (!isCurrent()) return;
        const hasFlash = await scanner.hasFlash();
        if (!isCurrent()) return;
        setTorchAvailable(torch, hasFlash);
        if (hasFlash) setTorchState(torch, scanner.isFlashOn());
      } catch {
        if (isCurrent()) setTorchAvailable(torch, false);
      }
    });
  };
  select.addEventListener("change", changeHandler);
  return () => select.removeEventListener("change", changeHandler);
};

/** Sends a scanned credential and normalizes typed server failures. */
const postCredential = async (url, credential) => {
  let response;
  try {
    response = await ocgFetch(url, {
      body: JSON.stringify({ credential }),
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      method: "POST",
    });
  } catch {
    throw new Error("Network error. Try again or use manual check-in.");
  }

  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body?.error?.message || "Check-in failed. Try again or use manual check-in.");
  }
  return body;
};

/** Renders visible and screen-reader scan feedback. */
const renderFeedback = (element, feedback) => {
  element.className = `absolute inset-x-4 top-4 rounded-lg border p-4 text-center shadow-lg ${
    feedback.kind === "success"
      ? "border-green-800 bg-green-100 text-green-800"
      : feedback.kind === "neutral"
        ? "border-stone-800 bg-stone-100 text-stone-800"
        : "border-red-800 bg-red-100 text-red-800"
  }`;
  const message = document.createElement("p");
  message.className = "text-sm font-normal md:text-base";
  message.textContent = feedback.message;
  element.replaceChildren(message);
  if (feedback.attendeeName) {
    const details = document.createElement("p");
    details.className = "mt-1 text-sm";
    details.textContent = `${feedback.attendeeName} · ${feedback.ticketTitle}`;
    element.append(details);
  }
};

/**
 * Replaces the video so delayed cleanup from an old scanner cannot clear the new
 * stream.
 */
const replaceScannerVideo = (root) => {
  const currentVideo = root.querySelector("[data-group-check-in-video]");
  if (!(currentVideo instanceof HTMLVideoElement)) return null;
  const nextVideo = currentVideo.cloneNode(true);
  currentVideo.replaceWith(nextVideo);
  return nextVideo;
};

/** Returns the production decoder or an explicitly injected browser-test double. */
const scannerImplementation = () => window.__OCG_E2E_QR_SCANNER__ || QrScanner;

/** Updates the disabled camera selector with one explicit availability state. */
const setCameraSelectPlaceholder = (select, message) => {
  if (!(select instanceof HTMLSelectElement)) return;
  const option = document.createElement("option");
  option.textContent = message;
  option.selected = true;
  select.replaceChildren(option);
  select.disabled = true;
};

/** Updates the visual camera-unavailable message inside the scanner viewport. */
const setCameraUnavailableState = (root, message = "") => {
  const unavailable = root.querySelector("[data-group-check-in-camera-unavailable]");
  const unavailableMessage = root.querySelector("[data-group-check-in-camera-unavailable-message]");
  if (!(unavailable instanceof HTMLElement)) return;
  unavailable.classList.toggle("hidden", !message);
  unavailable.classList.toggle("flex", Boolean(message));
  if (unavailableMessage) unavailableMessage.textContent = message;
};

/** Updates the compact live region used while loading the manual attendee list. */
const setManualCheckInStatus = (element, message) => {
  if (!(element instanceof HTMLElement)) return;
  element.textContent = message;
  element.classList.toggle("hidden", !message);
};

/** Updates the visible and accessible sound state. */
const setMuteState = (input, isMuted) => {
  if (!(input instanceof HTMLInputElement) || input.type !== "checkbox") return;
  input.checked = isMuted;
};

/** Updates whether the torch switch is available for the active camera. */
const setTorchAvailable = (input, isAvailable) => {
  if (!(input instanceof HTMLInputElement) || input.type !== "checkbox") return;
  const control = input.closest("[data-group-check-in-torch-control]");
  if (!(control instanceof HTMLElement)) return;
  control.classList.toggle("hidden", !isAvailable);
  control.classList.toggle("inline-flex", isAvailable);
  input.disabled = !isAvailable;
  if (!isAvailable) setTorchState(input, false);
};

/** Updates the visible and accessible torch switch state. */
const setTorchState = (input, isOn) => {
  if (!(input instanceof HTMLInputElement) || input.type !== "checkbox") return;
  input.checked = isOn;
};

/** Starts one scanner session for a selected event. */
const startScannerSession = async (root, trigger) => {
  activeSession?.close();

  const modal = root.querySelector(`#${MODAL_ID}`);
  if (!(modal instanceof HTMLElement)) return;
  const video = replaceScannerVideo(root);
  const status = root.querySelector("[data-group-check-in-status]");
  const result = root.querySelector("[data-group-check-in-result]");
  const camera = root.querySelector("[data-group-check-in-camera]");
  const mute = root.querySelector("[data-group-check-in-mute]");
  const torch = root.querySelector("[data-group-check-in-torch]");
  if (!(video instanceof HTMLVideoElement)) return;

  const eventId = trigger.dataset.eventId || "";
  const eventDate = trigger.dataset.eventDate || "Date information unavailable";
  const eventLocation = trigger.dataset.eventLocation || "Location information unavailable";
  const eventName = trigger.dataset.eventName || "Event check-in";
  const scanUrl = trigger.dataset.scanUrl || "";
  const eventDateElement = root.querySelector("#group-check-in-event-date");
  const eventLocationElement = root.querySelector("#group-check-in-event-location");
  const eventNameElement = root.querySelector("#group-check-in-event-name");
  const manualLink = root.querySelector("[data-group-check-in-manual]");
  if (eventDateElement) eventDateElement.textContent = eventDate;
  if (eventLocationElement) eventLocationElement.textContent = eventLocation;
  if (eventNameElement) eventNameElement.textContent = eventName;
  if (manualLink instanceof HTMLAnchorElement) {
    manualLink.dataset.attendeesUrl = trigger.dataset.attendeesUrl || "";
    manualLink.dataset.eventId = eventId;
    manualLink.dataset.eventName = eventName;
  }
  if (status) status.textContent = "Starting camera…";
  if (result) result.classList.add("hidden");
  setCameraSelectPlaceholder(camera, "Finding cameras…");
  setCameraUnavailableState(root);
  if (mute instanceof HTMLInputElement) mute.disabled = false;
  setMuteState(mute, true);
  setTorchAvailable(torch, false);

  let audio = null;
  let cleanupCameraSelection = () => {};
  let controller = null;
  let hardwareControlPending = false;
  let resourcesCleaned = false;
  let scanner = null;
  let session;
  let torchChangeHandler = null;
  const isCurrent = () => activeSession === session;
  const cleanupControls = () => {
    cleanupCameraSelection();
    cleanupCameraSelection = () => {};
    if (torch instanceof HTMLInputElement && torchChangeHandler) {
      torch.removeEventListener("change", torchChangeHandler);
      torchChangeHandler = null;
    }
    setTorchAvailable(torch, false);
  };
  const cleanupResources = () => {
    cleanupControls();
    if (resourcesCleaned) return;
    resourcesCleaned = true;
    try {
      if (controller) {
        controller.teardown();
      } else {
        scanner?.destroy?.();
        audio?.close?.();
      }
    } catch {
      audio?.close?.();
    }
  };
  const runHardwareControl = async (operation) => {
    if (hardwareControlPending || !isCurrent()) return false;
    hardwareControlPending = true;
    if (camera instanceof HTMLSelectElement) camera.disabled = true;
    if (torch instanceof HTMLInputElement) torch.disabled = true;
    try {
      await operation();
      return true;
    } finally {
      hardwareControlPending = false;
      if (isCurrent()) {
        if (camera instanceof HTMLSelectElement) camera.disabled = camera.options.length < 2;
        if (torch instanceof HTMLInputElement) {
          const torchControl = torch.closest("[data-group-check-in-torch-control]");
          torch.disabled =
            !(torchControl instanceof HTMLElement) || torchControl.classList.contains("hidden");
        }
      }
    }
  };

  const close = () => {
    cleanupResources();
    if (!isElementHidden(modal)) toggleModalVisibility(MODAL_ID);
    if (isCurrent()) activeSession = null;
  };
  const teardown = () => {
    cleanupResources();
    if (isCurrent()) activeSession = null;
  };
  session = { close, controller, modal, root, teardown };
  activeSession = session;

  try {
    toggleModalVisibility(MODAL_ID, trigger);
    audio = createScannerAudio();
    audio.unlock();
    const Scanner = scannerImplementation();
    scanner = new Scanner(video, (decoded) => controller?.handleDecode(decoded), {
      maxScansPerSecond: 12,
      preferredCamera: "environment",
      returnDetailedScanResult: true,
    });
    controller = createScanStateMachine({
      audio,
      eventId,
      onFeedback: (feedback) => renderFeedback(result, feedback),
      onReady: () => {
        result?.classList.add("hidden");
        if (status) status.textContent = "Hold an attendee QR code inside the frame.";
      },
      postCredential: (credential) => postCredential(scanUrl, credential),
      scanner,
    });
    session.controller = controller;

    if (!window.isSecureContext || !(await Scanner.hasCamera())) {
      const error = new Error("No camera available");
      error.name = window.isSecureContext ? "NotFoundError" : "SecurityError";
      throw error;
    }
    if (!isCurrent()) return;
    await controller.start();
    if (!isCurrent()) {
      controller.teardown();
      return;
    }
    let hasFlash = false;
    try {
      hasFlash = await scanner.hasFlash();
    } catch {
      // Flash support is optional; scanning can continue without torch controls.
    }
    if (!isCurrent()) {
      controller.teardown();
      return;
    }
    if (camera instanceof HTMLSelectElement) {
      try {
        cleanupCameraSelection = await populateCameras(camera, scanner, isCurrent, torch, runHardwareControl);
      } catch {
        if (isCurrent()) setCameraSelectPlaceholder(camera, "Camera selection unavailable");
      }
    }
    if (!isCurrent()) {
      cleanupControls();
      controller.teardown();
      return;
    }
    if (torch instanceof HTMLInputElement && torch.type === "checkbox") {
      setTorchAvailable(torch, hasFlash);
      if (hasFlash) setTorchState(torch, scanner.isFlashOn());
      torchChangeHandler = () => {
        void runHardwareControl(async () => {
          try {
            await scanner.toggleFlash();
            if (isCurrent()) setTorchState(torch, scanner.isFlashOn());
          } catch {
            if (isCurrent()) setTorchAvailable(torch, false);
          }
        });
      };
      torch.addEventListener("change", torchChangeHandler);
    }
  } catch (error) {
    cleanupResources();
    if (isCurrent()) {
      const errorMessage = cameraErrorMessage(error);
      if (mute instanceof HTMLInputElement) mute.disabled = true;
      setCameraSelectPlaceholder(camera, "No cameras detected");
      setCameraUnavailableState(root, errorMessage);
      if (status) status.textContent = cameraStatusMessage(error);
    }
  }
};

document.addEventListener("htmx:beforeCleanupElement", (event) => {
  const root = activeSession?.root;
  if (root && (root === event.target || event.target?.contains?.(root))) {
    activeSession.close();
  }
});
window.addEventListener("beforeunload", () => activeSession?.teardown());
window.addEventListener("pageshow", (event) => {
  if (event.persisted) activeSession?.close();
});

initializeOnReadyAndHtmxLoad(initializeGroupCheckInScanner);
