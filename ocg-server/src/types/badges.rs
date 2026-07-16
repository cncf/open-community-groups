//! Badge definitions, awards, and public credential database contracts.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Maximum badge criteria length accepted at persistence boundaries.
pub(crate) const BADGE_CRITERIA_MAX_CHARS: usize = 10_000;
/// Maximum badge description length accepted at persistence boundaries.
pub(crate) const BADGE_DESCRIPTION_MAX_CHARS: usize = 10_000;
/// Maximum badge name length accepted at persistence boundaries.
pub(crate) const BADGE_NAME_MAX_CHARS: usize = 200;

/// Result counts returned by a bulk badge award operation.
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct AwardBadgeOutcome {
    /// Number of new credentials inserted.
    pub awarded_count: usize,
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
    /// Event source filter.
    pub event_id: Option<Uuid>,
    /// Inclusive earliest award timestamp.
    pub from: Option<DateTime<Utc>>,
    /// Recipient or badge search text.
    pub query: Option<String>,
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
    /// Explicit recipients to validate and award atomically.
    pub user_ids: Vec<Uuid>,

    /// Event that defines recipient eligibility, when applicable.
    pub event_id: Option<Uuid>,
}

/// Event source represented in group award history.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct BadgeAwardSource {
    /// Event identifier.
    pub event_id: Uuid,
    /// Event name.
    pub name: String,
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
    /// Distinct event sources across the complete group history.
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
    /// Credential award time.
    pub awarded_at: DateTime<Utc>,
    /// Issuing group identifier.
    pub group_id: Uuid,
    /// Immutable badge snapshot.
    pub snapshot: BadgeSnapshot,
    /// Opaque award identifier used by the credential URL.
    pub user_badge_id: Uuid,
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
