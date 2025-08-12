//! Database interfaces for dashboards functionality.
//!
//! This module provides traits and types for dashboards-related database operations.

use async_trait::async_trait;

use crate::db::PgDB;

use admin::DBDashboardAdmin;
use group::DBDashboardGroup;

pub(crate) mod admin;
pub(crate) mod group;

/// Unified database trait for all dashboards operations.
#[async_trait]
pub(crate) trait DBDashboard: DBDashboardAdmin + DBDashboardGroup {}

impl DBDashboard for PgDB {}
