import { expect } from "@open-wc/testing";

import "/static/js/common/online-event-details.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import {
  mountLitComponent,
  mountLitComponentWithAttributes,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("online-event-details", () => {
  useMountedElementsCleanup("online-event-details");

  it("returns manual meeting data and resets back to manual defaults", async () => {
    // Render the online-event-details fixture.
    const element = await mountLitComponent("online-event-details", {
      meetingJoinInstructions: " Bring your ticket confirmation. ",
      meetingJoinUrl: " https://example.com/join ",
      meetingRecordingUrl: " https://example.com/recording ",
    });

    // Manual meeting data is trimmed before submission.
    expect(element.getMeetingData()).to.deep.equal({
      meeting_join_instructions: "Bring your ticket confirmation.",
      meeting_join_url: "https://example.com/join",
      meeting_recording_published: false,
      meeting_recording_requested: true,
      meeting_recording_url: "https://example.com/recording",
      meeting_requested: false,
      meeting_provider_id: "",
    });

    // Reset the fixture state.
    element.reset();

    // Resetting returns the component to empty manual defaults.
    expect(element._mode).to.equal("manual");
    expect(element._joinInstructions).to.equal("");
    expect(element._joinUrl).to.equal("");
    expect(element._recordingPublished).to.equal(false);
    expect(element._recordingUrl).to.equal("");
  });

  it("honors a server-rendered false recording request attribute", async () => {
    // Render the component fixture.
    const element = await mountLitComponentWithAttributes(
      "online-event-details",
      {
        attributes: {
          "meeting-recording-requested": "false",
        },
      },
    );

    // The false attribute value is preserved in submitted data.
    expect(element.getMeetingData()).to.include({
      meeting_recording_requested: false,
    });
  });

  it("submits recording visibility and explains the public target", async () => {
    // Save browser globals before mocking clipboard and window open.
    const originalClipboardDescriptor = Object.getOwnPropertyDescriptor(
      navigator,
      "clipboard",
    );
    const originalOpen = window.open;
    const clipboardCalls = [];
    const openCalls = [];
    const swal = mockSwal();

    // Mock the browser API.
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: {
        writeText: async (value) => {
          clipboardCalls.push(value);
        },
      },
    });
    window.open = (...args) => {
      openCalls.push(args);
    };

    // Render the component fixture.
    const element = await mountLitComponentWithAttributes(
      "online-event-details",
      {
        attributes: {
          "meeting-recording-published": "false",
          "meeting-recording-raw-urls": JSON.stringify([
            "https://zoom.us/rec/share/raw-main",
            "https://zoom.us/rec/share/raw-late",
          ]),
        },
      },
    );

    // Execute the async scenario and restore mocked globals afterward.
    try {
      // Recording metadata starts unpublished with both raw URLs visible.
      expect(element.getMeetingData()).to.include({
        meeting_recording_published: false,
      });
      expect(
        [
          ...element.renderRoot.querySelectorAll('input[readonly][type="url"]'),
        ].map((input) => input.value),
      ).to.deep.equal([
        "https://zoom.us/rec/share/raw-main",
        "https://zoom.us/rec/share/raw-late",
      ]);
      expect(
        [...element.renderRoot.querySelectorAll("label.form-label")]
          .map((label) => label.textContent.trim())
          .filter((label) => label.includes("Original provider")),
      ).to.deep.equal(["Original provider recordings"]);
      expect(element.textContent).to.include(
        "Controls whether public visitors can see the final public recording URL.",
      );
      expect(element.textContent).to.include(
        "Zoom can send multiple raw recordings when participants join before or after the main meeting.",
      );

      // List the fixture values.
      const copyButtons = [
        ...element.renderRoot.querySelectorAll("[data-raw-recording-copy]"),
      ];
      const openButtons = [
        ...element.renderRoot.querySelectorAll("[data-raw-recording-open]"),
      ];

      // Copy and open controls are rendered for each raw recording URL.
      expect(copyButtons).to.have.length(2);
      expect(openButtons).to.have.length(2);

      // Click one copy button and one open button.
      copyButtons[0].click();
      openButtons[1].click();
      await new Promise((resolve) => setTimeout(resolve, 0));

      // Copying and opening use the selected raw recording URLs.
      expect(clipboardCalls).to.deep.equal([
        "https://zoom.us/rec/share/raw-main",
      ]);
      expect(openCalls).to.deep.equal([
        ["https://zoom.us/rec/share/raw-late", "_blank", "noopener,noreferrer"],
      ]);
      expect(swal.calls[0]).to.include({
        text: "Recording URL copied to clipboard.",
        icon: "info",
      });

      // Let the component finish rendering.
      element._handleRecordingPublishedChange({ target: { checked: true } });
      await element.updateComplete;

      // Publishing the recording updates submitted data and keeps helper copy.
      expect(element.getMeetingData()).to.include({
        meeting_recording_published: true,
      });
      expect(element.textContent).to.include(
        "Controls whether public visitors can see the final public recording URL.",
      );
    } finally {
      swal.restore();
      window.open = originalOpen;

      // Handle the conditional test branch.
      if (originalClipboardDescriptor) {
        Object.defineProperty(
          navigator,
          "clipboard",
          originalClipboardDescriptor,
        );
      } else {
        delete navigator.clipboard;
      }
    }
  });

  it("shows a capacity warning when automatic meeting capacity is exceeded", async () => {
    // Create the input fixture.
    const capacity = document.createElement("input");
    capacity.id = "capacity";
    capacity.value = "150";
    document.body.append(capacity);

    // Render the online-event-details fixture.
    const element = await mountLitComponent("online-event-details", {
      meetingMaxParticipants: { zoom: 100 },
    });

    // Set automatic meeting data and validate capacity.
    element._mode = "automatic";
    element._createMeeting = true;
    element._providerId = "zoom";
    element._checkMeetingCapacity();

    // The provider capacity warning is shown for the oversized event.
    expect(element._capacityWarning).to.include("Capacity (150) exceeds");
  });

  it("disables automatic meeting creation for past events", async () => {
    // Create the capacity fixture required by automatic meeting validation.
    const capacity = document.createElement("input");
    capacity.id = "capacity";
    capacity.value = "75";
    document.body.append(capacity);
    const swal = mockSwal();

    try {
      // Render the online-event-details fixture for a past event.
      const element = await mountLitComponent("online-event-details", {
        endsAt: "2025-05-10T12:00",
        eventPast: true,
        kind: "virtual",
        meetingMaxParticipants: { zoom: 100 },
        startsAt: "2025-05-10T10:00",
      });

      // The automatic option is disabled and explains the past-event rule.
      const automaticModeInput = element.renderRoot.querySelector(
        'input[type="radio"][value="automatic"]',
      );
      const automaticModeCard = automaticModeInput.nextElementSibling;
      expect(automaticModeInput.disabled).to.equal(true);
      expect(automaticModeCard.classList.contains("border-dashed")).to.equal(true);
      expect(automaticModeCard.classList.contains("bg-stone-50")).to.equal(true);
      expect(element.textContent).to.include(
        "Automatic meetings are not available for past events.",
      );

      // Attempting to switch into automatic mode keeps the component manual.
      await element._handleModeChange({
        preventDefault() {},
        target: { value: "automatic" },
      });
      expect(element._mode).to.equal("manual");
      expect(element.getMeetingData()).to.include({
        meeting_requested: false,
      });
      expect(swal.calls[0]).to.include({
        text: "Automatic meetings are not available for past events.",
        icon: "info",
      });
    } finally {
      swal.restore();
    }
  });

  it("keeps synced past automatic meetings selected without enablement requirements", async () => {
    // Create the capacity fixture required by automatic meeting validation.
    const capacity = document.createElement("input");
    capacity.id = "capacity";
    capacity.value = "75";
    document.body.append(capacity);

    // Render the online-event-details fixture for a synced past automatic meeting.
    const element = await mountLitComponent("online-event-details", {
      endsAt: "2025-05-10T12:00",
      eventPast: true,
      kind: "virtual",
      meetingInSync: true,
      meetingJoinUrl: "https://zoom.us/j/synced-past",
      meetingMaxParticipants: { zoom: 100 },
      meetingPassword: "past-auto",
      meetingProviderId: "zoom",
      meetingRequested: true,
      startsAt: "2025-05-10T10:00",
    });

    // The synced automatic meeting stays selected but avoids enablement copy.
    const automaticModeInput = element.renderRoot.querySelector(
      'input[type="radio"][value="automatic"]',
    );
    expect(automaticModeInput.checked).to.equal(true);
    expect(automaticModeInput.disabled).to.equal(true);
    expect(element.textContent).to.include(
      "This existing automatic meeting is preserved. New automatic meetings cannot be enabled for past events.",
    );
    expect(element.textContent).to.not.include(
      "Complete these requirements to enable this option:",
    );
    expect(element.textContent).to.include("Meeting synced");
    expect(element.textContent).to.include("https://zoom.us/j/synced-past");
    expect(element.getMeetingData()).to.include({
      meeting_requested: true,
      meeting_provider_id: "zoom",
    });
  });

  it("removes the capacity input listener when disconnected", async () => {
    // Create the capacity input fixture.
    const capacity = document.createElement("input");
    capacity.id = "capacity";
    document.body.append(capacity);

    // Track listener cleanup on the capacity input.
    const originalRemoveEventListener = capacity.removeEventListener.bind(capacity);
    const removedListeners = [];
    capacity.removeEventListener = (type, listener, options) => {
      removedListeners.push({ type, listener, options });
      return originalRemoveEventListener(type, listener, options);
    };

    try {
      // Render the online-event-details fixture.
      const element = await mountLitComponent("online-event-details", {
        meetingMaxParticipants: { zoom: 100 },
      });
      const capacityInputHandler = element._capacityInputHandler;

      // Disconnect the component to trigger lifecycle cleanup.
      element.remove();

      // The stored capacity input handler is removed on disconnect.
      expect(
        removedListeners.some(
          ({ type, listener }) => type === "input" && listener === capacityInputHandler,
        ),
      ).to.equal(true);
    } finally {
      // Restore the native listener removal method.
      capacity.removeEventListener = originalRemoveEventListener;
    }
  });

  it("does not copy synced automatic meeting details into manual fields", async () => {
    // Render the online-event-details fixture.
    const element = await mountLitComponent("online-event-details", {
      meetingInSync: true,
      meetingJoinUrl: "https://zoom.us/j/synced",
      meetingRecordingRawUrls: ["https://zoom.us/rec/share/synced"],
      meetingRequested: true,
    });

    // Mock the external browser library.
    globalThis.Swal = {
      fire: async () => ({ isConfirmed: true }),
    };

    // Apply the selected meeting mode and update related fields.
    await element._handleModeChange({
      preventDefault() {},
      target: { value: "manual" },
    });

    // No copy synced automatic meeting details into manual fields.
    expect(element._mode).to.equal("manual");
    expect(element._joinUrl).to.equal("");
    expect(element._recordingUrl).to.equal("");
    expect(element.getMeetingData()).to.deep.equal({
      meeting_join_instructions: "",
      meeting_join_url: "",
      meeting_recording_published: false,
      meeting_recording_requested: true,
      meeting_recording_url: "",
      meeting_requested: false,
      meeting_provider_id: "",
    });
  });

  it("restores synced automatic recording when switching back without saving", async () => {
    // Render the online-event-details fixture.
    const element = await mountLitComponent("online-event-details", {
      endsAt: "2030-05-10T12:00",
      kind: "virtual",
      meetingInSync: true,
      meetingJoinUrl: "https://zoom.us/j/synced",
      meetingRecordingRawUrls: ["https://zoom.us/rec/share/synced"],
      meetingRequested: true,
      startsAt: "2030-05-10T10:00",
    });

    // Mock the external browser library.
    globalThis.Swal = {
      fire: async () => ({ isConfirmed: true }),
    };

    // Apply the selected meeting mode and update related fields.
    await element._handleModeChange({
      preventDefault() {},
      target: { value: "manual" },
    });
    await element._handleModeChange({
      preventDefault() {},
      target: { value: "automatic" },
    });

    // Restored synced automatic recording when switching back without saving.
    expect(element._mode).to.equal("automatic");
    expect(element._joinUrl).to.equal("");
    expect(element._rawRecordingUrls).to.deep.equal([
      "https://zoom.us/rec/share/synced",
    ]);
    expect(element._recordingUrl).to.equal("");
    expect(element.getMeetingData()).to.deep.equal({
      meeting_join_instructions: "",
      meeting_join_url: "",
      meeting_recording_published: false,
      meeting_recording_requested: true,
      meeting_recording_url: "",
      meeting_requested: true,
      meeting_provider_id: "zoom",
    });
  });

  it("keeps automatic recording edits when switching to manual without saving", async () => {
    // Render the online-event-details fixture.
    const element = await mountLitComponent("online-event-details", {
      meetingInSync: true,
      meetingRecordingRawUrls: ["https://zoom.us/rec/share/synced"],
      meetingRequested: true,
    });

    // Mock the external browser library.
    globalThis.Swal = {
      fire: async () => ({ isConfirmed: true }),
    };

    // Normalize the recording URL and update derived state.
    element._handleRecordingUrlChange({
      target: { value: " https://youtube.com/watch?v=processed " },
    });
    await element._handleModeChange({
      preventDefault() {},
      target: { value: "manual" },
    });

    // The manual mode keeps the edited recording URL without saving first.
    expect(element._mode).to.equal("manual");
    expect(element._recordingUrl).to.equal(
      " https://youtube.com/watch?v=processed ",
    );
    expect(element.getMeetingData()).to.deep.equal({
      meeting_join_instructions: "",
      meeting_join_url: "",
      meeting_recording_published: false,
      meeting_recording_requested: true,
      meeting_recording_url: "https://youtube.com/watch?v=processed",
      meeting_requested: false,
      meeting_provider_id: "",
    });
  });

  it("preserves recording overrides when switching from manual to automatic mode", async () => {
    // Create the input fixture.
    const capacity = document.createElement("input");
    capacity.id = "capacity";
    capacity.value = "150";
    document.body.append(capacity);

    // Render the online-event-details fixture.
    const element = await mountLitComponent("online-event-details", {
      endsAt: "2030-05-10T12:00",
      kind: "virtual",
      meetingJoinUrl: " https://example.com/join ",
      meetingRecordingUrl: " https://youtube.com/watch?v=processed ",
      startsAt: "2030-05-10T10:00",
    });

    // Apply the selected meeting mode and update related fields.
    await element._handleModeChange({
      preventDefault() {},
      target: { value: "automatic" },
    });

    // Automatic mode preserves the processed recording URL.
    expect(element._mode).to.equal("automatic");
    expect(element._joinUrl).to.equal("");
    expect(element._recordingUrl).to.equal(
      " https://youtube.com/watch?v=processed ",
    );
    expect(element.getMeetingData()).to.deep.equal({
      meeting_join_instructions: "",
      meeting_join_url: "",
      meeting_recording_published: false,
      meeting_recording_requested: true,
      meeting_recording_url: "https://youtube.com/watch?v=processed",
      meeting_requested: true,
      meeting_provider_id: "zoom",
    });
  });

  it("returns automatic recording overrides for session meeting data", async () => {
    // Render the online-event-details fixture.
    const element = await mountLitComponent("online-event-details", {
      fieldNamePrefix: "sessions[0]",
      meetingRecordingRawUrls: ["https://example.com/original"],
    });

    // Apply the recording URL change.
    element._mode = "automatic";
    element._createMeeting = true;
    element._providerId = "zoom";
    element._handleRecordingUrlChange({
      target: { value: " https://youtube.com/watch?v=session-processed " },
    });

    // Session meeting data uses the processed recording override.
    expect(element.getMeetingData()).to.deep.equal({
      meeting_join_instructions: "",
      meeting_join_url: "",
      meeting_recording_published: false,
      meeting_recording_requested: true,
      meeting_recording_url: "https://youtube.com/watch?v=session-processed",
      meeting_requested: true,
      meeting_provider_id: "zoom",
    });
  });
});
