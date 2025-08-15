//! Askama templates for HTML rendering.
//!
//! This module organizes all HTML templates used by the OCG server. Templates are
//! compile-time checked using Askama, providing type safety and performance. The
//! structure mirrors the handler organization.

use serde::{Deserialize, Serialize};

pub(crate) mod auth;
pub(crate) mod common;
pub(crate) mod community;
pub(crate) mod dashboard;
pub(crate) mod event;
mod filters;
pub(crate) mod group;
pub(crate) mod helpers;

/// Enum representing unique identifiers for each page in the application.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum PageId {
    Community,
    CommunityDashboard,
    Event,
    Group,
    GroupDashboard,
    LogIn,
    SignUp,
}
