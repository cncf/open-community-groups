//! Community dashboard region types.

use garde::Validate;
use serde::{Deserialize, Serialize};

use crate::validation::{MAX_LEN_ENTITY_NAME, trimmed_non_empty};

/// Region form payload used by create and update operations.
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct RegionInput {
    /// Region name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub name: String,
}
