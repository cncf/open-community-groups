//! Templates and types for group accelerator management.

use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::validation::{
    MAX_LEN_DATE, MAX_LEN_DESCRIPTION, MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_ENTITY_NAME, MAX_LEN_L,
    MAX_LEN_M, optional_trimmed_string, trimmed_non_empty, trimmed_non_empty_opt,
};

/// Group dashboard accelerator management page.
#[derive(Debug, Clone, askama::Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/accelerator.html")]
pub(crate) struct Page {
    /// Whether the current user can manage accelerator operations.
    pub can_manage_accelerator: bool,
    /// Accelerator programs owned by the selected group.
    pub programs: Vec<AcceleratorProgram>,
    /// Cohorts for all listed programs.
    pub cohorts: Vec<AcceleratorCohort>,
    /// Applications for all listed cohorts.
    pub applications: Vec<AcceleratorApplication>,
    /// Cohort members for all listed cohorts.
    pub members: Vec<AcceleratorMember>,
    /// Weekly curriculum entries for all listed cohorts.
    pub weeks: Vec<AcceleratorWeek>,
    /// Submitted weekly updates for all listed weeks.
    pub weekly_updates: Vec<AcceleratorWeeklyUpdate>,
}

/// Full accelerator dashboard payload.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct AcceleratorDashboard {
    /// Accelerator programs.
    #[serde(default)]
    pub programs: Vec<AcceleratorProgram>,
    /// Cohorts.
    #[serde(default)]
    pub cohorts: Vec<AcceleratorCohort>,
    /// Applications.
    #[serde(default)]
    pub applications: Vec<AcceleratorApplication>,
    /// Members.
    #[serde(default)]
    pub members: Vec<AcceleratorMember>,
    /// Weeks.
    #[serde(default)]
    pub weeks: Vec<AcceleratorWeek>,
    /// Weekly updates.
    #[serde(default)]
    pub weekly_updates: Vec<AcceleratorWeeklyUpdate>,
}

/// Accelerator program form.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct AcceleratorProgramInput {
    /// Program name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub name: String,
    /// Short program summary.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub summary: String,
    /// Full program description.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION))]
    pub description: Option<String>,
    /// External or public application URL.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(url, length(max = MAX_LEN_L), custom(trimmed_non_empty_opt))]
    pub application_url: Option<String>,
    /// Curriculum URL.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(url, length(max = MAX_LEN_L), custom(trimmed_non_empty_opt))]
    pub curriculum_url: Option<String>,
    /// Whether the program is active.
    #[serde(default = "default_true")]
    #[garde(skip)]
    pub active: bool,
}

/// Cohort form.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct AcceleratorCohortInput {
    /// Parent program ID.
    #[garde(skip)]
    pub group_accelerator_program_id: Uuid,
    /// Cohort name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub name: String,
    /// Cohort status.
    #[garde(custom(valid_cohort_status), length(max = MAX_LEN_M))]
    pub status: String,
    /// Start date.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(valid_date_opt), length(max = MAX_LEN_DATE))]
    pub starts_on: Option<String>,
    /// End date.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(valid_date_opt), length(max = MAX_LEN_DATE))]
    pub ends_on: Option<String>,
    /// Application deadline.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(valid_date_opt), length(max = MAX_LEN_DATE))]
    pub application_deadline: Option<String>,
    /// Capacity.
    #[garde(range(min = 1))]
    pub capacity: Option<i32>,
}

/// Public application form.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct AcceleratorApplicationInput {
    /// Applicant name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub applicant_name: String,
    /// Applicant email.
    #[garde(email, length(max = MAX_LEN_M))]
    pub applicant_email: String,
    /// Project name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub project_name: String,
    /// Project URL.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(url, length(max = MAX_LEN_L), custom(trimmed_non_empty_opt))]
    pub project_url: Option<String>,
    /// Application pitch.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION))]
    pub pitch: String,
    /// Applicant goals.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION))]
    pub goals: Option<String>,
}

/// Application review form.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct AcceleratorApplicationReviewInput {
    /// Review status.
    #[garde(custom(valid_application_status), length(max = MAX_LEN_M))]
    pub status: String,
    /// Reviewer notes.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION))]
    pub reviewer_notes: Option<String>,
}

/// Cohort week form.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct AcceleratorWeekInput {
    /// Parent cohort ID.
    #[garde(skip)]
    pub group_accelerator_cohort_id: Uuid,
    /// Week number.
    #[garde(range(min = 1))]
    pub week_number: i32,
    /// Week title.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub title: String,
    /// Week goals.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION))]
    pub goals: Option<String>,
    /// Resources URL.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(url, length(max = MAX_LEN_L), custom(trimmed_non_empty_opt))]
    pub resources_url: Option<String>,
    /// Suggested deliverable.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub deliverable: Option<String>,
    /// Start date.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(valid_date_opt), length(max = MAX_LEN_DATE))]
    pub starts_on: Option<String>,
    /// Due date.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(valid_date_opt), length(max = MAX_LEN_DATE))]
    pub due_on: Option<String>,
}

/// Member weekly update form.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct AcceleratorWeeklyUpdateInput {
    /// Cohort member ID.
    #[garde(skip)]
    pub group_accelerator_member_id: Uuid,
    /// Shipped work.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION))]
    pub shipped: String,
    /// Metrics.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub metrics: Option<String>,
    /// Blockers.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub blockers: Option<String>,
    /// Asks.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub asks: Option<String>,
    /// Links.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub links: Option<String>,
}

/// Weekly update review form.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct AcceleratorWeeklyUpdateReviewInput {
    /// Review status.
    #[garde(custom(valid_weekly_update_status), length(max = MAX_LEN_M))]
    pub status: String,
    /// Reviewer notes.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION))]
    pub reviewer_notes: Option<String>,
}

/// Accelerator program.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AcceleratorProgram {
    /// Program ID.
    pub group_accelerator_program_id: Uuid,
    /// Group ID.
    pub group_id: Uuid,
    /// Program name.
    pub name: String,
    /// Summary.
    pub summary: String,
    /// Description.
    pub description: Option<String>,
    /// Application URL.
    pub application_url: Option<String>,
    /// Curriculum URL.
    pub curriculum_url: Option<String>,
    /// Active flag.
    pub active: bool,
    /// Creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Last update time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub updated_at: Option<DateTime<Utc>>,
}

/// Accelerator cohort.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AcceleratorCohort {
    /// Cohort ID.
    pub group_accelerator_cohort_id: Uuid,
    /// Program ID.
    pub group_accelerator_program_id: Uuid,
    /// Cohort name.
    pub name: String,
    /// Status.
    pub status: String,
    /// Start date.
    pub starts_on: Option<String>,
    /// End date.
    pub ends_on: Option<String>,
    /// Application deadline.
    pub application_deadline: Option<String>,
    /// Capacity.
    pub capacity: Option<i32>,
    /// Creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
}

/// Accelerator application.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AcceleratorApplication {
    /// Application ID.
    pub group_accelerator_application_id: Uuid,
    /// Cohort ID.
    pub group_accelerator_cohort_id: Uuid,
    /// Applicant user ID.
    pub user_id: Option<Uuid>,
    /// Applicant name.
    pub applicant_name: String,
    /// Applicant email.
    pub applicant_email: String,
    /// Project name.
    pub project_name: String,
    /// Project URL.
    pub project_url: Option<String>,
    /// Pitch.
    pub pitch: String,
    /// Goals.
    pub goals: Option<String>,
    /// Status.
    pub status: String,
    /// Reviewer notes.
    pub reviewer_notes: Option<String>,
    /// Creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
}

/// Accepted accelerator member.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AcceleratorMember {
    /// Member ID.
    pub group_accelerator_member_id: Uuid,
    /// Cohort ID.
    pub group_accelerator_cohort_id: Uuid,
    /// User ID.
    pub user_id: Option<Uuid>,
    /// Display name.
    pub display_name: String,
    /// Project name.
    pub project_name: String,
    /// Project URL.
    pub project_url: Option<String>,
    /// Status.
    pub status: String,
    /// Creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
}

/// Accelerator week.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AcceleratorWeek {
    /// Week ID.
    pub group_accelerator_week_id: Uuid,
    /// Cohort ID.
    pub group_accelerator_cohort_id: Uuid,
    /// Week number.
    pub week_number: i32,
    /// Title.
    pub title: String,
    /// Goals.
    pub goals: Option<String>,
    /// Resources URL.
    pub resources_url: Option<String>,
    /// Deliverable.
    pub deliverable: Option<String>,
    /// Start date.
    pub starts_on: Option<String>,
    /// Due date.
    pub due_on: Option<String>,
    /// Creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
}

/// Weekly update.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AcceleratorWeeklyUpdate {
    /// Update ID.
    pub group_accelerator_weekly_update_id: Uuid,
    /// Member ID.
    pub group_accelerator_member_id: Uuid,
    /// Week ID.
    pub group_accelerator_week_id: Uuid,
    /// User ID.
    pub user_id: Option<Uuid>,
    /// Shipped work.
    pub shipped: String,
    /// Metrics.
    pub metrics: Option<String>,
    /// Blockers.
    pub blockers: Option<String>,
    /// Asks.
    pub asks: Option<String>,
    /// Links.
    pub links: Option<String>,
    /// Status.
    pub status: String,
    /// Reviewer notes.
    pub reviewer_notes: Option<String>,
    /// Creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
}

fn default_true() -> bool {
    true
}

fn valid_cohort_status(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    match value.as_ref() {
        "planned" | "open" | "running" | "completed" | "archived" => Ok(()),
        _ => Err(garde::Error::new("invalid cohort status")),
    }
}

fn valid_application_status(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    match value.as_ref() {
        "submitted" | "reviewing" | "accepted" | "rejected" | "waitlisted" => Ok(()),
        _ => Err(garde::Error::new("invalid application status")),
    }
}

fn valid_weekly_update_status(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    match value.as_ref() {
        "submitted" | "reviewed" => Ok(()),
        _ => Err(garde::Error::new("invalid weekly update status")),
    }
}

fn valid_date_opt(value: &Option<String>, _ctx: &()) -> garde::Result {
    let Some(value) = value.as_deref() else {
        return Ok(());
    };
    chrono::NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map(|_| ())
        .map_err(|_| garde::Error::new("invalid date"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_cohort_statuses() {
        assert!(valid_cohort_status(&"planned", &()).is_ok());
        assert!(valid_cohort_status(&"open", &()).is_ok());
        assert!(valid_cohort_status(&"running", &()).is_ok());
        assert!(valid_cohort_status(&"completed", &()).is_ok());
        assert!(valid_cohort_status(&"archived", &()).is_ok());
        assert!(valid_cohort_status(&"paused", &()).is_err());
    }

    #[test]
    fn validates_application_statuses() {
        assert!(valid_application_status(&"submitted", &()).is_ok());
        assert!(valid_application_status(&"reviewing", &()).is_ok());
        assert!(valid_application_status(&"accepted", &()).is_ok());
        assert!(valid_application_status(&"rejected", &()).is_ok());
        assert!(valid_application_status(&"waitlisted", &()).is_ok());
        assert!(valid_application_status(&"unknown", &()).is_err());
    }

    #[test]
    fn validates_weekly_update_statuses_and_dates() {
        assert!(valid_weekly_update_status(&"submitted", &()).is_ok());
        assert!(valid_weekly_update_status(&"reviewed", &()).is_ok());
        assert!(valid_weekly_update_status(&"done", &()).is_err());
        assert!(valid_date_opt(&Some("2027-03-01".to_string()), &()).is_ok());
        assert!(valid_date_opt(&Some("03/01/2027".to_string()), &()).is_err());
    }
}
