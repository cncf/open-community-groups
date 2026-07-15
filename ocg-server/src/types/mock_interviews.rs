//! Mock interview domain types.

#![allow(clippy::ref_option, clippy::trivially_copy_pass_by_ref)]

use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::dashboard,
    types::pagination::{Pagination, ToRawQuery},
    validation::{
        MAX_LEN_DESCRIPTION, MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_M, MAX_PAGINATION_LIMIT,
        optional_trimmed_string, trimmed_non_empty, trimmed_non_empty_opt,
    },
};

/// Static poll-informed option.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub(crate) struct MockInterviewOption {
    /// Stored slug.
    pub value: &'static str,
    /// Display label.
    pub label: &'static str,
    /// Source poll vote count.
    pub votes: i32,
}

impl MockInterviewOption {
    /// Returns a correctly pluralized vote label.
    pub(crate) fn vote_label(&self) -> String {
        if self.votes == 1 {
            "1 vote".to_string()
        } else {
            format!("{} votes", self.votes)
        }
    }

    /// Returns a bounded display percentage against the strongest poll option.
    pub(crate) fn demand_percent(&self) -> i32 {
        let percent = (self.votes.max(0) * 100) / 49;
        percent.clamp(8, 100)
    }
}

/// Practice role options from the poll.
pub(crate) const PRACTICE_ROLE_OPTIONS: &[MockInterviewOption] = &[
    MockInterviewOption {
        value: "interviewee",
        label: "Interviewee",
        votes: 41,
    },
    MockInterviewOption {
        value: "both",
        label: "Both",
        votes: 40,
    },
    MockInterviewOption {
        value: "interviewer",
        label: "Interviewer",
        votes: 5,
    },
    MockInterviewOption {
        value: "not_interested",
        label: "Not interested",
        votes: 1,
    },
];

/// Interview type options from the poll.
pub(crate) const INTERVIEW_TYPE_OPTIONS: &[MockInterviewOption] = &[
    MockInterviewOption {
        value: "software_engineering",
        label: "Software Engineering",
        votes: 49,
    },
    MockInterviewOption {
        value: "ai_ml",
        label: "AI/ML",
        votes: 36,
    },
    MockInterviewOption {
        value: "startup_cofounder",
        label: "Startup / Co-Founder",
        votes: 31,
    },
    MockInterviewOption {
        value: "product_management",
        label: "Product Management",
        votes: 17,
    },
    MockInterviewOption {
        value: "devops_cloud",
        label: "DevOps / Cloud",
        votes: 15,
    },
    MockInterviewOption {
        value: "security",
        label: "Security",
        votes: 7,
    },
    MockInterviewOption {
        value: "behavioral_hr",
        label: "Behavioral (HR)",
        votes: 3,
    },
    MockInterviewOption {
        value: "other",
        label: "Other",
        votes: 9,
    },
];

/// Target company options from the poll.
pub(crate) const TARGET_COMPANY_OPTIONS: &[MockInterviewOption] = &[
    MockInterviewOption {
        value: "remote_global",
        label: "Remote/global companies",
        votes: 57,
    },
    MockInterviewOption {
        value: "ai_labs_faang",
        label: "AI Labs / FAANG",
        votes: 26,
    },
    MockInterviewOption {
        value: "enterprise",
        label: "Enterprise",
        votes: 23,
    },
    MockInterviewOption {
        value: "ai_startup",
        label: "AI startup",
        votes: 19,
    },
    MockInterviewOption {
        value: "doesnt_matter",
        label: "Doesn't matter",
        votes: 9,
    },
];

/// Seniority options from the poll.
pub(crate) const SENIORITY_OPTIONS: &[MockInterviewOption] = &[
    MockInterviewOption {
        value: "senior",
        label: "Senior, 3-7y exp",
        votes: 37,
    },
    MockInterviewOption {
        value: "staff_plus",
        label: "Staff and above, 7y+",
        votes: 30,
    },
    MockInterviewOption {
        value: "mid",
        label: "Mid, 1-3y exp",
        votes: 28,
    },
    MockInterviewOption {
        value: "graduate_junior",
        label: "Graduate / junior, no exp",
        votes: 27,
    },
];

/// Location options from the poll.
pub(crate) const LOCATION_OPTIONS: &[MockInterviewOption] = &[
    MockInterviewOption {
        value: "aze",
        label: "AZE",
        votes: 121,
    },
    MockInterviewOption {
        value: "usa_canada",
        label: "USA / Canada",
        votes: 33,
    },
    MockInterviewOption {
        value: "eu",
        label: "EU",
        votes: 17,
    },
    MockInterviewOption {
        value: "other",
        label: "Other",
        votes: 2,
    },
    MockInterviewOption {
        value: "asia",
        label: "Asia",
        votes: 0,
    },
];

/// Dashboard filters.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct MockInterviewFilters {
    /// Status filter.
    #[garde(length(max = MAX_LEN_M), custom(valid_request_status_opt))]
    pub status: Option<String>,
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(MockInterviewFilters, limit, offset);

impl Default for MockInterviewFilters {
    fn default() -> Self {
        Self {
            status: None,
            limit: dashboard::default_limit(),
            offset: dashboard::default_offset(),
        }
    }
}

/// Mock interview request input.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct MockInterviewRequestInput {
    /// Desired practice role.
    #[garde(custom(valid_practice_role), length(max = MAX_LEN_M))]
    pub practice_role: String,
    /// Interview type.
    #[garde(custom(valid_interview_type), length(max = MAX_LEN_M))]
    pub interview_type: String,
    /// Target company type.
    #[garde(custom(valid_target_company), length(max = MAX_LEN_M))]
    pub target_company: String,
    /// Seniority.
    #[garde(custom(valid_seniority), length(max = MAX_LEN_M))]
    pub seniority: String,
    /// Location.
    #[garde(custom(valid_location), length(max = MAX_LEN_M))]
    pub location: String,
    /// Availability notes.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub availability: Option<String>,
    /// Freeform notes.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION))]
    pub notes: Option<String>,
}

/// Match input from the organizer queue.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct MockInterviewMatchInput {
    /// Optional interviewer user ID.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(valid_uuid_opt), length(max = MAX_LEN_M))]
    pub interviewer_user_id: Option<String>,
    /// Optional interviewee user ID.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(valid_uuid_opt), length(max = MAX_LEN_M))]
    pub interviewee_user_id: Option<String>,
    /// Scheduled time as RFC3339 or database-compatible timestamp string.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub scheduled_at: Option<String>,
    /// Meeting URL.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(url, length(max = MAX_LEN_M), custom(trimmed_non_empty_opt))]
    pub meeting_url: Option<String>,
    /// Match status.
    #[garde(custom(valid_match_status), length(max = MAX_LEN_M))]
    pub status: String,
    /// Internal organizer notes.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION))]
    pub internal_notes: Option<String>,
}

/// Feedback input.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct MockInterviewFeedbackInput {
    /// Match status.
    #[garde(custom(valid_match_status), length(max = MAX_LEN_M))]
    pub status: String,
    /// Interviewer feedback.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION))]
    pub interviewer_feedback: Option<String>,
    /// Interviewee feedback.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION))]
    pub interviewee_feedback: Option<String>,
    /// Interviewee rating for the interviewer.
    #[serde(default)]
    #[garde(range(min = 1, max = 5))]
    pub interviewer_rating: Option<i32>,
}

/// Participant feedback input.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct MockInterviewParticipantFeedbackInput {
    /// Feedback for the current user's assigned role.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION))]
    pub feedback: Option<String>,
    /// Interviewee rating for the interviewer.
    #[serde(default)]
    #[garde(range(min = 1, max = 5))]
    pub interviewer_rating: Option<i32>,
}

/// Participant scheduling input.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct MockInterviewParticipantScheduleInput {
    /// Scheduled time as RFC3339 or database-compatible timestamp string.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub scheduled_at: String,
    /// Meeting URL.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(url, length(max = MAX_LEN_M), custom(trimmed_non_empty_opt))]
    pub meeting_url: Option<String>,
}

/// Dashboard output.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct MockInterviewDashboard {
    /// Requests.
    #[serde(default)]
    pub requests: Vec<MockInterviewRequest>,
    /// Matches.
    #[serde(default)]
    pub matches: Vec<MockInterviewMatch>,
    /// Stats.
    #[serde(default)]
    pub stats: Vec<MockInterviewStat>,
    /// Aggregate metrics for the mock interview dashboard.
    #[serde(default)]
    pub metrics: MockInterviewMetrics,
    /// Total matching requests.
    pub total: usize,
}

/// Aggregate mock interview dashboard metrics.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct MockInterviewMetrics {
    /// Total submitted requests.
    pub total_requests: usize,
    /// Requests still waiting to be matched.
    pub pending_requests: usize,
    /// Requests currently matched or scheduled.
    pub active_requests: usize,
    /// Total created matches.
    pub total_matches: usize,
    /// Matches currently active.
    pub active_matches: usize,
    /// Completed matches.
    pub completed_matches: usize,
    /// Canceled matches.
    pub canceled_matches: usize,
    /// Matches with at least one feedback or rating field.
    pub feedback_count: usize,
    /// Average interviewee rating for interviewers.
    pub average_interviewer_rating: Option<f64>,
}

impl MockInterviewMetrics {
    /// Formats average interviewer rating for display.
    pub(crate) fn average_interviewer_rating_display(&self) -> String {
        self.average_interviewer_rating
            .map_or_else(|| "N/A".to_string(), |rating| format!("{rating:.1}"))
    }
}

/// Mock interview request.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct MockInterviewRequest {
    /// Request ID.
    pub mock_interview_request_id: Uuid,
    /// Requesting user ID.
    pub requester_user_id: Uuid,
    /// Requester username.
    pub requester_username: String,
    /// Requester display name.
    pub requester_name: Option<String>,
    /// Requester email.
    pub requester_email: String,
    /// Desired role.
    pub practice_role: String,
    /// Interview type.
    pub interview_type: String,
    /// Target company.
    pub target_company: String,
    /// Seniority.
    pub seniority: String,
    /// Location.
    pub location: String,
    /// Availability.
    pub availability: Option<String>,
    /// Notes.
    pub notes: Option<String>,
    /// Status.
    pub status: String,
    /// Creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Updated time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub updated_at: Option<DateTime<Utc>>,
}

impl MockInterviewRequest {
    /// Returns display name fallback.
    pub(crate) fn display_name(&self) -> &str {
        self.requester_name
            .as_deref()
            .unwrap_or(self.requester_username.as_str())
    }

    /// Returns the requester in the shape expected by user search selectors.
    pub(crate) fn requester_selection(&self) -> Vec<MockInterviewUserSelection> {
        vec![MockInterviewUserSelection {
            user_id: self.requester_user_id,
            username: self.requester_username.clone(),
            name: Some(self.display_name().to_string()),
        }]
    }

    /// Returns whether the request is still waiting for a match.
    pub(crate) fn is_waiting(&self) -> bool {
        self.status == "requested"
    }

    /// Returns whether the request reached a terminal state.
    pub(crate) fn is_closed(&self) -> bool {
        matches!(self.status.as_str(), "completed" | "canceled")
    }
}

/// User selection payload for dashboard search components.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct MockInterviewUserSelection {
    /// User ID.
    pub user_id: Uuid,
    /// Username.
    pub username: String,
    /// Display name.
    pub name: Option<String>,
}

/// Mock interview match.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct MockInterviewMatch {
    /// Match ID.
    pub mock_interview_match_id: Uuid,
    /// Request ID.
    pub mock_interview_request_id: Uuid,
    /// Interviewer user ID.
    pub interviewer_user_id: Option<Uuid>,
    /// Interviewer label.
    pub interviewer_label: Option<String>,
    /// Interviewee user ID.
    pub interviewee_user_id: Option<Uuid>,
    /// Interviewee label.
    pub interviewee_label: Option<String>,
    /// Scheduled time.
    pub scheduled_at: Option<String>,
    /// Meeting URL.
    pub meeting_url: Option<String>,
    /// Status.
    pub status: String,
    /// Internal notes.
    pub internal_notes: Option<String>,
    /// Interviewer feedback.
    pub interviewer_feedback: Option<String>,
    /// Interviewee feedback.
    pub interviewee_feedback: Option<String>,
    /// Interviewee rating for the interviewer.
    pub interviewer_rating: Option<i32>,
    /// Creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
}

impl MockInterviewMatch {
    /// Returns whether the interviewer rating equals the given value.
    pub(crate) fn interviewer_rating_is(&self, value: i32) -> bool {
        self.interviewer_rating == Some(value)
    }
}

/// Participant context used when notifying a new match.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct MockInterviewMatchNotificationContext {
    /// Match ID.
    pub mock_interview_match_id: Uuid,
    /// Interviewer user ID.
    pub interviewer_user_id: Option<Uuid>,
    /// Interviewer username.
    pub interviewer_username: Option<String>,
    /// Interviewer display name.
    pub interviewer_name: Option<String>,
    /// Interviewee user ID.
    pub interviewee_user_id: Option<Uuid>,
    /// Interviewee username.
    pub interviewee_username: Option<String>,
    /// Interviewee display name.
    pub interviewee_name: Option<String>,
    /// Interview type.
    pub interview_type: String,
    /// Practice role.
    pub practice_role: String,
}

impl MockInterviewMatchNotificationContext {
    /// Returns the interviewer display label.
    pub(crate) fn interviewer_label(&self) -> String {
        self.interviewer_name
            .as_deref()
            .or(self.interviewer_username.as_deref())
            .unwrap_or("Interviewer")
            .to_string()
    }

    /// Returns the interviewee display label.
    pub(crate) fn interviewee_label(&self) -> String {
        self.interviewee_name
            .as_deref()
            .or(self.interviewee_username.as_deref())
            .unwrap_or("Interviewee")
            .to_string()
    }
}

/// Mock interview match for the current user's dashboard.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserMockInterviewMatch {
    /// Match details.
    #[serde(flatten)]
    pub match_: MockInterviewMatch,
    /// Current user's role in the match.
    pub role: String,
}

impl UserMockInterviewMatch {
    /// Returns a human-readable role label.
    pub(crate) fn role_label(&self) -> &'static str {
        match self.role.as_str() {
            "interviewer" => "Interviewer",
            "interviewee" => "Interviewee",
            _ => "Participant",
        }
    }

    /// Returns the feedback value editable by the current user.
    pub(crate) fn current_user_feedback(&self) -> Option<&str> {
        match self.role.as_str() {
            "interviewer" => self.match_.interviewer_feedback.as_deref(),
            "interviewee" => self.match_.interviewee_feedback.as_deref(),
            _ => None,
        }
    }

    /// Returns the interviewer rating editable by the interviewee.
    pub(crate) fn current_user_interviewer_rating(&self) -> Option<i32> {
        if self.role == "interviewee" {
            self.match_.interviewer_rating
        } else {
            None
        }
    }

    /// Returns whether the current interviewee rating equals the given value.
    pub(crate) fn current_user_interviewer_rating_is(&self, value: i32) -> bool {
        self.current_user_interviewer_rating() == Some(value)
    }

    /// Returns whether this match still needs time or meeting details.
    pub(crate) fn needs_schedule(&self) -> bool {
        matches!(self.match_.status.as_str(), "matched" | "scheduled")
            && (self.match_.scheduled_at.is_none() || self.match_.meeting_url.is_none())
    }

    /// Returns whether the current user has submitted role-specific feedback.
    pub(crate) fn current_user_feedback_submitted(&self) -> bool {
        match self.role.as_str() {
            "interviewer" => self.match_.interviewer_feedback.is_some(),
            "interviewee" => {
                self.match_.interviewee_feedback.is_some()
                    || self.match_.interviewer_rating.is_some()
            }
            _ => false,
        }
    }
}

/// Dashboard aggregate stat.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct MockInterviewStat {
    /// Dimension name.
    pub dimension: String,
    /// Stored slug.
    pub value: String,
    /// Number of requests.
    pub count: i64,
}

/// Returns a label for a stored mock interview option.
pub(crate) fn option_label(value: &str) -> &str {
    PRACTICE_ROLE_OPTIONS
        .iter()
        .chain(INTERVIEW_TYPE_OPTIONS)
        .chain(TARGET_COMPANY_OPTIONS)
        .chain(SENIORITY_OPTIONS)
        .chain(LOCATION_OPTIONS)
        .find(|option| option.value == value)
        .map_or(value, |option| option.label)
}

fn valid_practice_role(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    valid_option(
        value.as_ref(),
        PRACTICE_ROLE_OPTIONS,
        "invalid practice role",
    )
}

fn valid_interview_type(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    valid_option(
        value.as_ref(),
        INTERVIEW_TYPE_OPTIONS,
        "invalid interview type",
    )
}

fn valid_target_company(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    valid_option(
        value.as_ref(),
        TARGET_COMPANY_OPTIONS,
        "invalid target company",
    )
}

fn valid_seniority(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    valid_option(value.as_ref(), SENIORITY_OPTIONS, "invalid seniority")
}

fn valid_location(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    valid_option(value.as_ref(), LOCATION_OPTIONS, "invalid location")
}

fn valid_request_status_opt(value: &Option<String>, _ctx: &()) -> garde::Result {
    let Some(value) = value.as_deref() else {
        return Ok(());
    };
    valid_request_status(&value, &())
}

fn valid_request_status(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    match value.as_ref() {
        "requested" | "matched" | "scheduled" | "completed" | "canceled" => Ok(()),
        _ => Err(garde::Error::new("invalid request status")),
    }
}

fn valid_match_status(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    match value.as_ref() {
        "matched" | "scheduled" | "completed" | "canceled" => Ok(()),
        _ => Err(garde::Error::new("invalid match status")),
    }
}

fn valid_uuid_opt(value: &Option<String>, _ctx: &()) -> garde::Result {
    let Some(value) = value.as_deref() else {
        return Ok(());
    };
    Uuid::parse_str(value)
        .map(|_| ())
        .map_err(|_| garde::Error::new("invalid user id"))
}

fn valid_option(
    value: &str,
    options: &[MockInterviewOption],
    message: &'static str,
) -> garde::Result {
    if options.iter().any(|option| option.value == value) {
        Ok(())
    } else {
        Err(garde::Error::new(message))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_poll_taxonomy() {
        assert!(valid_practice_role(&"interviewee", &()).is_ok());
        assert!(valid_interview_type(&"software_engineering", &()).is_ok());
        assert!(valid_target_company(&"remote_global", &()).is_ok());
        assert!(valid_seniority(&"staff_plus", &()).is_ok());
        assert!(valid_location(&"aze", &()).is_ok());
        assert!(valid_interview_type(&"sales", &()).is_err());
    }

    #[test]
    fn validates_statuses() {
        assert!(valid_request_status(&"requested", &()).is_ok());
        assert!(valid_request_status(&"scheduled", &()).is_ok());
        assert!(valid_match_status(&"matched", &()).is_ok());
        assert!(valid_match_status(&"requested", &()).is_err());
    }

    #[test]
    fn labels_options() {
        assert_eq!(option_label("ai_ml"), "AI/ML");
        assert_eq!(option_label("unknown"), "unknown");
    }
}
