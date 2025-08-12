//! Database interfaces for dashboards functionality.
//!
//! This module provides traits and types for dashboards-related database operations.

use async_trait::async_trait;

use crate::db::PgDB;

use community::DBDashboardCommunity;
use group::DBDashboardGroup;

pub(crate) mod community;
pub(crate) mod group;

/// Unified database trait for all dashboards operations.
#[async_trait]
pub(crate) trait DBDashboard: DBDashboardCommunity + DBDashboardGroup {}

impl DBDashboard for PgDB {}
