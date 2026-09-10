//! Group dashboard home types.

use serde::{Deserialize, Serialize};

use crate::types::{community::CommunitySummary, group::GroupMinimal};

/// Groups organized by community, used for displaying user's groups in dashboard.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct UserGroupsByCommunity {
    /// Community information.
    pub community: CommunitySummary,
    /// Groups belonging to this community.
    pub groups: Vec<GroupMinimal>,
}
