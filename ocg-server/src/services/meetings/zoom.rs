//! Zoom-backed meetings provider implementation.

use async_trait::async_trait;

use crate::{
    config::MeetingsZoomConfig,
    services::meetings::zoom::client::{
        CreateMeetingRequest, UpdateMeetingRequest, ZOOM_MEETING_NOT_FOUND, ZoomClient, ZoomClientError,
    },
};

use super::{Meeting, MeetingEndResult, MeetingProviderError, MeetingProviderMeeting, MeetingsProvider};

pub(crate) mod client;

/// Zoom-backed meetings provider implementation.
pub(crate) struct ZoomMeetingsProvider {
    client: ZoomClient,
}

impl ZoomMeetingsProvider {
    /// Create a new `ZoomMeetingsProvider`.
    pub(crate) fn new(cfg: &MeetingsZoomConfig) -> Self {
        Self {
            client: ZoomClient::new(cfg.clone()),
        }
    }
}

#[async_trait]
impl MeetingsProvider for ZoomMeetingsProvider {
    /// Create a meeting with Zoom.
    async fn create_meeting(
        &self,
        meeting: &Meeting,
    ) -> Result<MeetingProviderMeeting, MeetingProviderError> {
        let host_user_id = meeting
            .provider_host_user_id
            .as_deref()
            .ok_or_else(|| MeetingProviderError::Client("missing provider host user id".to_string()))?;
        let req = CreateMeetingRequest::try_from(meeting).map_err(MeetingProviderError::from)?;
        let zoom_meeting = self
            .client
            .create_meeting(host_user_id, &req)
            .await
            .map_err(MeetingProviderError::from)?;

        Ok(MeetingProviderMeeting {
            id: zoom_meeting.id.to_string(),
            join_url: zoom_meeting.join_url,
            password: zoom_meeting.password,
        })
    }

    /// Delete a meeting from Zoom.
    async fn delete_meeting(&self, provider_meeting_id: &str) -> Result<(), MeetingProviderError> {
        let meeting_id: i64 = provider_meeting_id
            .parse()
            .map_err(|e: std::num::ParseIntError| MeetingProviderError::Client(e.to_string()))?;

        match self.client.delete_meeting(meeting_id).await {
            Ok(()) => Ok(()),
            Err(ZoomClientError::Client { code, .. }) if code == ZOOM_MEETING_NOT_FOUND => {
                Err(MeetingProviderError::NotFound)
            }
            Err(e) => Err(MeetingProviderError::from(e)),
        }
    }

    /// End a meeting in Zoom after checking it is still running.
    async fn end_meeting(&self, provider_meeting_id: &str) -> Result<MeetingEndResult, MeetingProviderError> {
        let meeting_id: i64 = provider_meeting_id
            .parse()
            .map_err(|e: std::num::ParseIntError| MeetingProviderError::Client(e.to_string()))?;

        // Check current meeting status first to avoid unnecessary end calls
        let zoom_meeting = self
            .client
            .get_meeting(meeting_id)
            .await
            .map_err(MeetingProviderError::from)?;
        let is_started = zoom_meeting
            .status
            .as_deref()
            .is_some_and(|status| status.eq_ignore_ascii_case("started"));
        if !is_started {
            return Ok(MeetingEndResult::AlreadyNotRunning);
        }

        self.client
            .end_meeting(meeting_id)
            .await
            .map_err(MeetingProviderError::from)?;

        Ok(MeetingEndResult::Ended)
    }

    /// Get meeting details from Zoom.
    async fn get_meeting(
        &self,
        provider_meeting_id: &str,
    ) -> Result<MeetingProviderMeeting, MeetingProviderError> {
        let meeting_id: i64 = provider_meeting_id
            .parse()
            .map_err(|e: std::num::ParseIntError| MeetingProviderError::Client(e.to_string()))?;

        let zoom_meeting = self
            .client
            .get_meeting(meeting_id)
            .await
            .map_err(MeetingProviderError::from)?;

        Ok(MeetingProviderMeeting {
            id: zoom_meeting.id.to_string(),
            join_url: zoom_meeting.join_url,
            password: zoom_meeting.password,
        })
    }

    /// Update a meeting on Zoom.
    async fn update_meeting(
        &self,
        provider_meeting_id: &str,
        meeting: &Meeting,
    ) -> Result<(), MeetingProviderError> {
        let meeting_id: i64 = provider_meeting_id
            .parse()
            .map_err(|e: std::num::ParseIntError| MeetingProviderError::Client(e.to_string()))?;

        let req = UpdateMeetingRequest::try_from(meeting).map_err(MeetingProviderError::from)?;
        self.client
            .update_meeting(meeting_id, &req)
            .await
            .map_err(MeetingProviderError::from)?;

        Ok(())
    }
}
