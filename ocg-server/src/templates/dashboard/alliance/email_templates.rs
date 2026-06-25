//! Templates for alliance dashboard email template settings.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};

use crate::{
    templates::notifications::{
        default_site_onboarding_body, default_site_onboarding_cta_text,
        default_site_onboarding_preheader, default_site_onboarding_subject,
    },
    validation::{
        MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_M, MAX_LEN_NOTIFICATION_BODY, trimmed_non_empty,
    },
};

/// Page template for editable email templates.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/alliance/email_templates.html")]
pub(crate) struct Page {
    /// Whether the current user can manage settings.
    pub can_manage_settings: bool,
    /// Editable onboarding email template.
    pub onboarding: SiteOnboardingEmailTemplate,
}

/// Editable onboarding email template fields.
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct SiteOnboardingEmailTemplate {
    /// Main body copy shown before the fixed starting links.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_NOTIFICATION_BODY))]
    pub body: String,
    /// Button label for the dashboard CTA.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub cta_text: String,
    /// Inbox preheader text.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub preheader: String,
    /// Email subject.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub subject: String,
}

impl Default for SiteOnboardingEmailTemplate {
    fn default() -> Self {
        Self {
            body: default_site_onboarding_body(),
            cta_text: default_site_onboarding_cta_text(),
            preheader: default_site_onboarding_preheader(),
            subject: default_site_onboarding_subject(),
        }
    }
}
