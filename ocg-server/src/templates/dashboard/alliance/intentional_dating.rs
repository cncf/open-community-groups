//! Templates and types for alliance intentional dating curation.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    db::dashboard::common::IntentionalDatingOptIn,
    validation::{MAX_LEN_DESCRIPTION_SHORT, optional_trimmed_string, trimmed_non_empty_opt},
};

/// Alliance-level intentional dating curation page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/alliance/intentional_dating.html")]
pub(crate) struct ListPage {
    /// Whether the current user can curate introductions.
    pub can_manage_introductions: bool,
    /// Private opt-ins visible to authorized alliance admins.
    pub opt_ins: Vec<IntentionalDatingOptIn>,
}

/// Admin-created introduction form.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct IntroForm {
    /// Group context for the introduction.
    #[garde(skip)]
    pub group_id: Uuid,
    /// First opted-in member.
    #[garde(skip)]
    pub first_user_id: Uuid,
    /// Second opted-in member.
    #[garde(skip)]
    pub second_user_id: Uuid,
    /// Private admin notes.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub admin_notes: Option<String>,
    /// Optional message sent to both introduced members.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub notification_message: Option<String>,
}
