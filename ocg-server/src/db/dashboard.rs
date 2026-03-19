//! Database interfaces for dashboards functionality.
//!
//! This module provides traits and types for dashboards-related database operations.

use async_trait::async_trait;

use crate::db::PgDB;

use common::DBDashboardCommon;
use community::DBDashboardCommunity;
use group::DBDashboardGroup;
use user::DBDashboardUser;

/// Common dashboard database operations.
pub(crate) mod common;
/// Community dashboard database operations.
pub(crate) mod community;
/// Group dashboard database operations.
pub(crate) mod group;
/// User dashboard database operations.
pub(crate) mod user;

/// Unified database trait for all dashboards operations.
#[async_trait]
pub(crate) trait DBDashboard:
    DBDashboardCommon + DBDashboardCommunity + DBDashboardGroup + DBDashboardUser
{
}

impl DBDashboard for PgDB {}
