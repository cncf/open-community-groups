//! Zoom-backed meetings provider implementation.

use anyhow::Result;
use async_trait::async_trait;
use tracing::info;

use crate::{
    config::MeetingsZoomConfig,
    services::meetings::zoom::client::{
        CreateMeetingRequest, UpdateMeetingRequest, ZOOM_MEETING_NOT_FOUND, ZoomClient,
        ZoomClientError,
    },
};

use super::{
    Meeting, MeetingEndResult, MeetingProviderError, MeetingProviderMeeting, MeetingsProvider,
};

pub(crate) mod client;

#[cfg(test)]
mod tests;

/// Zoom-backed meetings provider implementation.
pub(crate) struct ZoomMeetingsProvider {
    /// Zoom API client.
    client: ZoomClient,
    /// Host users whose meetings are searched before creating a new one.
    host_pool_users: Vec<String>,
}

impl ZoomMeetingsProvider {
    /// Create a new `ZoomMeetingsProvider`.
    pub(crate) fn new(cfg: &MeetingsZoomConfig) -> Result<Self> {
        Ok(Self {
            client: ZoomClient::new(cfg.clone())?,
            host_pool_users: cfg.host_pool_users.clone(),
        })
    }

    /// Find the meeting stamped with the reference across the host pool.
    ///
    /// Returns the Zoom meeting identifier and the pool host that owns it. A
    /// listing failure for any host is propagated, because skipping that host
    /// could miss an existing meeting and lead to a duplicate creation.
    async fn find_meeting_by_reference(
        &self,
        reference: &str,
    ) -> Result<Option<(i64, String)>, MeetingProviderError> {
        for host_user_id in &self.host_pool_users {
            // Walk every page of this host's scheduled meetings
            let mut next_page_token: Option<String> = None;
            loop {
                let page = self
                    .client
                    .list_meetings(host_user_id, next_page_token.as_deref())
                    .await
                    .map_err(MeetingProviderError::from)?;

                // Match on the agenda stamp written at creation
                if let Some(zoom_meeting) = page
                    .meetings
                    .iter()
                    .find(|m| m.agenda.as_deref().is_some_and(|agenda| agenda.trim() == reference))
                {
                    return Ok(Some((zoom_meeting.id, host_user_id.clone())));
                }

                // Stop at the last page, which Zoom marks with an empty or missing token
                match page.next_page_token.filter(|token| !token.is_empty()) {
                    Some(token) => next_page_token = Some(token),
                    None => break,
                }
            }
        }

        Ok(None)
    }
}

#[async_trait]
impl MeetingsProvider for ZoomMeetingsProvider {
    /// Create a meeting with Zoom, adopting one left by an interrupted creation.
    async fn create_meeting(
        &self,
        meeting: &Meeting,
    ) -> Result<MeetingProviderMeeting, MeetingProviderError> {
        // Validate the inputs needed for the provider request
        let host_user_id = meeting.provider_host_user_id.as_deref().ok_or_else(|| {
            MeetingProviderError::Client("missing provider host user id".to_string())
        })?;
        let req = CreateMeetingRequest::try_from(meeting).map_err(MeetingProviderError::from)?;

        // Adopt the meeting when an earlier attempt created it but its response
        // was lost, bringing it up to date and reading back its join details
        if let Some(reference) = meeting.provider_reference()
            && let Some((meeting_id, owner_host_user_id)) =
                self.find_meeting_by_reference(&reference).await?
        {
            info!(
                %reference,
                zoom_meeting_id = meeting_id,
                host_user_id = %owner_host_user_id,
                "adopting existing zoom meeting instead of creating a new one",
            );
            let update =
                UpdateMeetingRequest::try_from(meeting).map_err(MeetingProviderError::from)?;
            self.client
                .update_meeting(meeting_id, &update)
                .await
                .map_err(MeetingProviderError::from)?;
            let zoom_meeting = self
                .client
                .get_meeting(meeting_id)
                .await
                .map_err(MeetingProviderError::from)?;

            return Ok(MeetingProviderMeeting {
                id: zoom_meeting.id.to_string(),
                join_url: zoom_meeting.join_url,
                host_user_id: Some(owner_host_user_id),
                password: zoom_meeting.password,
            });
        }

        // Create the meeting on the assigned host
        let zoom_meeting = self
            .client
            .create_meeting(host_user_id, &req)
            .await
            .map_err(MeetingProviderError::from)?;

        Ok(MeetingProviderMeeting {
            id: zoom_meeting.id.to_string(),
            join_url: zoom_meeting.join_url,
            host_user_id: Some(host_user_id.to_string()),
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
    async fn end_meeting(
        &self,
        provider_meeting_id: &str,
    ) -> Result<MeetingEndResult, MeetingProviderError> {
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
            host_user_id: None,
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
