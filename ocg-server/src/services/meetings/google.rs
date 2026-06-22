//! Google Meet-backed meetings provider implementation.

use async_trait::async_trait;

use crate::{
    config::MeetingsGoogleMeetConfig,
    services::meetings::google::client::{
        CalendarEventRequest, GOOGLE_CALENDAR_EVENT_NOT_FOUND, GoogleCalendarClient,
        GoogleCalendarClientError,
    },
};

use super::{
    Meeting, MeetingEndResult, MeetingProviderError, MeetingProviderMeeting, MeetingsProvider,
};

pub(crate) mod client;

/// Google Meet-backed meetings provider implementation.
pub(crate) struct GoogleMeetMeetingsProvider {
    client: GoogleCalendarClient,
}

impl GoogleMeetMeetingsProvider {
    /// Create a new `GoogleMeetMeetingsProvider`.
    pub(crate) fn new(cfg: &MeetingsGoogleMeetConfig) -> Self {
        Self {
            client: GoogleCalendarClient::new(cfg.clone()),
        }
    }
}

#[async_trait]
impl MeetingsProvider for GoogleMeetMeetingsProvider {
    /// Create a Google Calendar event with a Google Meet conference.
    async fn create_meeting(
        &self,
        meeting: &Meeting,
    ) -> Result<MeetingProviderMeeting, MeetingProviderError> {
        let req = CalendarEventRequest::try_from(meeting).map_err(MeetingProviderError::from)?;
        let event = self
            .client
            .create_event(&req)
            .await
            .map_err(MeetingProviderError::from)?;

        Ok(MeetingProviderMeeting {
            id: event.id,
            join_url: event.meet_url.ok_or_else(|| {
                MeetingProviderError::Client(
                    "google calendar event did not include a meet join url".to_string(),
                )
            })?,
            password: None,
        })
    }

    /// Delete the backing Google Calendar event.
    async fn delete_meeting(&self, provider_meeting_id: &str) -> Result<(), MeetingProviderError> {
        match self.client.delete_event(provider_meeting_id).await {
            Ok(()) => Ok(()),
            Err(GoogleCalendarClientError::Client { code, .. })
                if code == GOOGLE_CALENDAR_EVENT_NOT_FOUND =>
            {
                Err(MeetingProviderError::NotFound)
            }
            Err(e) => Err(MeetingProviderError::from(e)),
        }
    }

    /// Google Meet does not support the same explicit host-side end call as Zoom.
    async fn end_meeting(
        &self,
        _provider_meeting_id: &str,
    ) -> Result<MeetingEndResult, MeetingProviderError> {
        Ok(MeetingEndResult::AlreadyNotRunning)
    }

    /// Get the backing Google Calendar event details.
    async fn get_meeting(
        &self,
        provider_meeting_id: &str,
    ) -> Result<MeetingProviderMeeting, MeetingProviderError> {
        let event = self
            .client
            .get_event(provider_meeting_id)
            .await
            .map_err(MeetingProviderError::from)?;

        Ok(MeetingProviderMeeting {
            id: event.id,
            join_url: event.meet_url.ok_or_else(|| {
                MeetingProviderError::Client(
                    "google calendar event did not include a meet join url".to_string(),
                )
            })?,
            password: None,
        })
    }

    /// Update the backing Google Calendar event.
    async fn update_meeting(
        &self,
        provider_meeting_id: &str,
        meeting: &Meeting,
    ) -> Result<(), MeetingProviderError> {
        let req = CalendarEventRequest::try_from(meeting).map_err(MeetingProviderError::from)?;
        self.client
            .update_event(provider_meeting_id, &req)
            .await
            .map_err(MeetingProviderError::from)?;

        Ok(())
    }
}
