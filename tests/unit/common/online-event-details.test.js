import { expect } from "@open-wc/testing";

import "/static/js/common/online-event-details.js";
import {
  mountLitComponent,
  mountLitComponentWithAttributes,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("online-event-details", () => {
  useMountedElementsCleanup("online-event-details");

  it("returns manual meeting data and resets back to manual defaults", async () => {
    const element = await mountLitComponent("online-event-details", {
      meetingJoinInstructions: " Bring your ticket confirmation. ",
      meetingJoinUrl: " https://example.com/join ",
      meetingRecordingUrl: " https://example.com/recording ",
    });

    expect(element.getMeetingData()).to.deep.equal({
      meeting_join_instructions: "Bring your ticket confirmation.",
      meeting_join_url: "https://example.com/join",
      meeting_recording_published: false,
      meeting_recording_requested: true,
      meeting_recording_url: "https://example.com/recording",
      meeting_requested: false,
      meeting_provider_id: "",
    });

    element.reset();

    expect(element._mode).to.equal("manual");
    expect(element._joinInstructions).to.equal("");
    expect(element._joinUrl).to.equal("");
    expect(element._recordingPublished).to.equal(false);
    expect(element._recordingUrl).to.equal("");
  });

  it("honors a server-rendered false recording request attribute", async () => {
    const element = await mountLitComponentWithAttributes(
      "online-event-details",
      {
        attributes: {
          "meeting-recording-requested": "false",
        },
      },
    );

    expect(element.getMeetingData()).to.include({
      meeting_recording_requested: false,
    });
  });

  it("submits recording visibility and explains the public target", async () => {
    const element = await mountLitComponentWithAttributes(
      "online-event-details",
      {
        attributes: {
          "meeting-recording-published": "false",
          "meeting-recording-raw-url": "https://zoom.us/rec/share/raw",
        },
      },
    );

    expect(element.getMeetingData()).to.include({
      meeting_recording_published: false,
    });
    expect(element._getRecordingVisibilityText()).to.equal(
      "Public visitors will not see a recording link.",
    );

    element._handleRecordingPublishedChange({ target: { checked: true } });

    expect(element.getMeetingData()).to.include({
      meeting_recording_published: true,
    });
    expect(element._getRecordingVisibilityText()).to.equal(
      "Public visitors will see the original provider recording.",
    );
  });

  it("shows a capacity warning when automatic meeting capacity is exceeded", async () => {
    const capacity = document.createElement("input");
    capacity.id = "capacity";
    capacity.value = "150";
    document.body.append(capacity);

    const element = await mountLitComponent("online-event-details", {
      meetingMaxParticipants: { zoom: 100 },
    });

    element._mode = "automatic";
    element._createMeeting = true;
    element._providerId = "zoom";
    element._checkMeetingCapacity();

    expect(element._capacityWarning).to.include("Capacity (150) exceeds");
  });

  it("does not copy synced automatic meeting details into manual fields", async () => {
    const element = await mountLitComponent("online-event-details", {
      meetingInSync: true,
      meetingJoinUrl: "https://zoom.us/j/synced",
      meetingRecordingRawUrl: "https://zoom.us/rec/share/synced",
      meetingRequested: true,
    });

    globalThis.Swal = {
      fire: async () => ({ isConfirmed: true }),
    };

    await element._handleModeChange({
      preventDefault() {},
      target: { value: "manual" },
    });

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
    const element = await mountLitComponent("online-event-details", {
      endsAt: "2030-05-10T12:00",
      kind: "virtual",
      meetingInSync: true,
      meetingJoinUrl: "https://zoom.us/j/synced",
      meetingRecordingRawUrl: "https://zoom.us/rec/share/synced",
      meetingRequested: true,
      startsAt: "2030-05-10T10:00",
    });

    globalThis.Swal = {
      fire: async () => ({ isConfirmed: true }),
    };

    await element._handleModeChange({
      preventDefault() {},
      target: { value: "manual" },
    });
    await element._handleModeChange({
      preventDefault() {},
      target: { value: "automatic" },
    });

    expect(element._mode).to.equal("automatic");
    expect(element._joinUrl).to.equal("");
    expect(element._rawRecordingUrl).to.equal("https://zoom.us/rec/share/synced");
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
    const element = await mountLitComponent("online-event-details", {
      meetingInSync: true,
      meetingRecordingRawUrl: "https://zoom.us/rec/share/synced",
      meetingRequested: true,
    });

    globalThis.Swal = {
      fire: async () => ({ isConfirmed: true }),
    };

    element._handleRecordingUrlChange({
      target: { value: " https://youtube.com/watch?v=processed " },
    });
    await element._handleModeChange({
      preventDefault() {},
      target: { value: "manual" },
    });

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
    const capacity = document.createElement("input");
    capacity.id = "capacity";
    capacity.value = "150";
    document.body.append(capacity);

    const element = await mountLitComponent("online-event-details", {
      endsAt: "2030-05-10T12:00",
      kind: "virtual",
      meetingJoinUrl: " https://example.com/join ",
      meetingRecordingUrl: " https://youtube.com/watch?v=processed ",
      startsAt: "2030-05-10T10:00",
    });

    await element._handleModeChange({
      preventDefault() {},
      target: { value: "automatic" },
    });

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
    const element = await mountLitComponent("online-event-details", {
      fieldNamePrefix: "sessions[0]",
      meetingRecordingRawUrl: "https://example.com/original",
    });

    element._mode = "automatic";
    element._createMeeting = true;
    element._providerId = "zoom";
    element._handleRecordingUrlChange({
      target: { value: " https://youtube.com/watch?v=session-processed " },
    });

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
