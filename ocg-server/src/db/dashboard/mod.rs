//! Database interfaces for dashboards functionality.
//!
//! This module provides traits and types for dashboards-related database operations.

use async_trait::async_trait;

use crate::db::PgDB;

use common::DBDashboardCommon;
use community::DBDashboardCommunity;
use group::DBDashboardGroup;

pub(crate) mod common;
pub(crate) mod community;
pub(crate) mod group;

/// Unified database trait for all dashboards operations.
#[async_trait]
pub(crate) trait DBDashboard: DBDashboardCommon + DBDashboardCommunity + DBDashboardGroup {}

impl DBDashboard for PgDB {}
