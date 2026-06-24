//! Shared API response types.

use std::collections::BTreeMap;

use serde::Serialize;

/// Standard successful API response envelope.
#[derive(Debug, Clone, Serialize)]
pub(crate) struct ApiResponse<T>
where
    T: Serialize,
{
    /// Response payload.
    pub data: T,
    /// Optional response metadata.
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub meta: BTreeMap<String, serde_json::Value>,
    /// Optional related links.
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub links: BTreeMap<String, String>,
}

impl<T> ApiResponse<T>
where
    T: Serialize,
{
    /// Wrap data in the standard response envelope.
    pub(crate) fn data(data: T) -> Self {
        Self {
            data,
            meta: BTreeMap::new(),
            links: BTreeMap::new(),
        }
    }

    /// Add one metadata field to the response.
    pub(crate) fn with_meta(mut self, key: impl Into<String>, value: impl Serialize) -> Self {
        self.meta.insert(
            key.into(),
            serde_json::to_value(value).unwrap_or(serde_json::Value::Null),
        );
        self
    }
}

/// Empty object used for mutation responses with no additional payload.
#[derive(Debug, Clone, Serialize)]
pub(crate) struct EmptyData {}
