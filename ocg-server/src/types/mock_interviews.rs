//! Mock interview domain types.

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
        optional_trimmed_string, trimmed_non_empty_opt,
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

/// Match/scheduling input.
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
    /// Total matching requests.
    pub total: usize,
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
    /// Creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
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
    valid_option(value.as_ref(), PRACTICE_ROLE_OPTIONS, "invalid practice role")
}

fn valid_interview_type(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    valid_option(value.as_ref(), INTERVIEW_TYPE_OPTIONS, "invalid interview type")
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
