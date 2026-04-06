//! Shared templates and types for dashboard audit logs.

use std::collections::BTreeMap;

use askama::Template;
use chrono::{DateTime, NaiveDate, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::dashboard,
    types::pagination::{self, Pagination, ToRawQuery},
    validation::{MAX_LEN_M, MAX_LEN_SORT_KEY, MAX_PAGINATION_LIMIT, trimmed_non_empty_opt},
};

// Pages templates.

/// Audit log list page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/audit_logs.html")]
pub(crate) struct ListPage {
    /// Available action filter options.
    pub action_options: Vec<AuditActionOption>,
    /// Documentation link for the page.
    pub docs_href: String,
    /// Partial route used by the filters form.
    pub filter_url: String,
    /// Audit rows to display.
    pub logs: Vec<AuditLogEntry>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Description shown under the page title.
    pub page_description: String,
    /// URL used to clear all filters.
    pub reset_url: String,
    /// Whether the actor filter and column are visible.
    pub show_actor: bool,
    /// Current sort selection.
    pub sort_value: String,
    /// Total number of audit rows matching the filters.
    pub total: usize,

    /// Current actor filter value.
    pub actor_value: Option<String>,
    /// Current date-from filter value.
    pub date_from_value: Option<String>,
    /// Current date-to filter value.
    pub date_to_value: Option<String>,
    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Current action filter value.
    pub selected_action: Option<String>,
}

impl ListPage {
    /// Builds a page from shared audit output for the given scope.
    pub(crate) fn new(
        scope: AuditScope,
        filters: &AuditLogFilters,
        output: AuditLogsOutput,
        navigation_links: pagination::NavigationLinks,
    ) -> Self {
        let selected_action = filters.action.clone();
        let mut action_options = scope.action_options();
        for option in &mut action_options {
            option.selected = selected_action.as_deref() == Some(option.value.as_str());
        }

        Self {
            action_options,
            docs_href: scope.docs_href().to_string(),
            filter_url: scope.filter_url().to_string(),
            logs: output.logs.into_iter().map(AuditLogEntry::from).collect(),
            navigation_links,
            page_description: scope.page_description().to_string(),
            reset_url: scope.reset_url().to_string(),
            show_actor: scope.show_actor(),
            sort_value: filters.sort.clone().unwrap_or_else(|| "created-desc".to_string()),
            total: output.total,

            actor_value: filters.actor.clone(),
            date_from_value: filters.date_from.map(|date| date.to_string()),
            date_to_value: filters.date_to.map(|date| date.to_string()),
            limit: filters.limit,
            offset: filters.offset,
            selected_action,
        }
    }
}

// Scopes and actions catalog.

/// Scopes for community-only audit actions.
const COMMUNITY_SCOPES: &[AuditScope] = &[AuditScope::Community];
/// Scopes for shared community and group audit actions.
const COMMUNITY_GROUP_SCOPES: &[AuditScope] = &[AuditScope::Community, AuditScope::Group];
/// Scopes for group-only audit actions.
const GROUP_SCOPES: &[AuditScope] = &[AuditScope::Group];
/// Scopes for user-only audit actions.
const USER_SCOPES: &[AuditScope] = &[AuditScope::User];

/// Shared audit action catalog used by filters and table rows.
const AUDIT_ACTION_DEFINITIONS: &[AuditActionDefinition] = &[
    AuditActionDefinition {
        label: "CFS submission updated",
        scopes: GROUP_SCOPES,
        value: "cfs_submission_updated",
    },
    AuditActionDefinition {
        label: "Community team invitation accepted",
        scopes: USER_SCOPES,
        value: "community_team_invitation_accepted",
    },
    AuditActionDefinition {
        label: "Community team invitation rejected",
        scopes: USER_SCOPES,
        value: "community_team_invitation_rejected",
    },
    AuditActionDefinition {
        label: "Community team member added",
        scopes: COMMUNITY_SCOPES,
        value: "community_team_member_added",
    },
    AuditActionDefinition {
        label: "Community team member removed",
        scopes: COMMUNITY_SCOPES,
        value: "community_team_member_removed",
    },
    AuditActionDefinition {
        label: "Community team member role updated",
        scopes: COMMUNITY_SCOPES,
        value: "community_team_member_role_updated",
    },
    AuditActionDefinition {
        label: "Community updated",
        scopes: COMMUNITY_SCOPES,
        value: "community_updated",
    },
    AuditActionDefinition {
        label: "Event added",
        scopes: GROUP_SCOPES,
        value: "event_added",
    },
    AuditActionDefinition {
        label: "Event attendee checked in",
        scopes: GROUP_SCOPES,
        value: "event_attendee_checked_in",
    },
    AuditActionDefinition {
        label: "Event canceled",
        scopes: GROUP_SCOPES,
        value: "event_canceled",
    },
    AuditActionDefinition {
        label: "Event category added",
        scopes: COMMUNITY_SCOPES,
        value: "event_category_added",
    },
    AuditActionDefinition {
        label: "Event category deleted",
        scopes: COMMUNITY_SCOPES,
        value: "event_category_deleted",
    },
    AuditActionDefinition {
        label: "Event category updated",
        scopes: COMMUNITY_SCOPES,
        value: "event_category_updated",
    },
    AuditActionDefinition {
        label: "Event custom notification sent",
        scopes: GROUP_SCOPES,
        value: "event_custom_notification_sent",
    },
    AuditActionDefinition {
        label: "Event deleted",
        scopes: GROUP_SCOPES,
        value: "event_deleted",
    },
    AuditActionDefinition {
        label: "Event published",
        scopes: GROUP_SCOPES,
        value: "event_published",
    },
    AuditActionDefinition {
        label: "Event unpublished",
        scopes: GROUP_SCOPES,
        value: "event_unpublished",
    },
    AuditActionDefinition {
        label: "Event updated",
        scopes: GROUP_SCOPES,
        value: "event_updated",
    },
    AuditActionDefinition {
        label: "Group activated",
        scopes: COMMUNITY_SCOPES,
        value: "group_activated",
    },
    AuditActionDefinition {
        label: "Group added",
        scopes: COMMUNITY_SCOPES,
        value: "group_added",
    },
    AuditActionDefinition {
        label: "Group category added",
        scopes: COMMUNITY_SCOPES,
        value: "group_category_added",
    },
    AuditActionDefinition {
        label: "Group category deleted",
        scopes: COMMUNITY_SCOPES,
        value: "group_category_deleted",
    },
    AuditActionDefinition {
        label: "Group category updated",
        scopes: COMMUNITY_SCOPES,
        value: "group_category_updated",
    },
    AuditActionDefinition {
        label: "Group custom notification sent",
        scopes: GROUP_SCOPES,
        value: "group_custom_notification_sent",
    },
    AuditActionDefinition {
        label: "Group deactivated",
        scopes: COMMUNITY_SCOPES,
        value: "group_deactivated",
    },
    AuditActionDefinition {
        label: "Group deleted",
        scopes: COMMUNITY_SCOPES,
        value: "group_deleted",
    },
    AuditActionDefinition {
        label: "Group sponsor added",
        scopes: GROUP_SCOPES,
        value: "group_sponsor_added",
    },
    AuditActionDefinition {
        label: "Group sponsor deleted",
        scopes: GROUP_SCOPES,
        value: "group_sponsor_deleted",
    },
    AuditActionDefinition {
        label: "Group sponsor updated",
        scopes: GROUP_SCOPES,
        value: "group_sponsor_updated",
    },
    AuditActionDefinition {
        label: "Group team invitation accepted",
        scopes: USER_SCOPES,
        value: "group_team_invitation_accepted",
    },
    AuditActionDefinition {
        label: "Group team invitation rejected",
        scopes: USER_SCOPES,
        value: "group_team_invitation_rejected",
    },
    AuditActionDefinition {
        label: "Group team member added",
        scopes: GROUP_SCOPES,
        value: "group_team_member_added",
    },
    AuditActionDefinition {
        label: "Group team member removed",
        scopes: GROUP_SCOPES,
        value: "group_team_member_removed",
    },
    AuditActionDefinition {
        label: "Group team member role updated",
        scopes: GROUP_SCOPES,
        value: "group_team_member_role_updated",
    },
    AuditActionDefinition {
        label: "Group updated",
        scopes: COMMUNITY_GROUP_SCOPES,
        value: "group_updated",
    },
    AuditActionDefinition {
        label: "Region added",
        scopes: COMMUNITY_SCOPES,
        value: "region_added",
    },
    AuditActionDefinition {
        label: "Region deleted",
        scopes: COMMUNITY_SCOPES,
        value: "region_deleted",
    },
    AuditActionDefinition {
        label: "Region updated",
        scopes: COMMUNITY_SCOPES,
        value: "region_updated",
    },
    AuditActionDefinition {
        label: "Session proposal added",
        scopes: USER_SCOPES,
        value: "session_proposal_added",
    },
    AuditActionDefinition {
        label: "Session proposal co-speaker invitation accepted",
        scopes: USER_SCOPES,
        value: "session_proposal_co_speaker_invitation_accepted",
    },
    AuditActionDefinition {
        label: "Session proposal co-speaker invitation rejected",
        scopes: USER_SCOPES,
        value: "session_proposal_co_speaker_invitation_rejected",
    },
    AuditActionDefinition {
        label: "Session proposal deleted",
        scopes: USER_SCOPES,
        value: "session_proposal_deleted",
    },
    AuditActionDefinition {
        label: "Session proposal updated",
        scopes: USER_SCOPES,
        value: "session_proposal_updated",
    },
    AuditActionDefinition {
        label: "Submission resubmitted",
        scopes: USER_SCOPES,
        value: "submission_resubmitted",
    },
    AuditActionDefinition {
        label: "Submission withdrawn",
        scopes: USER_SCOPES,
        value: "submission_withdrawn",
    },
    AuditActionDefinition {
        label: "User details updated",
        scopes: USER_SCOPES,
        value: "user_details_updated",
    },
    AuditActionDefinition {
        label: "User password updated",
        scopes: USER_SCOPES,
        value: "user_password_updated",
    },
];

// Types.

/// Shared metadata for one audit action.
#[derive(Debug, Clone, Copy)]
struct AuditActionDefinition {
    /// User-facing label shown in the UI.
    label: &'static str,
    /// Raw action key stored in the audit log.
    value: &'static str,
    /// Dashboard scopes where this action should be listed.
    scopes: &'static [AuditScope],
}

/// Action option shown in the audit filters.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AuditActionOption {
    /// User-facing label for the action.
    pub label: String,
    /// Whether the option is currently selected.
    pub selected: bool,
    /// Raw audit action value.
    pub value: String,
}

/// Detail row rendered inside an audit popover.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AuditLogDetail {
    /// Human-readable detail key.
    pub key_label: String,
    /// Human-readable detail value.
    pub value: String,
}

/// Prepared audit log row for rendering.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AuditLogEntry {
    /// Human-readable action label.
    pub action_label: String,
    /// Unique audit row identifier.
    pub audit_log_id: Uuid,
    /// Timestamp when the action was recorded.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Details prepared for the popover.
    pub details: Vec<AuditLogDetail>,
    /// Popover element identifier for this row.
    pub details_popover_id: String,
    /// Display name for the acted-on resource.
    pub resource_display_name: String,
    /// Human-readable resource type label.
    pub resource_type_label: String,

    /// Snapshot username of the actor when available.
    pub actor_username: Option<String>,
}

impl From<AuditLogRecord> for AuditLogEntry {
    fn from(record: AuditLogRecord) -> Self {
        let resource_display_name = record.resource_name.unwrap_or_else(|| record.resource_id.to_string());
        let details = record
            .details
            .into_iter()
            .map(|(key, value)| AuditLogDetail {
                key_label: humanize_key(&key),
                value: render_detail_value(&value),
            })
            .collect();

        Self {
            action_label: action_label(&record.action).to_string(),
            audit_log_id: record.audit_log_id,
            created_at: record.created_at,
            details,
            details_popover_id: format!("audit-log-details-{}", record.audit_log_id),
            resource_display_name,
            resource_type_label: resource_type_label(&record.resource_type).to_string(),

            actor_username: record.actor_username,
        }
    }
}

/// Shared audit log filter parameters.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct AuditLogFilters {
    /// Raw action key used to filter results.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub action: Option<String>,
    /// Actor username filter used in community and group dashboards.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub actor: Option<String>,
    /// Inclusive start date filter.
    #[garde(skip)]
    pub date_from: Option<NaiveDate>,
    /// Inclusive end date filter.
    #[garde(skip)]
    pub date_to: Option<NaiveDate>,
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
    /// Sort option used to order audit rows.
    #[serde(default = "default_sort")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_SORT_KEY))]
    pub sort: Option<String>,
}

crate::impl_pagination_and_raw_query!(AuditLogFilters, limit, offset);

/// Raw audit log row returned by the database.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AuditLogRecord {
    /// Raw audit action key.
    pub action: String,
    /// Unique audit row identifier.
    pub audit_log_id: Uuid,
    /// Timestamp when the action was recorded.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Raw details object from the audit row.
    pub details: BTreeMap<String, Value>,
    /// Target resource identifier.
    pub resource_id: Uuid,
    /// Raw target resource type.
    pub resource_type: String,

    /// Snapshot username of the actor when available.
    pub actor_username: Option<String>,
    /// Display name for the resource.
    pub resource_name: Option<String>,
}

/// Paginated audit log response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AuditLogsOutput {
    /// Audit rows matching the filters.
    pub logs: Vec<AuditLogRecord>,
    /// Total number of matching rows before pagination.
    pub total: usize,
}

/// Dashboard scope for an audit log screen.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) enum AuditScope {
    /// Community dashboard logs.
    Community,
    /// Group dashboard logs.
    Group,
    /// User dashboard logs.
    User,
}

impl AuditScope {
    /// Returns the action options available for the scope.
    fn action_options(self) -> Vec<AuditActionOption> {
        AUDIT_ACTION_DEFINITIONS
            .iter()
            .filter(|definition| definition.scopes.contains(&self))
            .map(|definition| AuditActionOption {
                label: definition.label.to_string(),
                selected: false,
                value: definition.value.to_string(),
            })
            .collect()
    }

    /// Returns the documentation link for the scope.
    fn docs_href(self) -> &'static str {
        match self {
            AuditScope::Community => "/docs#/guides/community-dashboard?id=audit-logs",
            AuditScope::Group => "/docs#/guides/group-dashboard?id=audit-logs",
            AuditScope::User => "/docs#/guides/user-dashboard?id=audit-logs",
        }
    }

    /// Returns the partial route used to filter the scope.
    fn filter_url(self) -> &'static str {
        match self {
            AuditScope::Community => "/dashboard/community/logs",
            AuditScope::Group => "/dashboard/group/logs",
            AuditScope::User => "/dashboard/user/logs",
        }
    }

    /// Returns the human-readable description for the scope.
    fn page_description(self) -> &'static str {
        match self {
            AuditScope::Community => "Review activity recorded from this community dashboard.",
            AuditScope::Group => "Review activity recorded from this group dashboard.",
            AuditScope::User => "Review actions you performed from your user dashboard.",
        }
    }

    /// Returns the full dashboard URL used to reset the scope.
    fn reset_url(self) -> &'static str {
        match self {
            AuditScope::Community => "/dashboard/community?tab=logs",
            AuditScope::Group => "/dashboard/group?tab=logs",
            AuditScope::User => "/dashboard/user?tab=logs",
        }
    }

    /// Returns whether the actor column should be shown.
    fn show_actor(self) -> bool {
        !matches!(self, AuditScope::User)
    }
}

// Helpers.

/// Finds metadata for a raw audit action value.
fn action_definition(action: &str) -> Option<&'static AuditActionDefinition> {
    AUDIT_ACTION_DEFINITIONS
        .iter()
        .find(|definition| definition.value == action)
}

/// Maps a raw audit action to a user-facing label.
fn action_label(action: &str) -> &'static str {
    action_definition(action).map_or("Audit action", |definition| definition.label)
}

/// Default sort option for audit lists.
#[allow(clippy::unnecessary_wraps)]
fn default_sort() -> Option<String> {
    Some("created-desc".to_string())
}

/// Converts a raw audit detail key into a user-facing label.
fn humanize_key(key: &str) -> String {
    key.split('_')
        .map(|part| {
            if part == "cfs" {
                "CFS".to_string()
            } else {
                let mut chars = part.chars();
                match chars.next() {
                    Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
                    None => String::new(),
                }
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// Formats a JSON detail value for display.
fn render_detail_value(value: &Value) -> String {
    match value {
        Value::Array(_) | Value::Object(_) => value.to_string(),
        Value::Bool(value) => value.to_string(),
        Value::Null => "-".to_string(),
        Value::Number(value) => value.to_string(),
        Value::String(value) => value.clone(),
    }
}

/// Maps a raw resource type to a user-facing label.
fn resource_type_label(resource_type: &str) -> &'static str {
    match resource_type {
        "cfs_submission" => "CFS submission",
        "community" => "Community",
        "event" => "Event",
        "event_category" => "Event category",
        "group" => "Group",
        "group_category" => "Group category",
        "group_sponsor" => "Group sponsor",
        "region" => "Region",
        "session_proposal" => "Session proposal",
        "user" => "User",
        _ => "Resource",
    }
}
