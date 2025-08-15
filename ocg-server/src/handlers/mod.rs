//! HTTP request handlers for the OCG server.
//!
//! This module organizes all HTTP request handlers by domain. It also includes shared
//! utilities like error handling and request extractors for common functionality.

/// Authentication handlers.
pub(crate) mod auth;
/// Community site handlers.
pub(crate) mod community;
/// Dashboards handlers.
pub(crate) mod dashboard;
/// Error handling utilities for HTTP handlers.
pub(crate) mod error;
/// Event page handlers.
pub(crate) mod event;
/// Custom extractors for HTTP handlers.
pub(crate) mod extractors;
/// Group site handlers.
pub(crate) mod group;
