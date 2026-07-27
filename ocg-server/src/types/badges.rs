//! Badge definitions, awards, and public credential database contracts.

use std::{fmt, str::FromStr};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_with::{DeserializeFromStr, SerializeDisplay};
use uuid::Uuid;

/// Maximum badge criteria length accepted at persistence boundaries.
pub(crate) const BADGE_CRITERIA_MAX_CHARS: usize = 10_000;

/// Maximum badge description length accepted at persistence boundaries.
pub(crate) const BADGE_DESCRIPTION_MAX_CHARS: usize = 10_000;

/// Maximum badge name length accepted at persistence boundaries.
pub(crate) const BADGE_NAME_MAX_CHARS: usize = 200;

/// Stable filter value that selects direct group awards.
const GROUP_AWARD_SOURCE_VALUE: &str = "group";

/// Result counts returned by a bulk badge award operation.
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct AwardBadgeOutcome {
    /// Number of new credentials queued for durable issuance.
    pub queued_count: usize,
    /// Number of recipients who already held an active badge.
    pub skipped_count: usize,
}

/// Search and pagination filters for group award history.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub(crate) struct AwardedBadgesFilters {
    /// Page size.
    pub limit: usize,
    /// Result offset.
    pub offset: usize,

    /// Badge definition filter.
    pub badge_id: Option<Uuid>,
    /// Inclusive earliest award timestamp.
    pub from: Option<DateTime<Utc>>,
    /// Recipient or badge search text.
    pub query: Option<String>,
    /// Award source filter.
    pub source: Option<BadgeAwardSourceFilter>,
    /// Active or revoked status filter.
    pub status: Option<String>,
    /// Exclusive latest award timestamp.
    pub to: Option<DateTime<Utc>>,
}

/// Group-owned badge definition.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct Badge {
    /// Unique definition identifier.
    pub badge_id: Uuid,
    /// Human-readable achievement criteria.
    pub criteria: String,
    /// Human-readable badge description.
    pub description: String,
    /// Content-addressed artwork file name.
    pub image_file_name: String,
    /// Badge name.
    pub name: String,
}

/// Reusable group gallery artwork.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct BadgeArtwork {
    /// Unique gallery entry identifier.
    pub badge_artwork_id: Uuid,
    /// Content-addressed image file name.
    pub file_name: String,
}

/// Badge definition represented in group award history.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct BadgeAwardDefinition {
    /// Badge definition identifier.
    pub badge_id: Uuid,
    /// Current badge name.
    pub name: String,
}

/// Database input for one badge award operation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct BadgeAwardInput {
    /// Badge definition to award.
    pub badge_id: Uuid,
    /// Explicit recipients to validate and queue atomically.
    pub user_ids: Vec<Uuid>,

    /// Event that defines recipient eligibility, when applicable.
    pub event_id: Option<Uuid>,
}

/// Award source represented in group award history.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct BadgeAwardSource {
    /// Source display name.
    pub name: String,

    /// Source event identifier, absent for direct group awards.
    pub event_id: Option<Uuid>,
}

impl BadgeAwardSource {
    /// Returns the filter value that selects this source.
    pub(crate) fn filter(&self) -> BadgeAwardSourceFilter {
        match self.event_id {
            Some(event_id) => BadgeAwardSourceFilter::Event(event_id),
            None => BadgeAwardSourceFilter::Group,
        }
    }
}

/// Award source filter accepted by group award history.
#[derive(Clone, Copy, Debug, DeserializeFromStr, Eq, PartialEq, SerializeDisplay)]
pub(crate) enum BadgeAwardSourceFilter {
    /// Awards issued through a specific event.
    Event(Uuid),
    /// Direct group awards without an event source.
    Group,
}

impl fmt::Display for BadgeAwardSourceFilter {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BadgeAwardSourceFilter::Event(event_id) => write!(f, "{event_id}"),
            BadgeAwardSourceFilter::Group => f.write_str(GROUP_AWARD_SOURCE_VALUE),
        }
    }
}

impl FromStr for BadgeAwardSourceFilter {
    type Err = uuid::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        if s == GROUP_AWARD_SOURCE_VALUE {
            return Ok(BadgeAwardSourceFilter::Group);
        }
        Ok(BadgeAwardSourceFilter::Event(Uuid::from_str(s)?))
    }
}

/// Search and pagination filters for group badge definitions.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub(crate) struct BadgeFilters {
    /// Page size.
    pub limit: usize,
    /// Result offset.
    pub offset: usize,

    /// Full-text search query.
    pub query: Option<String>,
}

/// Input accepted when creating or updating a badge definition.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub(crate) struct BadgeInput {
    /// Human-readable achievement criteria.
    pub criteria: String,
    /// Human-readable badge description.
    pub description: String,
    /// Content-addressed artwork file name.
    pub image_file_name: String,
    /// Badge name.
    pub name: String,
}

/// Immutable badge fields captured when a credential is issued.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct BadgeSnapshot {
    /// Human-readable achievement criteria.
    pub criteria: String,
    /// Human-readable badge description.
    pub description: String,
    /// Content-addressed artwork file name.
    pub image_file_name: String,
    /// Immutable issuer display context.
    pub issuer: BadgeSnapshotIssuer,
    /// Badge name.
    pub name: String,
}

/// Immutable issuer display fields captured for a credential.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct BadgeSnapshotIssuer {
    /// Issuing community identifier.
    pub community_id: Uuid,
    /// Issuing community display name.
    pub community_name: String,
    /// Issuing group identifier.
    pub group_id: Uuid,
    /// Issuing group display name.
    pub group_name: String,
}

/// Stable group-scoped revocation list state.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct BadgeStatusList {
    /// Stable status-list identifier.
    pub badge_status_list_id: Uuid,
    /// Issuing group identifier.
    pub group_id: Uuid,
    /// Sorted revoked indexes contained in the list.
    pub revoked_indexes: Vec<i32>,
}
/// Paginated group award-history output.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub(crate) struct GroupAwardedBadges {
    /// Awards in the current result page.
    pub awards: Vec<UserBadge>,
    /// Distinct current definitions represented across the complete history.
    pub badges: Vec<BadgeAwardDefinition>,
    /// Distinct award sources across the complete group history.
    pub sources: Vec<BadgeAwardSource>,
    /// Total number of matching history rows.
    pub total: usize,
}

/// Paginated group badge-definition output.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub(crate) struct GroupBadges {
    /// Definitions in the current result page.
    pub badges: Vec<Badge>,
    /// Total number of matching definitions.
    pub total: usize,
}

/// Public profile badge summary.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct PublicUserBadge {
    /// Minimal immutable fields rendered by public profiles.
    pub snapshot: PublicBadgeSnapshot,
    /// Opaque award identifier used by the credential URL.
    pub user_badge_id: Uuid,
}

/// Minimal immutable badge fields exposed by public profiles.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct PublicBadgeSnapshot {
    /// Content-addressed artwork file name.
    pub image_file_name: String,
    /// Minimal issuer context rendered by public profiles.
    pub issuer: PublicBadgeSnapshotIssuer,
    /// Badge name.
    pub name: String,
}

/// Minimal immutable issuer fields exposed by public profiles.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct PublicBadgeSnapshotIssuer {
    /// Issuing community display name.
    pub community_name: String,
    /// Issuing group display name.
    pub group_name: String,
}

/// Durable badge award and credential issuance state.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct UserBadge {
    /// Credential award time.
    pub awarded_at: DateTime<Utc>,
    /// Stable revocation-list identifier.
    pub badge_status_list_id: Uuid,
    /// User-selected profile display order.
    pub display_order: i32,
    /// Issuing group identifier.
    pub group_id: Uuid,
    /// Whether profiles may discover this badge.
    pub is_listed: bool,
    /// Immutable badge and issuer display context.
    pub snapshot: BadgeSnapshot,
    /// Credential index in the referenced status list.
    pub status_list_index: i32,
    /// Opaque award identifier.
    pub user_badge_id: Uuid,

    /// Current definition identifier, when retained.
    pub badge_id: Option<Uuid>,
    /// Award source event identifier.
    pub event_id: Option<Uuid>,
    /// Award source event name for group history.
    pub event_name: Option<String>,
    /// Identity binding creation time used as the export proof timestamp.
    pub identity_bound_at: Option<DateTime<Utc>>,
    /// Hex-encoded SHA-256 digest of the bound lowercased email and salt.
    pub identity_hash: Option<String>,
    /// Salt appended to the bound lowercased email before hashing.
    pub identity_salt: Option<String>,
    /// Current recipient display name for authorized history and local verification.
    pub recipient_name: Option<String>,
    /// Current recipient username for authorized history and local verification.
    pub recipient_username: Option<String>,
    /// Private internal revocation reason.
    pub revocation_reason: Option<String>,
    /// Credential revocation time.
    pub revoked_at: Option<DateTime<Utc>>,
    /// User who performed the revocation, when retained.
    pub revoked_by_user_id: Option<Uuid>,
    /// Current internal recipient association.
    pub user_id: Option<Uuid>,
}

/// Persisted recipient email identity binding for one badge award.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct UserBadgeIdentity {
    /// Binding creation time used as the export proof timestamp.
    pub identity_bound_at: DateTime<Utc>,
    /// Hex-encoded SHA-256 digest of the bound lowercased email and salt.
    pub identity_hash: String,
    /// Salt appended to the bound lowercased email before hashing.
    pub identity_salt: String,
}
