//! Partner integration records displayed on alliance pages.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// A partner integration configured for an alliance.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct PartnerIntegration {
    pub attribution_copy: String,
    pub logo_url: Option<String>,
    pub name: String,
    pub partner_integration_id: Uuid,
    pub public: bool,
    pub website_url: Option<String>,
}
