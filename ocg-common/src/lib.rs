//! Shared building blocks for the Open Community Groups binaries.
//!
//! This crate consolidates the configuration types, database helpers, and
//! runtime helpers used by both the OCG server and the OCG redirector.

#![warn(clippy::all, clippy::pedantic)]

/// Shared configuration types.
pub mod config;
/// Shared database helpers.
pub mod db;
/// Shared runtime helpers.
pub mod runtime;
