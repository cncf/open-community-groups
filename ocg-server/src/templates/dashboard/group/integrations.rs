//! Templates for group event discovery settings.

use askama::Template;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Event discovery settings and recent run status.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct IntegrationPage {
    pub can_manage_events: bool,
    pub city: String,
    pub enabled: bool,
    pub latest_run: Option<IntegrationRun>,
    pub sources: Vec<IntegrationSource>,
    pub timezone: String,
}

/// A configured source URL.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct IntegrationSource {
    pub enabled: bool,
    pub group_event_integration_source_id: Uuid,
    pub url: String,
}

/// Summary of one ingestion run.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct IntegrationRun {
    pub completed_at: Option<i64>,
    pub created_count: i32,
    pub discovered_count: i32,
    pub error_message: Option<String>,
    pub started_at: i64,
    pub status: String,
}

/// Partial template rendered inside the group dashboard.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/integrations.html")]
pub(crate) struct Page {
    pub integration: IntegrationPage,
}
