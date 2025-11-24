//! This module defines types and logic to manage meeting synchronization with providers.

use std::time::Duration;

use chrono::{DateTime, Utc};
use serde::Serialize;
use serde_with::skip_serializing_none;
use uuid::Uuid;

pub(crate) mod zoom;
mod zoom_api;

pub(crate) use zoom::ZoomMeetingsManager;

/// Represents a meeting to be synced with the provider.
#[skip_serializing_none]
#[derive(Clone, Default, Serialize)]
pub(crate) struct Meeting {
    pub delete: Option<bool>,
    pub duration: Option<Duration>,
    pub event_id: Option<Uuid>,
    pub meeting_id: Option<Uuid>,
    pub password: Option<String>,
    pub provider_meeting_id: Option<String>,
    pub requires_password: Option<bool>,
    pub session_id: Option<Uuid>,
    pub starts_at: Option<DateTime<Utc>>,
    pub timezone: Option<String>,
    pub topic: Option<String>,
    pub url: Option<String>,
}

impl Meeting {
    /// Returns the action to take to sync this meeting with the provider.
    pub(crate) fn sync_action(&self) -> SyncAction {
        if self.delete == Some(true) {
            SyncAction::Delete
        } else if self.provider_meeting_id.is_none() {
            SyncAction::Create
        } else {
            SyncAction::Update
        }
    }
}

/// Action to take to sync a meeting with the provider.
pub(crate) enum SyncAction {
    Create,
    Delete,
    Update,
}
