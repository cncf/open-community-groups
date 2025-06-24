//! HTTP request handlers for the OCG server.
//!
//! This module organizes all HTTP request handlers by domain. It also includes shared
//! utilities like error handling and request extractors for common functionality.

/// Community site handlers.
pub(crate) mod community;
/// Error handling utilities for HTTP handlers.
mod error;
/// Event page handlers.
pub(crate) mod event;
/// Custom extractors for HTTP handlers.
mod extractors;
/// Group site handlers.
pub(crate) mod group;
