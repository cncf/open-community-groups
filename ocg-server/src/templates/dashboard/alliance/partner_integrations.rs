//! Templates and inputs for alliance partner integrations.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};

use crate::{
    types::partner_integration::PartnerIntegration,
    validation::{
        MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_ENTITY_NAME, MAX_LEN_L, image_url_opt,
        trimmed_non_empty, trimmed_non_empty_opt,
    },
};

/// Partner integrations list page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/alliance/partner_integrations.html")]
pub(crate) struct Page {
    pub can_manage_settings: bool,
    pub integrations: Vec<PartnerIntegration>,
}

/// Input used to create or update a partner integration.
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct PartnerIntegrationInput {
    #[garde(length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub attribution_copy: String,
    #[garde(custom(image_url_opt))]
    pub logo_url: Option<String>,
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub name: String,
    #[serde(default)]
    #[garde(skip)]
    pub public: bool,
    #[garde(url, length(max = MAX_LEN_L), custom(trimmed_non_empty_opt))]
    pub website_url: Option<String>,
}
