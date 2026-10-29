//! Shared templates and types for dashboard audit logs.

use askama::Template;
use chrono::{DateTime, Utc};
use serde_json::Value;

use crate::types::dashboard::common::{
    AuditLogFilters, AuditLogRecord, AuditLogSort, AuditLogsOutput,
};
use crate::types::pagination;

// Pages templates.

/// Audit log list page template.
#[derive(Debug, Clone, Template)]
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
    /// Pagination offset for results.
    pub offset: Option<usize>,
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
            sort_value: filters.sort.unwrap_or(AuditLogSort::CreatedDesc).to_string(),
            total: output.total,

            actor_value: filters.actor.clone(),
            date_from_value: filters.date_from.map(|date| date.to_string()),
            date_to_value: filters.date_to.map(|date| date.to_string()),
            offset: filters.offset,
        }
    }
}

// Scopes and actions catalog.

/// Scopes for community-only audit actions.
const COMMUNITY_SCOPES: &[AuditScope] = &[AuditScope::Community];
/// Scopes for shared community and group audit actions.
const COMMUNITY_GROUP_SCOPES: &[AuditScope] = &[AuditScope::Community, AuditScope::Group];
/// Scopes for shared community and user audit actions.
const COMMUNITY_USER_SCOPES: &[AuditScope] = &[AuditScope::Community, AuditScope::User];
/// Scopes for group-only audit actions.
const GROUP_SCOPES: &[AuditScope] = &[AuditScope::Group];
/// Scopes for shared group and user audit actions.
const GROUP_USER_SCOPES: &[AuditScope] = &[AuditScope::Group, AuditScope::User];
/// Scopes for user-only audit actions.
const USER_SCOPES: &[AuditScope] = &[AuditScope::User];

/// Shared audit action catalog used by filters and table rows.
const AUDIT_ACTION_DEFINITIONS: &[AuditActionDefinition] = &[
    AuditActionDefinition {
        label: "Event ticket offer expired",
        scopes: GROUP_SCOPES,
        value: "admission_offer_expired",
    },
    AuditActionDefinition {
        label: "Badge added",
        scopes: GROUP_SCOPES,
        value: "badge_added",
    },
    AuditActionDefinition {
        label: "Badge artwork added",
        scopes: GROUP_SCOPES,
        value: "badge_artwork_added",
    },
    AuditActionDefinition {
        label: "Badge artwork deleted",
        scopes: GROUP_SCOPES,
        value: "badge_artwork_deleted",
    },
    AuditActionDefinition {
        label: "Badge awarded",
        scopes: GROUP_SCOPES,
        value: "badge_awarded",
    },
    AuditActionDefinition {
        label: "Badge deleted",
        scopes: GROUP_SCOPES,
        value: "badge_deleted",
    },
    AuditActionDefinition {
        label: "Badge revoked",
        scopes: GROUP_SCOPES,
        value: "badge_revoked",
    },
    AuditActionDefinition {
        label: "Badge revoked after account deletion",
        scopes: GROUP_SCOPES,
        value: "badge_revoked_account_deleted",
    },
    AuditActionDefinition {
        label: "Badge revoked by recipient",
        scopes: GROUP_SCOPES,
        value: "badge_revoked_by_recipient",
    },
    AuditActionDefinition {
        label: "Badge updated",
        scopes: GROUP_SCOPES,
        value: "badge_updated",
    },
    AuditActionDefinition {
        label: "CFS submission updated",
        scopes: GROUP_SCOPES,
        value: "cfs_submission_updated",
    },
    AuditActionDefinition {
        label: "Community custom notification sent",
        scopes: COMMUNITY_SCOPES,
        value: "community_custom_notification_sent",
    },
    AuditActionDefinition {
        label: "Community team invitation accepted",
        scopes: COMMUNITY_USER_SCOPES,
        value: "community_team_invitation_accepted",
    },
    AuditActionDefinition {
        label: "Community team invitation rejected",
        scopes: COMMUNITY_USER_SCOPES,
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
        label: "Event ticket offer canceled",
        scopes: GROUP_SCOPES,
        value: "event_admission_offer_canceled",
    },
    AuditActionDefinition {
        label: "Event ticket offer declined",
        scopes: GROUP_USER_SCOPES,
        value: "event_admission_offer_declined",
    },
    AuditActionDefinition {
        label: "Event ticket offer reissued",
        scopes: GROUP_SCOPES,
        value: "event_admission_offer_reissued",
    },
    AuditActionDefinition {
        label: "Event application-fee recovery completed",
        scopes: GROUP_SCOPES,
        value: "event_application_fee_adjustment_recovery_completed",
    },
    AuditActionDefinition {
        label: "Event attendance canceled",
        scopes: GROUP_SCOPES,
        value: "event_attendee_attendance_canceled",
    },
    AuditActionDefinition {
        label: "Event attendee checked in",
        scopes: GROUP_SCOPES,
        value: "event_attendee_checked_in",
    },
    AuditActionDefinition {
        label: "Event attendee invitation accepted",
        scopes: GROUP_USER_SCOPES,
        value: "event_attendee_invitation_accepted",
    },
    AuditActionDefinition {
        label: "Event attendee invitation canceled",
        scopes: GROUP_SCOPES,
        value: "event_attendee_invitation_canceled",
    },
    AuditActionDefinition {
        label: "Event attendee invitation rejected",
        scopes: GROUP_USER_SCOPES,
        value: "event_attendee_invitation_rejected",
    },
    AuditActionDefinition {
        label: "Event attendee invitation sent",
        scopes: GROUP_SCOPES,
        value: "event_attendee_invitation_sent",
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
        label: "Event co-host approved",
        scopes: GROUP_SCOPES,
        value: "event_cohost_approved",
    },
    AuditActionDefinition {
        label: "Event co-host canceled",
        scopes: GROUP_SCOPES,
        value: "event_cohost_canceled",
    },
    AuditActionDefinition {
        label: "Event co-host closed",
        scopes: GROUP_SCOPES,
        value: "event_cohost_closed",
    },
    AuditActionDefinition {
        label: "Event co-host invited",
        scopes: GROUP_SCOPES,
        value: "event_cohost_invited",
    },
    AuditActionDefinition {
        label: "Event co-host rejected",
        scopes: GROUP_SCOPES,
        value: "event_cohost_rejected",
    },
    AuditActionDefinition {
        label: "Event co-host removed",
        scopes: GROUP_SCOPES,
        value: "event_cohost_removed",
    },
    AuditActionDefinition {
        label: "Event credit note recovery completed",
        scopes: GROUP_SCOPES,
        value: "event_credit_note_recovery_completed",
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
        label: "Event invitation request accepted",
        scopes: GROUP_SCOPES,
        value: "event_invitation_request_accepted",
    },
    AuditActionDefinition {
        label: "Event invitation request rejected",
        scopes: GROUP_SCOPES,
        value: "event_invitation_request_rejected",
    },
    AuditActionDefinition {
        label: "Event published",
        scopes: GROUP_SCOPES,
        value: "event_published",
    },
    AuditActionDefinition {
        label: "Event external payment completed",
        scopes: GROUP_SCOPES,
        value: "event_purchase_external_payment_completed",
    },
    AuditActionDefinition {
        label: "Event refund approved",
        scopes: GROUP_SCOPES,
        value: "event_refund_approved",
    },
    AuditActionDefinition {
        label: "Event refund recovery completed",
        scopes: GROUP_SCOPES,
        value: "event_refund_recovery_completed",
    },
    AuditActionDefinition {
        label: "Event refund rejected",
        scopes: GROUP_SCOPES,
        value: "event_refund_rejected",
    },
    AuditActionDefinition {
        label: "Event refund requested",
        scopes: GROUP_SCOPES,
        value: "event_refund_requested",
    },
    AuditActionDefinition {
        label: "Event refunded",
        scopes: GROUP_SCOPES,
        value: "event_refunded",
    },
    AuditActionDefinition {
        label: "Event survey added",
        scopes: GROUP_SCOPES,
        value: "event_survey_added",
    },
    AuditActionDefinition {
        label: "Event survey closed",
        scopes: GROUP_SCOPES,
        value: "event_survey_closed",
    },
    AuditActionDefinition {
        label: "Event survey deleted",
        scopes: GROUP_SCOPES,
        value: "event_survey_deleted",
    },
    AuditActionDefinition {
        label: "Event survey marked ready",
        scopes: GROUP_SCOPES,
        value: "event_survey_marked_ready",
    },
    AuditActionDefinition {
        label: "Event survey moved to draft",
        scopes: GROUP_SCOPES,
        value: "event_survey_moved_to_draft",
    },
    AuditActionDefinition {
        label: "Event survey reopened",
        scopes: GROUP_SCOPES,
        value: "event_survey_reopened",
    },
    AuditActionDefinition {
        label: "Event survey updated",
        scopes: GROUP_SCOPES,
        value: "event_survey_updated",
    },
    AuditActionDefinition {
        label: "Event waitlist ticket offer created",
        scopes: GROUP_SCOPES,
        value: "event_ticket_waitlist_offer_created",
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
        label: "Group external payments updated",
        scopes: COMMUNITY_GROUP_SCOPES,
        value: "group_external_payments_updated",
    },
    AuditActionDefinition {
        label: "Group notifications muted",
        scopes: USER_SCOPES,
        value: "group_notifications_muted",
    },
    AuditActionDefinition {
        label: "Group notifications unmuted",
        scopes: USER_SCOPES,
        value: "group_notifications_unmuted",
    },
    AuditActionDefinition {
        label: "Group payment recipient updated",
        scopes: COMMUNITY_GROUP_SCOPES,
        value: "group_payment_recipient_updated",
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
        label: "Inbox conversation closed",
        scopes: GROUP_SCOPES,
        value: "inbox_conversation_closed",
    },
    AuditActionDefinition {
        label: "Inbox conversation marked as spam",
        scopes: GROUP_SCOPES,
        value: "inbox_conversation_marked_as_spam",
    },
    AuditActionDefinition {
        label: "Inbox conversation reopened",
        scopes: GROUP_SCOPES,
        value: "inbox_conversation_reopened",
    },
    AuditActionDefinition {
        label: "Inbox conversation started",
        scopes: USER_SCOPES,
        value: "inbox_conversation_started",
    },
    AuditActionDefinition {
        label: "Inbox conversation unmarked as spam",
        scopes: GROUP_SCOPES,
        value: "inbox_conversation_unmarked_as_spam",
    },
    AuditActionDefinition {
        label: "Inbox message sent",
        scopes: USER_SCOPES,
        value: "inbox_message_sent",
    },
    AuditActionDefinition {
        label: "Inbox reply sent",
        scopes: GROUP_SCOPES,
        value: "inbox_reply_sent",
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
        label: "Notification preferences updated",
        scopes: USER_SCOPES,
        value: "user_notification_preferences_updated",
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
#[derive(Debug, Clone)]
pub(crate) struct AuditActionOption {
    /// User-facing label for the action.
    pub label: String,
    /// Whether the option is currently selected.
    pub selected: bool,
    /// Raw audit action value.
    pub value: String,
}

/// Detail row rendered inside an audit popover.
#[derive(Debug, Clone)]
pub(crate) struct AuditLogDetail {
    /// Human-readable detail key.
    pub key_label: String,
    /// Human-readable detail value.
    pub value: String,
}

/// Prepared audit log row for rendering.
#[derive(Debug, Clone)]
pub(crate) struct AuditLogEntry {
    /// Human-readable action label.
    pub action_label: String,
    /// Timestamp when the action was recorded.
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
        let resource_display_name =
            record.resource_name.unwrap_or_else(|| record.resource_id.to_string());
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
            created_at: record.created_at,
            details,
            details_popover_id: format!("audit-log-details-{}", record.audit_log_id),
            resource_display_name,
            resource_type_label: resource_type_label(&record.resource_type).to_string(),

            actor_username: record.actor_username,
        }
    }
}

/// Dashboard scope for an audit log screen.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
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

/// Returns whether a JSON value is a scalar.
fn is_scalar(value: &Value) -> bool {
    !matches!(value, Value::Array(_) | Value::Object(_))
}

/// Formats a JSON detail value for display.
///
/// Arrays of scalars render as comma-separated lists so filter names read
/// naturally; nested structures keep their JSON representation.
fn render_detail_value(value: &Value) -> String {
    match value {
        Value::Array(items) if items.iter().all(is_scalar) => {
            items.iter().map(render_detail_value).collect::<Vec<_>>().join(", ")
        }
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
        "admission_offer" => "Ticket offer",
        "badge" => "Badge",
        "badge_artwork" => "Badge artwork",
        "cfs_submission" => "CFS submission",
        "community" => "Community",
        "event" => "Event",
        "event_category" => "Event category",
        "event_survey" => "Event survey",
        "group" => "Group",
        "group_category" => "Group category",
        "group_sponsor" => "Group sponsor",
        "inbox_conversation" => "Inbox conversation",
        "region" => "Region",
        "session_proposal" => "Session proposal",
        "user" => "User",
        "user_badge" => "Badge award",
        _ => "Resource",
    }
}

#[cfg(test)]
mod tests {
    use std::{
        collections::BTreeSet,
        fs,
        path::{Path, PathBuf},
    };

    use serde_json::json;

    use super::*;

    /// Community audit log function source holding its action allow-list.
    const COMMUNITY_AUDIT_LOGS_SQL: &str = include_str!(
        "../../../../database/migrations/functions/dashboard-community/list_community_audit_logs.sql"
    );
    /// Audit action expressions built from a parameter, with every value they take.
    const DYNAMIC_ACTIONS: &[(&str, &[&str])] = &[
        // The event cohost transition only accepts these statuses
        (
            "'event_cohost_' || p_status",
            &[
                "event_cohost_approved",
                "event_cohost_canceled",
                "event_cohost_rejected",
            ],
        ),
    ];
    /// Group audit log function source holding its action allow-list.
    const GROUP_AUDIT_LOGS_SQL: &str = include_str!(
        "../../../../database/migrations/functions/dashboard-group/list_group_audit_logs.sql"
    );
    /// Emitted audit actions intentionally absent from every audit log page.
    const HIDDEN_ACTIONS: &[&str] = &[
        // Attendee answer history, not an organizer or account change
        "event_registration_questions_answered",
        // Operator database action without a dashboard actor
        "notification_manually_requeued",
        // Operator database action without a dashboard actor
        "user_notifications_suppressed",
    ];
    /// Listed audit actions no longer emitted but kept for historical rows.
    const LEGACY_ACTIONS: &[&str] = &[
        // Historical rows remain listed after the action stopped being emitted
        "event_attendee_invitation_accepted",
    ];
    /// User audit log function source holding its action allow-list.
    const USER_AUDIT_LOGS_SQL: &str = include_str!(
        "../../../../database/migrations/functions/dashboard-user/list_user_audit_logs.sql"
    );

    #[test]
    fn test_action_catalog_labels_and_scopes() {
        use AuditScope::{Community, Group, User};

        // Collect the actions listed by each scope
        let scopes_actions =
            [Community, Group, User].map(|scope| (scope, scope_action_values(scope)));

        // (action, label, scopes listing the action)
        let cases: [(&str, &str, &[AuditScope]); 22] = [
            (
                "admission_offer_expired",
                "Event ticket offer expired",
                &[Group],
            ),
            ("badge_added", "Badge added", &[Group]),
            ("badge_artwork_added", "Badge artwork added", &[Group]),
            ("badge_artwork_deleted", "Badge artwork deleted", &[Group]),
            ("badge_awarded", "Badge awarded", &[Group]),
            ("badge_deleted", "Badge deleted", &[Group]),
            ("badge_revoked", "Badge revoked", &[Group]),
            (
                "badge_revoked_account_deleted",
                "Badge revoked after account deletion",
                &[Group],
            ),
            (
                "badge_revoked_by_recipient",
                "Badge revoked by recipient",
                &[Group],
            ),
            ("badge_updated", "Badge updated", &[Group]),
            (
                "community_custom_notification_sent",
                "Community custom notification sent",
                &[Community],
            ),
            (
                "event_admission_offer_canceled",
                "Event ticket offer canceled",
                &[Group],
            ),
            (
                "event_admission_offer_declined",
                "Event ticket offer declined",
                &[Group, User],
            ),
            (
                "event_admission_offer_reissued",
                "Event ticket offer reissued",
                &[Group],
            ),
            ("event_survey_added", "Event survey added", &[Group]),
            ("event_survey_closed", "Event survey closed", &[Group]),
            ("event_survey_deleted", "Event survey deleted", &[Group]),
            (
                "event_survey_marked_ready",
                "Event survey marked ready",
                &[Group],
            ),
            (
                "event_survey_moved_to_draft",
                "Event survey moved to draft",
                &[Group],
            ),
            ("event_survey_reopened", "Event survey reopened", &[Group]),
            ("event_survey_updated", "Event survey updated", &[Group]),
            (
                "event_ticket_waitlist_offer_created",
                "Event waitlist ticket offer created",
                &[Group],
            ),
        ];

        // Check each action label and the scopes that list it
        for (action, label, scopes) in cases {
            assert_eq!(action_label(action), label, "{action}");
            for (scope, scope_actions) in &scopes_actions {
                assert_eq!(
                    scope_actions.contains(action),
                    scopes.contains(scope),
                    "{action} in {scope:?}"
                );
            }
        }
    }

    #[test]
    fn test_emitted_audit_actions_are_listed_or_hidden() {
        // Collect the emitted actions and the actions listed by every audit page
        let emitted = emitted_audit_actions();
        let listed: BTreeSet<String> = [
            COMMUNITY_AUDIT_LOGS_SQL,
            GROUP_AUDIT_LOGS_SQL,
            USER_AUDIT_LOGS_SQL,
        ]
        .into_iter()
        .flat_map(sql_allow_list)
        .collect();
        assert!(!emitted.is_empty(), "no emitted audit actions found");

        // Check every emitted action is listed by an audit page or hidden
        for action in &emitted {
            assert!(
                listed.contains(action) || HIDDEN_ACTIONS.contains(&action.as_str()),
                "audit action {action} is emitted but not listed: add it to a \
                 list_*_audit_logs.sql allow-list plus AUDIT_ACTION_DEFINITIONS, or to \
                 HIDDEN_ACTIONS"
            );
        }

        // Check hidden actions are emitted, unlisted and keep the fallback label
        for action in HIDDEN_ACTIONS {
            assert!(
                emitted.contains(*action),
                "hidden action {action} is not emitted"
            );
            assert!(
                !listed.contains(*action),
                "hidden action {action} is listed"
            );
            assert!(
                action_definition(action).is_none(),
                "hidden action {action} has a definition"
            );
        }

        // Check every listed action is still emitted or kept for legacy rows
        for action in &listed {
            assert!(
                emitted.contains(action) || LEGACY_ACTIONS.contains(&action.as_str()),
                "audit action {action} is listed but never emitted"
            );
        }
    }

    #[test]
    fn test_hidden_actions_are_not_scoped() {
        // Collect the actions listed by each scope
        let scopes_actions = [
            scope_action_values(AuditScope::Community),
            scope_action_values(AuditScope::Group),
            scope_action_values(AuditScope::User),
        ];

        // Check hidden actions are absent from every scope and keep the fallback label
        for action in [
            "admission_offer_canceled",
            "event_registration_questions_answered",
        ] {
            for scope_actions in &scopes_actions {
                assert!(!scope_actions.contains(action), "{action} is listed");
            }
            assert_eq!(action_label(action), "Audit action");
        }
    }

    #[test]
    fn test_humanize_key_capitalizes_words_and_cfs() {
        let cases = [
            ("single word", "name", "Name"),
            ("several words", "starts_at", "Starts At"),
            ("cfs abbreviation", "cfs_enabled", "CFS Enabled"),
            ("empty segment", "a__b", "A  B"),
        ];

        for (case, key, expected) in cases {
            assert_eq!(humanize_key(key), expected, "{case}");
        }
    }

    #[test]
    fn test_list_page_new_selects_filtered_action() {
        let filters = AuditLogFilters {
            action: Some("badge_added".to_string()),
            ..AuditLogFilters::default()
        };
        let output = AuditLogsOutput {
            logs: vec![],
            total: 0,
        };

        let page = ListPage::new(
            AuditScope::Group,
            &filters,
            output,
            pagination::NavigationLinks::default(),
        );

        let selected: Vec<&str> = page
            .action_options
            .iter()
            .filter(|option| option.selected)
            .map(|option| option.value.as_str())
            .collect();
        assert_eq!(selected, ["badge_added"]);
    }

    #[test]
    fn test_render_detail_value_formats_values() {
        let cases = [
            ("integer", json!(2), "2"),
            (
                "nested array",
                json!([{"name": "Platform"}]),
                r#"[{"name":"Platform"}]"#,
            ),
            ("null", json!(null), "-"),
            (
                "scalar array",
                json!(["Platform", "No region", 3]),
                "Platform, No region, 3",
            ),
            ("string", json!("All"), "All"),
        ];
        for (case, value, expected) in cases {
            assert_eq!(render_detail_value(&value), expected, "{case}");
        }
    }

    #[test]
    fn test_resource_type_label_names_resource_types() {
        for (resource_type, label) in [
            ("admission_offer", "Ticket offer"),
            ("badge", "Badge"),
            ("badge_artwork", "Badge artwork"),
            ("event_survey", "Event survey"),
            ("user_badge", "Badge award"),
        ] {
            assert_eq!(resource_type_label(resource_type), label, "{resource_type}");
        }
    }

    #[test]
    fn test_scope_action_catalogs_match_sql_allow_lists() {
        assert_eq!(
            scope_action_values(AuditScope::Community),
            sql_allow_list(COMMUNITY_AUDIT_LOGS_SQL)
        );
        assert_eq!(
            scope_action_values(AuditScope::Group),
            sql_allow_list(GROUP_AUDIT_LOGS_SQL)
        );
        assert_eq!(
            scope_action_values(AuditScope::User),
            sql_allow_list(USER_AUDIT_LOGS_SQL)
        );
    }

    // Helpers.

    /// Returns the first value expression of each `insert into audit_log` statement.
    fn audit_log_insert_actions(file: &str, source: &str) -> Vec<String> {
        word_positions(source, "audit_log")
            .filter(|position| {
                // Keep table references that follow insert into, schema-qualified or not
                let before = strip_schema_qualifier(&source[..*position]);
                strip_keyword_suffix(before, "into")
                    .and_then(|before| strip_keyword_suffix(before, "insert"))
                    .is_some()
            })
            .map(|position| {
                // Check the column list starts with the action column
                let rest = source[position + "audit_log".len()..].trim_start();
                let rest = rest
                    .strip_prefix('(')
                    .unwrap_or_else(|| panic!("audit_log insert without a column list in {file}"));
                let columns_end = rest
                    .find(')')
                    .unwrap_or_else(|| panic!("audit_log column list end in {file}"));
                assert_eq!(
                    rest[..columns_end].split(',').next().map(str::trim),
                    Some("action"),
                    "audit_log insert does not start with the action column in {file}"
                );

                // Read the first value of a values list or a select
                let values = &rest[columns_end + 1..];
                let values = strip_keyword_prefix(values, "values")
                    .and_then(|values| values.trim_start().strip_prefix('('))
                    .or_else(|| strip_keyword_prefix(values, "select"))
                    .unwrap_or_else(|| {
                        panic!("audit_log insert without values or select in {file}")
                    });
                first_argument(values).to_string()
            })
            .collect()
    }

    /// Returns the first argument of every call to `function`, skipping its definition.
    fn call_first_arguments(file: &str, source: &str, function: &str) -> Vec<String> {
        word_positions(source, function)
            .filter(|position| {
                // Skip the function definition, schema-qualified or not
                let before = strip_schema_qualifier(&source[..*position]);
                strip_keyword_suffix(before, "function").is_none()
            })
            .map(|position| {
                // Fail on references that are not calls
                let arguments = source[position + function.len()..].trim_start();
                let arguments = arguments
                    .strip_prefix('(')
                    .unwrap_or_else(|| panic!("unrecognized reference to {function} in {file}"));

                // Read the first argument, removing a named action parameter
                let argument = first_argument(arguments);
                argument
                    .strip_prefix("p_action")
                    .map(str::trim_start)
                    .and_then(|rest| rest.strip_prefix("=>").or_else(|| rest.strip_prefix(":=")))
                    .unwrap_or(argument)
                    .trim()
                    .to_string()
            })
            .collect()
    }

    /// Returns the unqualified name of the function defined in a SQL source.
    fn defined_function_name(source: &str) -> Option<&str> {
        let start =
            source.find("create or replace function ")? + "create or replace function ".len();
        let end = start + source[start..].find('(')?;
        let name = source[start..end].trim();
        Some(name.rsplit('.').next().unwrap_or(name))
    }

    /// Collects every audit action emitted by the database function sources.
    fn emitted_audit_actions() -> BTreeSet<String> {
        // Load the function sources without comments or template directives
        let functions_dir =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../database/migrations/functions");
        let mut paths = Vec::new();
        walk_sql_files(&functions_dir, &mut paths);
        let sources: Vec<(String, String)> = paths
            .iter()
            .map(|path| {
                let file = path
                    .strip_prefix(&functions_dir)
                    .unwrap_or(path)
                    .display()
                    .to_string();
                let source = fs::read_to_string(path).expect("read SQL function source");
                let source = strip_sql_comments(&source)
                    .lines()
                    .filter(|line| !line.trim_start().starts_with("{{"))
                    .collect::<Vec<_>>()
                    .join("\n");
                (file, source)
            })
            .collect();

        // Find the audit helpers that forward an action parameter to an emitter or
        // audit_log, starting from the base helper's raw insert (the base helper is
        // discovered, not named, so Rust never references internal SQL functions)
        let mut emitters = BTreeSet::<String>::new();
        loop {
            let mut helpers = BTreeSet::new();
            for (file, source) in &sources {
                let mut expressions = audit_log_insert_actions(file, source);
                for emitter in &emitters {
                    expressions.extend(call_first_arguments(file, source, emitter));
                }
                if expressions.iter().any(|expression| is_parameter(expression)) {
                    let name = defined_function_name(source).unwrap_or_else(|| {
                        panic!("audit action parameter outside a function in {file}")
                    });
                    helpers.insert(name.to_string());
                }
            }
            if helpers.is_subset(&emitters) {
                break;
            }
            emitters.extend(helpers);
        }

        // Resolve the action expressions passed to every emitter and audit_log insert
        let mut actions = BTreeSet::new();
        for (file, source) in &sources {
            let mut expressions = audit_log_insert_actions(file, source);
            for emitter in &emitters {
                expressions.extend(call_first_arguments(file, source, emitter));
            }
            for expression in expressions.iter().filter(|expression| !is_parameter(expression)) {
                let resolved = resolve_action_expression(expression, source).unwrap_or_else(|| {
                    panic!("unresolved audit action expression in {file}: {expression}")
                });
                actions.extend(resolved);
            }
        }
        actions
    }

    /// Returns the first top-level argument of an argument list, trimmed.
    fn first_argument(arguments: &str) -> &str {
        let mut depth = 0_usize;
        let mut in_literal = false;
        for (position, c) in arguments.char_indices() {
            match c {
                '\'' => in_literal = !in_literal,
                '(' if !in_literal => depth += 1,
                ')' | ',' if !in_literal && depth == 0 => {
                    return arguments[..position].trim();
                }
                ')' if !in_literal => depth -= 1,
                _ => {}
            }
        }
        arguments.trim()
    }

    /// Reports whether a character can be part of a SQL identifier.
    fn is_identifier_char(c: char) -> bool {
        c.is_ascii_alphanumeric() || c == '_'
    }

    /// Reports whether an expression is a bare function parameter.
    fn is_parameter(expression: &str) -> bool {
        expression.starts_with("p_")
            && expression.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
    }

    /// Resolves an audit action expression to the literal actions it can produce.
    fn resolve_action_expression(expression: &str, source: &str) -> Option<Vec<String>> {
        // Map parameter-built expressions to their known values
        let normalized = expression.split_whitespace().collect::<Vec<_>>().join(" ");
        if let Some((_, values)) =
            DYNAMIC_ACTIONS.iter().find(|(dynamic, _)| *dynamic == normalized)
        {
            return Some(values.iter().map(ToString::to_string).collect());
        }

        // Accept a single literal
        if let Some(action) = sql_literal(expression) {
            return Some(vec![action]);
        }

        // Collect the then and else literals of a case expression
        let tokens = sql_tokens(expression);
        if tokens.first() == Some(&"case") && tokens.last() == Some(&"end") {
            return tokens
                .windows(2)
                .filter(|pair| pair[0] == "then" || pair[0] == "else")
                .map(|pair| sql_literal(pair[1]))
                .collect();
        }

        // Collect the literals assigned to a local variable in the same source
        if expression.starts_with("v_") {
            let assignment = format!("{expression} :=");
            let actions: Option<Vec<String>> = source
                .match_indices(&assignment)
                .map(|(position, _)| {
                    sql_tokens(&source[position + assignment.len()..])
                        .first()
                        .and_then(|token| sql_literal(token))
                })
                .collect();
            return actions.filter(|actions| !actions.is_empty());
        }
        None
    }

    /// Returns the action values listed by an audit scope.
    fn scope_action_values(scope: AuditScope) -> BTreeSet<String> {
        scope
            .action_options()
            .into_iter()
            .map(|option| option.value)
            .collect()
    }

    /// Extracts the quoted action literals of a SQL `array[...]::text[]` allow-list.
    fn sql_allow_list(source: &str) -> BTreeSet<String> {
        // Locate the allow-list array in the function source
        let start = source.find("array[").expect("allow-list start") + "array[".len();
        let end = start + source[start..].find("]::text[]").expect("allow-list end");

        // Collect the literals found between single quotes
        source[start..end]
            .split('\'')
            .skip(1)
            .step_by(2)
            .map(ToString::to_string)
            .collect()
    }

    /// Returns the value of an expression made of one quoted SQL literal.
    fn sql_literal(expression: &str) -> Option<String> {
        let value = expression.strip_prefix('\'')?.strip_suffix('\'')?;
        (!value.contains('\'')).then(|| value.to_string())
    }

    /// Splits a SQL expression into whitespace-separated words and quoted literals.
    fn sql_tokens(expression: &str) -> Vec<&str> {
        let mut tokens = Vec::new();
        let mut rest = expression.trim_start();
        while !rest.is_empty() {
            let len = if let Some(literal) = rest.strip_prefix('\'') {
                literal.find('\'').map_or(rest.len(), |end| end + 2)
            } else {
                rest.find(|c: char| c.is_whitespace() || c == '\'')
                    .unwrap_or(rest.len())
            };
            tokens.push(&rest[..len]);
            rest = rest[len..].trim_start();
        }
        tokens
    }

    /// Returns the text after a leading whole-word keyword, ignoring case and whitespace.
    fn strip_keyword_prefix<'a>(text: &'a str, keyword: &str) -> Option<&'a str> {
        let text = text.trim_start();
        let rest = text.get(keyword.len()..)?;
        let matches = text[..keyword.len()].eq_ignore_ascii_case(keyword)
            && !rest.chars().next().is_some_and(is_identifier_char);
        matches.then_some(rest)
    }

    /// Returns the text before a trailing whole-word keyword, ignoring case and whitespace.
    fn strip_keyword_suffix<'a>(text: &'a str, keyword: &str) -> Option<&'a str> {
        let text = text.trim_end();
        let start = text.len().checked_sub(keyword.len())?;
        let before = text.get(..start)?;
        let matches = text[start..].eq_ignore_ascii_case(keyword)
            && !before.chars().next_back().is_some_and(is_identifier_char);
        matches.then_some(before)
    }

    /// Removes a trailing `schema.` qualifier from the text before an identifier.
    fn strip_schema_qualifier(before: &str) -> &str {
        match before.strip_suffix('.') {
            Some(qualified) => qualified.trim_end_matches(is_identifier_char),
            None => before,
        }
    }

    /// Removes `--` line comments outside SQL literals.
    fn strip_sql_comments(source: &str) -> String {
        source
            .lines()
            .map(|line| {
                let mut in_literal = false;
                let mut previous = ' ';
                for (position, c) in line.char_indices() {
                    if c == '\'' {
                        in_literal = !in_literal;
                    } else if c == '-' && previous == '-' && !in_literal {
                        return &line[..position - 1];
                    }
                    previous = c;
                }
                line
            })
            .collect::<Vec<_>>()
            .join("\n")
    }

    /// Recursively collects `.sql` files under `dir`.
    fn walk_sql_files(dir: &Path, files: &mut Vec<PathBuf>) {
        let entries = fs::read_dir(dir).expect("read SQL functions directory");
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                walk_sql_files(&path, files);
            } else if path.extension().is_some_and(|ext| ext == "sql") {
                files.push(path);
            }
        }
    }

    /// Returns the positions of `word` not adjacent to other identifier characters.
    fn word_positions<'a>(source: &'a str, word: &'a str) -> impl Iterator<Item = usize> + 'a {
        source.match_indices(word).filter_map(move |(position, _)| {
            let before = source[..position].chars().next_back();
            let after = source[position + word.len()..].chars().next();
            let whole_word =
                !before.is_some_and(is_identifier_char) && !after.is_some_and(is_identifier_char);
            whole_word.then_some(position)
        })
    }
}
