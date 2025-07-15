//! Askama templates for HTML rendering.
//!
//! This module organizes all HTML templates used by the OCG server. Templates are
//! compile-time checked using Askama, providing type safety and performance. The
//! structure mirrors the handler organization.

pub(crate) mod common;
pub(crate) mod community;
pub(crate) mod event;
mod filters;
pub(crate) mod group;
mod helpers;
