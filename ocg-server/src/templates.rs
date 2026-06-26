//! Askama templates for HTML rendering.
//!
//! This module organizes all HTML templates used by the OCG server. Templates are
//! compile-time checked using Askama, providing type safety and performance. The
//! structure mirrors the handler organization.

use serde::{Deserialize, Serialize};

/// Alliance site templates.
pub(crate) mod alliance;
/// Authentication pages templates.
pub(crate) mod auth;
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
/// Global site templates.
pub(crate) mod site;

/// Enum representing unique identifiers for each page in the application.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum PageId {
    CheckIn,
    AllianceDashboard,
    Alliance,
    Event,
    Group,
    GroupDashboard,
    JobsDashboard,
    LogIn,
    SignUp,
    SiteAbout,
    SiteDocs,
    SiteExplore,
    SiteHome,
    SiteJobs,
    SiteLandscape,
    SiteNotFound,
    SiteSearch,
    SiteSponsor,
    SiteStats,
    SiteWiki,
    UserDashboard,
}
