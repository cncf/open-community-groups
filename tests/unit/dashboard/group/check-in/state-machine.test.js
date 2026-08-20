import { expect } from "@open-wc/testing";

import {
  createScanStateMachine,
  validateCredential,
} from "/static/js/dashboard/group/check-in/state-machine.js";

describe("group check-in scan state machine", () => {
  const eventId = "00000000-0000-0000-0000-000000000001";
  const credential = `ocg-check-in:v1:${eventId}:00000000-0000-0000-0000-000000000002`;

  it("rejects unrelated and wrong-event QR payloads before posting", () => {
    // Verify foreign and wrong-event credentials return distinct validation errors.
    expect(validateCredential("https://example.test", eventId)).to.deep.equal({
      ok: false,
      message: "This is not an Open Community Groups check-in code.",
    });
    expect(
      validateCredential(
        "ocg-check-in:v1:00000000-0000-0000-0000-000000000003:00000000-0000-0000-0000-000000000002",
        eventId,
      ),
    ).to.deep.equal({
      ok: false,
      message: "This check-in code belongs to a different event.",
    });
  });

  it("posts a decode, reports success, and resumes after cooldown", async () => {
    // Create a controller with observable scanner, audio, feedback, and timers.
    const feedback = [];
    const sounds = [];
    const timers = [];
    let readyCount = 0;
    let startCount = 0;
    const controller = createScanStateMachine({
      audio: { play: (kind) => sounds.push(kind) },
      eventId,
      onFeedback: (value) => feedback.push(value),
      onReady: () => {
        readyCount += 1;
      },
      postCredential: async (value) => ({
        attendee: { name: value === credential ? "Ada Lovelace" : "Wrong attendee" },
        outcome: "checked-in",
        ticket_title: "General admission",
      }),
      scanner: {
        start: async () => {
          startCount += 1;
        },
      },
      schedule: (callback) => {
        timers.push(callback);
        return timers.length;
      },
    });

    // Start the scanner and submit a valid credential.
    await controller.start();
    expect(await controller.handleDecode({ data: credential })).to.equal(true);

    // Verify success feedback and sound are emitted once.
    expect(startCount).to.equal(1);
    expect(readyCount).to.equal(1);
    expect(sounds).to.deep.equal(["success"]);
    expect(feedback[0]).to.include({
      attendeeName: "Ada Lovelace",
      kind: "success",
      message: "Checked in",
      ticketTitle: "General admission",
    });

    // Complete the cooldown and verify the scanner becomes ready again.
    timers[0]();
    expect(readyCount).to.equal(2);
  });

  it("keeps one request in flight and deduplicates rapid repeats", async () => {
    // Hold the first request open with a controllable response.
    let now = 1000;
    let postCount = 0;
    let releasePost;
    const timers = [];
    const firstPost = new Promise((resolve) => {
      releasePost = resolve;
    });
    const controller = createScanStateMachine({
      audio: {},
      eventId,
      now: () => now,
      postCredential: async () => {
        postCount += 1;
        if (postCount === 1) await firstPost;
        return { attendee: { username: "ada" }, outcome: "already-checked-in" };
      },
      scanner: {},
      schedule: (callback) => {
        timers.push(callback);
        return timers.length;
      },
    });
    await controller.start();

    // Submit the same credential again while the first request is pending.
    const pending = controller.handleDecode(credential);
    expect(await controller.handleDecode(credential)).to.equal(false);
    expect(postCount).to.equal(1);
    releasePost();
    await pending;

    // Complete the first request's cooldown.
    timers.shift()();

    // Verify repeats stay blocked until the deduplication window expires.
    expect(await controller.handleDecode(credential)).to.equal(false);
    now = 4001;
    expect(await controller.handleDecode(credential)).to.equal(true);
    expect(postCount).to.equal(2);
  });

  it("retries a failed credential after cooldown", async () => {
    // Create a controller with a stable clock and a recoverable first request.
    let postCount = 0;
    const timers = [];
    const controller = createScanStateMachine({
      audio: {},
      eventId,
      now: () => 1000,
      postCredential: async () => {
        postCount += 1;
        if (postCount === 1) throw new Error("Network error");
        return { attendee: { username: "ada" }, outcome: "checked-in" };
      },
      scanner: {},
      schedule: (callback) => {
        timers.push(callback);
        return timers.length;
      },
    });
    await controller.start();

    // Fail the first request and finish its normal feedback cooldown.
    expect(await controller.handleDecode(credential)).to.equal(false);
    timers.shift()();

    // Verify the same credential can retry without waiting for deduplication.
    expect(await controller.handleDecode(credential)).to.equal(true);
    expect(postCount).to.equal(2);
  });

  it("supports mute and tears down scanner, audio, and cooldown", async () => {
    // Create observable audio, scanner, and cooldown cleanup hooks.
    let audioClosed = false;
    let destroyCount = 0;
    let playCount = 0;
    let canceledTimer;
    const controller = createScanStateMachine({
      audio: {
        close: () => {
          audioClosed = true;
        },
        play: () => {
          playCount += 1;
        },
      },
      eventId,
      postCredential: async () => ({ attendee: {}, outcome: "checked-in" }),
      scanner: {
        destroy: () => {
          destroyCount += 1;
        },
      },
      schedule: () => 42,
      unschedule: (timer) => {
        canceledTimer = timer;
      },
    });

    // Mute the controller, process a credential, and tear down the session.
    await controller.start();
    controller.setMuted(true);
    await controller.handleDecode(credential);
    controller.teardown();

    // Verify teardown cancels feedback and releases every owned resource.
    expect(playCount).to.equal(0);
    expect(destroyCount).to.equal(1);
    expect(audioClosed).to.equal(true);
    expect(canceledTimer).to.equal(42);
  });

  it("ignores an in-flight response after teardown", async () => {
    // Hold a credential response open while tracking feedback side effects.
    const feedback = [];
    const sounds = [];
    let releasePost;
    const response = new Promise((resolve) => {
      releasePost = resolve;
    });
    const controller = createScanStateMachine({
      audio: { play: (kind) => sounds.push(kind) },
      eventId,
      onFeedback: (value) => feedback.push(value),
      postCredential: () => response,
      scanner: {},
    });
    await controller.start();

    // Tear down the controller before resolving the pending request.
    const pending = controller.handleDecode(credential);
    controller.teardown();
    releasePost({ attendee: { username: "ada" }, outcome: "checked-in" });

    // Verify the stale response cannot update feedback or play audio.
    expect(await pending).to.equal(false);
    expect(feedback).to.deep.equal([]);
    expect(sounds).to.deep.equal([]);
  });
});
