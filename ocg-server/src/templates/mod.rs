//! Askama templates for HTML rendering.
//!
//! This module organizes all HTML templates used by the OCG server. Templates are
//! compile-time checked using Askama, providing type safety and performance. The
//! structure mirrors the handler organization.

use serde::{Deserialize, Serialize};

/// Authentication pages templates.
pub(crate) mod auth;
/// Common template components and utilities.
pub(crate) mod common;
/// Community site templates.
pub(crate) mod community;
/// Dashboard templates.
pub(crate) mod dashboard;
/// Event page templates.
pub(crate) mod event;
/// Custom Askama template filters.
mod filters;
/// Group site templates.
pub(crate) mod group;
/// Template helper functions and utilities.
pub(crate) mod helpers;
/// Notification templates.
pub(crate) mod notifications;
/// Pagination types and helpers.
pub(crate) mod pagination;
/// Global site templates.
pub(crate) mod site;

/// Enum representing unique identifiers for each page in the application.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum PageId {
    CheckIn,
    CommunityDashboard,
    Community,
    Event,
    Group,
    GroupDashboard,
    LogIn,
    SignUp,
    SiteExplore,
    SiteHome,
    UserDashboard,
}
