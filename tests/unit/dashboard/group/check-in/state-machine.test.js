import { expect } from "@open-wc/testing";

import {
  createScanStateMachine,
  validateCredential,
} from "/static/js/dashboard/group/check-in/state-machine.js";

describe("group check-in scan state machine", () => {
  const eventId = "00000000-0000-0000-0000-000000000001";
  const credential = `ocg-check-in:v1:${eventId}:00000000-0000-0000-0000-000000000002`;

  it("rejects unrelated and wrong-event QR payloads before posting", () => {
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

    await controller.start();
    expect(await controller.handleDecode({ data: credential })).to.equal(true);

    expect(startCount).to.equal(1);
    expect(readyCount).to.equal(1);
    expect(sounds).to.deep.equal(["success"]);
    expect(feedback[0]).to.include({
      attendeeName: "Ada Lovelace",
      kind: "success",
      message: "Checked in",
      ticketTitle: "General admission",
    });

    timers[0]();
    expect(readyCount).to.equal(2);
  });

  it("keeps one request in flight and deduplicates rapid repeats", async () => {
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

    const pending = controller.handleDecode(credential);
    expect(await controller.handleDecode(credential)).to.equal(false);
    expect(postCount).to.equal(1);
    releasePost();
    await pending;
    timers.shift()();

    expect(await controller.handleDecode(credential)).to.equal(false);
    now = 4001;
    expect(await controller.handleDecode(credential)).to.equal(true);
    expect(postCount).to.equal(2);
  });

  it("supports mute and tears down scanner, audio, and cooldown", async () => {
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
    await controller.start();
    controller.setMuted(true);
    await controller.handleDecode(credential);
    controller.teardown();

    expect(playCount).to.equal(0);
    expect(destroyCount).to.equal(1);
    expect(audioClosed).to.equal(true);
    expect(canceledTimer).to.equal(42);
  });

  it("ignores an in-flight response after teardown", async () => {
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

    const pending = controller.handleDecode(credential);
    controller.teardown();
    releasePost({ attendee: { username: "ada" }, outcome: "checked-in" });

    expect(await pending).to.equal(false);
    expect(feedback).to.deep.equal([]);
    expect(sounds).to.deep.equal([]);
  });
});
