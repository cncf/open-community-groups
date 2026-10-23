//! Group dashboard event analytics types.

use chrono::{DateTime, NaiveDate, Utc};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::types::{
    event::EventAdmissionOfferSource, event_survey::EventSurveyState,
    questionnaire::QuestionnaireQuestionBreakdown,
};

#[cfg(test)]
mod tests;

/// Analytics of an event owned by a group.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventAnalytics {
    /// Audience composition and registration answers.
    pub audience: EventAudienceStats,
    /// Check-in arrivals.
    pub check_ins: EventCheckInStats,
    /// Current enrollment counts.
    pub enrollment: EventEnrollmentStats,
    /// Event configuration the statistics depend on.
    pub event: EventAnalyticsContext,
    /// Lifecycle milestones inside the range.
    pub markers: Vec<EventAnalyticsMarker>,
    /// Announcements inside the range left out of the markers.
    pub markers_announcements_omitted: i64,
    /// Survey responses of the surveys that are not drafts.
    pub surveys: EventSurveysStats,
    /// Lifecycle traffic and registrations.
    pub traffic: EventTrafficStats,
    /// All-time UTM attribution.
    pub utm: EventUtmStats,

    /// Lifecycle range in UTC days, missing when it cannot be resolved.
    pub range: Option<EventAnalyticsRange>,
    /// Seat and discount code usage, only reported for paid events.
    pub tickets: Option<EventTicketsStats>,
}

impl EventAnalytics {
    /// Returns the share of registrations that checked in.
    pub(crate) fn check_in_rate(&self) -> Option<f64> {
        ratio(self.enrollment.checked_in, self.enrollment.registrations)
    }

    /// Returns the approximate share of page views that led to a registration.
    pub(crate) fn conversion_rate(&self) -> Option<f64> {
        ratio(self.enrollment.registrations, self.traffic.views_total)
    }

    /// Returns the share of the configured capacity taken by registrations.
    pub(crate) fn fill_rate(&self) -> Option<f64> {
        let capacity = self.event.capacity.filter(|capacity| *capacity > 0)?;
        ratio(self.enrollment.registrations, i64::from(capacity))
    }

    /// Returns whether the event had ended at the given time.
    pub(crate) fn has_ended_at(&self, now: DateTime<Utc>) -> bool {
        self.event.effective_ends_at().is_some_and(|ends_at| ends_at <= now)
    }

    /// Returns the share of all page views represented by a view count, when
    /// attribution is consistent.
    pub(crate) fn share_of_views(&self, views: i64) -> Option<f64> {
        if !self.traffic.attribution_consistent {
            return None;
        }
        ratio(views, self.traffic.views_total)
    }

    /// Returns the views without recorded UTM attribution, when consistent.
    pub(crate) fn untagged_views(&self) -> Option<i64> {
        self.traffic
            .attribution_consistent
            .then(|| self.traffic.views_total - self.utm.tagged_views)
    }

    /// Returns the views recorded outside the lifecycle range.
    pub(crate) fn views_hidden_count(&self) -> i64 {
        self.traffic.views_after_end + self.traffic.views_before_start
    }
}

/// Admission offers of one source and outcome.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventAdmissionOfferCount {
    /// Number of offers.
    pub count: i64,
    /// Offer outcome.
    pub outcome: EventAdmissionOfferOutcome,
    /// Offer source.
    pub source: EventAdmissionOfferSource,
}

/// Outcomes of admission offers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum EventAdmissionOfferOutcome {
    /// Offer still reserving a seat before its deadline.
    Active,
    /// Offer canceled.
    Canceled,
    /// Offer completed.
    Completed,
    /// Offer still pending after its deadline passed.
    DeadlinePassed,
    /// Offer declined.
    Declined,
    /// Offer expired.
    Expired,
}

/// Event configuration reported with the analytics.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventAnalyticsContext {
    /// Whether the event was canceled.
    pub canceled: bool,
    /// Whether the event sells paid tickets.
    pub is_paid: bool,
    /// Whether the event is published.
    pub published: bool,
    /// Event timezone.
    pub timezone: Tz,

    /// Configured capacity.
    pub capacity: Option<i32>,
    /// Event end time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub ends_at: Option<DateTime<Utc>>,
    /// Latest publication time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub published_at: Option<DateTime<Utc>>,
    /// Configured registration close time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub registration_ends_at: Option<DateTime<Utc>>,
    /// Configured registration open time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub registration_starts_at: Option<DateTime<Utc>>,
    /// Event start time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub starts_at: Option<DateTime<Utc>>,
}

impl EventAnalyticsContext {
    /// Returns when the event stops being current: its end, or its start.
    pub(crate) fn effective_ends_at(&self) -> Option<DateTime<Utc>> {
        self.ends_at.or(self.starts_at)
    }
}

/// Lifecycle milestone shown on the daily charts.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventAnalyticsMarker {
    /// Milestone kind.
    pub kind: EventAnalyticsMarkerKind,
    /// Milestone time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub ts: DateTime<Utc>,
}

/// Kinds of lifecycle milestones.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum EventAnalyticsMarkerKind {
    /// Announcement sent to attendees.
    Announcement,
    /// Event start.
    EventStart,
    /// Latest publication.
    Published,
    /// Configured registration close.
    RegistrationCloses,
    /// Configured registration open.
    RegistrationOpens,
    /// Event reminder sent.
    ReminderSent,
}

/// Lifecycle range in UTC days, both ends included.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventAnalyticsRange {
    /// Last day of the range.
    pub end_day: NaiveDate,
    /// First day of the range.
    pub start_day: NaiveDate,
}

/// Audience composition and registration answer breakdowns.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventAudienceStats {
    /// Select question breakdowns in configured order.
    pub questions: Vec<QuestionnaireQuestionBreakdown>,
    /// Whether the window close was cut short by the event end or by now.
    pub window_end_capped: bool,
    /// Whether the window has no configured close.
    pub window_end_inferred: bool,
    /// Whether the window opens at the publication.
    pub window_start_inferred: bool,

    /// Group members who joined during the registration window.
    pub members_joined_in_window: Option<i64>,
    /// Members who joined during the window and registered.
    pub members_joined_in_window_registered: Option<i64>,
    /// Registrations without a prior attendance in the group.
    pub new_attendees: Option<i64>,
    /// Registrations with a prior attendance in the group.
    pub returning_attendees: Option<i64>,
    /// Registration window close.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub window_ends_at: Option<DateTime<Utc>>,
    /// Registration window open.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub window_starts_at: Option<DateTime<Utc>>,
}

/// Check-in arrivals in aligned time bins.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventCheckInStats {
    /// Bin width in minutes.
    pub bin_minutes: i32,
    /// Check-ins per bin start, in Unix milliseconds.
    pub bins: Vec<(i64, i64)>,
    /// Check-ins outside the binned span.
    pub outside_range: i64,
}

impl EventCheckInStats {
    /// Returns whether any check-in falls inside the bins.
    pub(crate) fn has_activity(&self) -> bool {
        self.bins.iter().any(|(_, count)| *count > 0)
    }
}

/// Redemptions of one discount code.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventDiscountCodeUsage {
    /// Whether the code can be redeemed.
    pub active: bool,
    /// Code entered by attendees.
    pub code: String,
    /// Discount code identifier.
    pub event_discount_code_id: Uuid,
    /// Purchases holding a seat that used the code.
    pub redemptions: i64,
    /// Discount code title.
    pub title: String,

    /// Redemptions still available.
    pub available: Option<i64>,
    /// Configured redemptions.
    pub total_available: Option<i64>,
}

/// Current enrollment counts.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventEnrollmentStats {
    /// Admission offers by source and outcome.
    pub admission_offers: Vec<EventAdmissionOfferCount>,
    /// Attendances canceled.
    pub cancellations: i64,
    /// Confirmed attendees checked in.
    pub checked_in: i64,
    /// Invitation requests by review status.
    pub invitation_requests: EventInvitationRequestCounts,
    /// Confirmed attendees.
    pub registrations: i64,
    /// Confirmed attendees by the path that admitted them.
    pub registrations_by_path: EventRegistrationPathCounts,
    /// Waiting list entries.
    pub waitlist: i64,
}

/// Invitation requests by review status.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventInvitationRequestCounts {
    /// Accepted requests.
    pub accepted: i64,
    /// Requests waiting for review.
    pub pending: i64,
    /// Rejected requests.
    pub rejected: i64,
}

/// Confirmed attendees by the path that admitted them.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventRegistrationPathCounts {
    /// Attendees admitted through an approved invitation request.
    pub approval: i64,
    /// Attendees who registered or purchased directly.
    pub direct: i64,
    /// Attendees invited by an organizer.
    pub organizer_invitation: i64,
    /// Attendees whose admission path is not recorded.
    pub unknown: i64,
    /// Attendees admitted from the waiting list.
    pub waitlist: i64,
}

/// Daily registrations of one ticket type.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventRegistrationsDailySeries {
    /// Series kind.
    pub kind: RegistrationSeriesKind,
    /// Registrations per UTC day.
    pub series: Vec<(String, i64)>,

    /// Ticket type identifier.
    pub event_ticket_type_id: Option<Uuid>,
    /// Ticket type display order.
    pub order: Option<i32>,
    /// Ticket type title.
    pub title: Option<String>,
}

/// Responses of one survey that is not a draft.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventSurveyResponseStats {
    /// Attendees currently in the survey audience.
    pub eligible_count: i64,
    /// Attendees currently in the survey audience who responded.
    pub eligible_respondents_count: i64,
    /// Survey identifier.
    pub event_survey_id: Uuid,
    /// Stored responses, including those of users no longer eligible.
    pub responses_count: i64,
    /// Live survey state.
    pub state: EventSurveyState,
    /// Survey title.
    pub title: String,
}

impl EventSurveyResponseStats {
    /// Returns the share of the current survey audience who responded.
    pub(crate) fn response_rate(&self) -> Option<f64> {
        ratio(self.eligible_respondents_count, self.eligible_count)
    }
}

/// Survey responses of an event.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventSurveysStats {
    /// Surveys that are not drafts, in creation order.
    pub surveys: Vec<EventSurveyResponseStats>,
    /// Audience of the surveys that already opened.
    pub total_eligible_count: i64,
    /// Respondents in the audience of the surveys that already opened.
    pub total_eligible_respondents_count: i64,
}

impl EventSurveysStats {
    /// Returns the overall response rate of the surveys that already opened,
    /// weighting each survey by its audience.
    pub(crate) fn response_rate(&self) -> Option<f64> {
        ratio(
            self.total_eligible_respondents_count,
            self.total_eligible_count,
        )
    }
}

/// Seat usage of one ticket type.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventTicketTypeUsage {
    /// Whether the ticket type is on sale.
    pub active: bool,
    /// Seats taken by purchases, live holds and active offers.
    pub allocated: i64,
    /// Ticket type identifier.
    pub event_ticket_type_id: Uuid,
    /// Display order.
    pub order: i32,
    /// Seats still available.
    pub remaining: i64,
    /// Configured seats.
    pub seats_total: i64,
    /// Seats held by purchases, counting purchases that share an admission offer once.
    pub sold: i64,
    /// Ticket type title.
    pub title: String,
}

impl EventTicketTypeUsage {
    /// Returns the allocated seats not covered by a seat-holding purchase.
    pub(crate) fn reserved(&self) -> i64 {
        (self.allocated - self.sold).max(0)
    }
}

/// Seat and discount code usage of a paid event.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventTicketsStats {
    /// Discount code redemptions.
    pub discount_codes: Vec<EventDiscountCodeUsage>,
    /// Seat usage per ticket type.
    pub ticket_types: Vec<EventTicketTypeUsage>,
}

/// Lifecycle traffic and registration statistics.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventTrafficStats {
    /// Whether tagged views never exceed the total views.
    pub attribution_consistent: bool,
    /// Registrations created before the range.
    pub registrations_baseline: i64,
    /// Daily registrations stacked by ticket type.
    pub registrations_by_ticket_type_per_day: Vec<EventRegistrationsDailySeries>,
    /// Cumulative registrations per day, starting at the baseline.
    pub registrations_running_total: Vec<(String, i64)>,
    /// All-time views recorded after the range.
    pub views_after_end: i64,
    /// All-time views recorded before the range.
    pub views_before_start: i64,
    /// Daily views stacked by source.
    pub views_by_source_per_day: Vec<EventViewsDailySeries>,
    /// All-time page views.
    pub views_total: i64,
}

impl EventTrafficStats {
    /// Returns whether any registration was recorded in the range.
    pub(crate) fn has_registrations_activity(&self) -> bool {
        self.registrations_by_ticket_type_per_day
            .iter()
            .any(|series| has_activity(&series.series))
    }

    /// Returns whether any view was recorded in the range.
    pub(crate) fn has_views_activity(&self) -> bool {
        self.views_by_source_per_day
            .iter()
            .any(|series| has_activity(&series.series))
    }
}

/// Views of one UTM source, medium and campaign combination.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventUtmCombination {
    /// First UTC day with views.
    pub first_day: NaiveDate,
    /// Last UTC day with views.
    pub last_day: NaiveDate,
    /// Tagged views.
    pub views: i64,

    /// Campaign value.
    pub utm_campaign: Option<String>,
    /// Medium value.
    pub utm_medium: Option<String>,
    /// Source value.
    pub utm_source: Option<String>,
}

/// Views of one UTM dimension.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventUtmDimension {
    /// Tagged views without a value for the dimension.
    pub not_specified: i64,
    /// Number of values outside the top ones.
    pub remainder_count: i64,
    /// Views of the values outside the top ones.
    pub remainder_views: i64,
    /// Top values by views.
    pub values: Vec<EventUtmValue>,
}

/// All-time UTM attribution statistics.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventUtmStats {
    /// Views by campaign.
    pub by_campaign: EventUtmDimension,
    /// Views by medium.
    pub by_medium: EventUtmDimension,
    /// Views by source.
    pub by_source: EventUtmDimension,
    /// Top combinations by views.
    pub combinations: Vec<EventUtmCombination>,
    /// Views of the combinations outside the top ones.
    pub combinations_remainder_views: i64,
    /// Number of distinct combinations.
    pub combinations_total_count: i64,
    /// Views with recorded UTM attribution.
    pub tagged_views: i64,
}

impl EventUtmStats {
    /// Returns the number of combinations outside the top ones.
    pub(crate) fn combinations_remainder_count(&self) -> i64 {
        let listed = i64::try_from(self.combinations.len()).unwrap_or(i64::MAX);
        (self.combinations_total_count - listed).max(0)
    }
}

/// Views of one UTM value.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventUtmValue {
    /// Stored value.
    pub value: String,
    /// Tagged views.
    pub views: i64,
}

/// Daily views of one traffic source group.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventViewsDailySeries {
    /// Series kind.
    pub kind: ViewsSeriesKind,
    /// Views per UTC day.
    pub series: Vec<(String, i64)>,

    /// UTM source, only set for top sources.
    pub source: Option<String>,
}

/// Kinds of registration series.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum RegistrationSeriesKind {
    /// Registrations holding a seat of a ticket type.
    TicketType,
    /// Registrations without a seat-holding purchase.
    Unknown,
}

/// Kinds of views series.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum ViewsSeriesKind {
    /// Tagged views without a source.
    NoSource,
    /// Tagged views of the sources outside the top ones.
    OtherSources,
    /// Tagged views of one top source.
    Source,
    /// Views without recorded UTM attribution.
    Untagged,
}

/// Returns whether any value of a day series is not zero.
fn has_activity(series: &[(String, i64)]) -> bool {
    series.iter().any(|(_, count)| *count != 0)
}

/// Returns a ratio, or none when the denominator is not positive.
#[allow(clippy::cast_precision_loss)]
fn ratio(numerator: i64, denominator: i64) -> Option<f64> {
    (denominator > 0).then(|| numerator as f64 / denominator as f64)
}
