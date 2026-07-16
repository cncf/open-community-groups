//! Templates and types for group intentional dating curation.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    db::dashboard::common::IntentionalDatingOptIn,
    validation::{MAX_LEN_DESCRIPTION_SHORT, optional_trimmed_string, trimmed_non_empty_opt},
};

/// Group-level intentional dating curation page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/intentional_dating.html")]
pub(crate) struct ListPage {
    /// Whether the current user can curate introductions.
    pub can_manage_introductions: bool,
    /// Private opt-ins visible to authorized group admins.
    pub opt_ins: Vec<IntentionalDatingOptIn>,
}

/// Admin-created introduction form.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct IntroForm {
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
}
