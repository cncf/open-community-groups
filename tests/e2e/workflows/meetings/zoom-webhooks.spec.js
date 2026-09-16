import { expect, test } from "../../fixtures.js";
import { queryE2eDatabase, queryE2eDatabaseRows } from "../../database.js";
import { TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_MEETING_EVENTS, TEST_MEETINGS } from "../../seed.js";
import { navigateToEvent, navigateToPath } from "../../utils.js";
import {
  postZoom,
  signZoom,
  WEBHOOK_ENDPOINTS,
  WEBHOOK_SECRETS,
  zoomEncryptedToken,
} from "../../webhooks.js";
import {
  openEventUpdateFormByName,
  waitForEventEditorAfterSave,
} from "../../dashboard/group/events/helpers.js";

const ZOOM_RECORDING_EVENT = TEST_MEETING_EVENTS.recording;

const ZOOM_RECORDING_MEETING = TEST_MEETINGS.recording;

test.describe("Zoom meeting webhooks", () => {
  test("validates Zoom URL challenge tokens", async ({ request }) => {
    const plainToken = "zoom-e2e-url-validation";

    // Post the signed URL-validation challenge and verify Zoom's expected response body.
    const response = await postZoom(request, {
      body: {
        event: "endpoint.url_validation",
        payload: { plainToken },
      },
      secret: WEBHOOK_SECRETS.zoom,
    });
    expect(response.status()).toBe(200);
    await expect(response).toBeOK();
    expect(await response.json()).toEqual({
      encryptedToken: zoomEncryptedToken(plainToken, WEBHOOK_SECRETS.zoom),
      plainToken,
    });
  });

  test("stores recording URLs once and exposes the reviewed public recording", async ({
    organizerGroupPage,
    page,
    request,
  }) => {
    const recordingBody = {
      event: "recording.completed",
      payload: {
        object: {
          id: Number(ZOOM_RECORDING_MEETING.providerMeetingId),
          share_url: ZOOM_RECORDING_MEETING.webhookRecordingUrl,
        },
      },
    };

    // Reset the recording fixture before posting webhooks.
    resetZoomRecordingFixture();

    try {
      // Deliver the signed recording webhook and verify the raw provider URL is persisted.
      const firstResponse = await postZoom(request, {
        body: recordingBody,
        secret: WEBHOOK_SECRETS.zoom,
      });
      expect(firstResponse.status()).toBe(200);
      await expect(firstResponse).toBeOK();
      expect(readRecordingUrls()).toEqual([ZOOM_RECORDING_MEETING.webhookRecordingUrl]);

      // Re-deliver the same webhook and verify the database function deduplicates the URL.
      const duplicateResponse = await postZoom(request, {
        body: recordingBody,
        secret: WEBHOOK_SECRETS.zoom,
      });
      expect(duplicateResponse.status()).toBe(200);
      await expect(duplicateResponse).toBeOK();
      expect(readRecordingUrls()).toEqual([ZOOM_RECORDING_MEETING.webhookRecordingUrl]);

      // Open the organizer editor for the past event and verify the raw URL is listed.
      await openPastMeetingEventEditor(organizerGroupPage, ZOOM_RECORDING_EVENT);
      const onlineEventDetails = organizerGroupPage.locator("#online-event-details");
      await expect(
        onlineEventDetails.locator('input[aria-label="Original provider recording 1"]'),
      ).toHaveValue(ZOOM_RECORDING_MEETING.webhookRecordingUrl);

      // Review the raw URL into the final public recording field and publish it.
      await onlineEventDetails
        .locator('input[type="url"][placeholder="https://youtube.com/watch?v=..."]')
        .fill(ZOOM_RECORDING_MEETING.webhookRecordingUrl);
      const publishRecordingToggle = onlineEventDetails.getByLabel("Publish recording publicly");
      if (!(await publishRecordingToggle.isChecked())) {
        await onlineEventDetails.locator("label", { hasText: "Publish recording publicly" }).click();
      }
      await waitForEventEditorAfterSave(
        organizerGroupPage,
        () => organizerGroupPage.locator("#update-event-button").click(),
        {
          eventId: ZOOM_RECORDING_EVENT.id,
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${ZOOM_RECORDING_EVENT.id}/update`,
        },
      );

      // Verify the public event page exposes only the reviewed final recording link.
      await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, ZOOM_RECORDING_EVENT.slug);
      await expect(page.getByRole("link", { name: "View recording" })).toHaveAttribute(
        "href",
        ZOOM_RECORDING_MEETING.webhookRecordingUrl,
      );
    } finally {
      // Restore the seeded recording fixture.
      resetZoomRecordingFixture();
    }
  });

  test("rejects bad signatures", async ({ request }) => {
    // Send a syntactically valid payload with an invalid signature header.
    const response = await postZoom(request, {
      body: { event: "recording.completed" },
      secret: WEBHOOK_SECRETS.zoom,
      signature: "v0=invalid",
    });

    // Verify the invalid signature is rejected.
    expect(response.status()).toBe(401);
  });

  test("rejects malformed JSON", async ({ request }) => {
    // Sign the exact malformed bytes so parsing, not authentication, rejects the request.
    const body = "{";
    const timestamp = Math.floor(Date.now() / 1000);
    const response = await request.post(WEBHOOK_ENDPOINTS.zoom, {
      data: Buffer.from(body),
      headers: {
        "content-type": "application/json",
        "x-zm-request-timestamp": String(timestamp),
        "x-zm-signature": signZoom(body, WEBHOOK_SECRETS.zoom, timestamp),
      },
    });

    // Verify malformed JSON is rejected.
    expect(response.status()).toBe(400);
  });

  test("rejects missing signature headers", async ({ request }) => {
    // Omit Zoom auth headers entirely to exercise the closed authentication path.
    const response = await request.post(WEBHOOK_ENDPOINTS.zoom, {
      data: JSON.stringify({ event: "recording.completed" }),
      headers: { "content-type": "application/json" },
    });

    // Verify requests without signatures are rejected.
    expect(response.status()).toBe(401);
  });

  test("rejects stale timestamps", async ({ request }) => {
    // Sign with a timestamp outside the five-minute replay window.
    const response = await postZoom(request, {
      body: { event: "recording.completed" },
      secret: WEBHOOK_SECRETS.zoom,
      timestamp: 1,
    });

    // Verify stale signatures are rejected.
    expect(response.status()).toBe(401);
  });

  test("ignores unknown event types", async ({ request }) => {
    // Unknown but authenticated events are acknowledged so Zoom does not retry them.
    const response = await postZoom(request, {
      body: { event: "meeting.started" },
      secret: WEBHOOK_SECRETS.zoom,
    });
    expect(response.status()).toBe(200);
    await expect(response).toBeOK();
  });
});

/** Opens the past meeting event editor and its date-venue section. */
const openPastMeetingEventEditor = async (page, event) => {
  await openEventUpdateFormByName(page, event.name, event.id, { eventsTab: "past" });

  const dateVenueSectionButton = page.locator('button[data-section="date-venue"]');
  await dateVenueSectionButton.click();
  await expect(dateVenueSectionButton).toHaveAttribute("data-active", "true");
};

/** Returns recording URLs from the meeting table for the Zoom fixture. */
const readRecordingUrls = () => {
  const rows = queryE2eDatabaseRows(`
    select unnest(recording_urls)
    from meeting
    where meeting_id = '${ZOOM_RECORDING_MEETING.id}'
    order by 1;
  `);

  return rows.map(([recordingUrl]) => recordingUrl);
};

/** Resets meeting and event recording fields for the Zoom fixture. */
const resetZoomRecordingFixture = () => {
  queryE2eDatabase(`
    update meeting
    set
      recording_urls = '{}'::text[],
      updated_at = current_timestamp
    where meeting_id = '${ZOOM_RECORDING_MEETING.id}';

    update event
    set
      meeting_recording_published = false,
      meeting_recording_url = null
    where event_id = '${ZOOM_RECORDING_EVENT.id}';
  `);
};
