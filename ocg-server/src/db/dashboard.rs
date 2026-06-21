//! Database interfaces for dashboards functionality.
//!
//! This module provides traits and types for dashboards-related database operations.

use async_trait::async_trait;

use crate::db::PgDB;

use common::DBDashboardCommon;
use alliance::DBDashboardAlliance;
use group::DBDashboardGroup;
use user::DBDashboardUser;

/// Common dashboard database operations.
pub(crate) mod common;
/// Alliance dashboard database operations.
pub(crate) mod alliance;
/// Group dashboard database operations.
pub(crate) mod group;
/// User dashboard database operations.
pub(crate) mod user;

/// Unified database trait for all dashboards operations.
#[async_trait]
pub(crate) trait DBDashboard:
    DBDashboardCommon + DBDashboardAlliance + DBDashboardGroup + DBDashboardUser
{
}

impl DBDashboard for PgDB {}
