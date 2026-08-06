//! Notifications templates.

use askama::Template;
use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};

use crate::types::{
    event::EventSummary, group::GroupSummary, payments::format_amount_minor, site::Theme,
};

// Emails templates.

/// Template for a newly awarded badge notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/badge_awarded.html")]
pub(crate) struct BadgeAwarded {
    /// Immutable badge and issuer snapshot.
    pub badge: crate::types::badges::BadgeSnapshot,
    /// Link to badge controls in the user dashboard.
    pub dashboard_url: String,
    /// Theme configuration for the community.
    pub theme: Theme,

    /// Deployment base URL added immediately before delivery.
    #[serde(default)]
    pub base_url: String,
}

impl BadgeAwarded {
    /// Return the stable public badge image path.
    pub fn image_url(&self) -> String {
        format!(
            "{}/images/badges/{}",
            self.base_url.trim_end_matches('/'),
            self.badge.image_file_name
        )
    }
}

/// Template for a permanently revoked badge notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/badge_revoked.html")]
pub(crate) struct BadgeRevoked {
    /// Immutable badge name.
    pub badge_name: String,
    /// Link to badge controls in the user dashboard.
    pub dashboard_url: String,
    /// Issuing group name.
    pub group_name: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for CFS submission update notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/cfs_submission_updated.html")]
pub(crate) struct CfsSubmissionUpdated {
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the user dashboard submissions page.
    pub link: String,
    /// Submission status name.
    pub status_name: String,
    /// Theme configuration for the community.
    pub theme: Theme,

    /// Action required message for the speaker.
    pub action_required_message: Option<String>,
}

/// Template for community team invitation notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/community_team_invitation.html")]
pub(crate) struct CommunityTeamInvitation {
    /// Community display name.
    pub community_name: String,
    /// Link to manage invitations in the dashboard.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for email verification notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/email_verification.html")]
pub(crate) struct EmailVerification {
    /// Verification link for the user to confirm their email address.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for a canceled event admission offer notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_admission_offer_canceled.html")]
pub(crate) struct EventAdmissionOfferCanceled {
    /// Link to review the user's remaining events and offers.
    pub dashboard_url: String,
    /// Event display name.
    pub event_name: String,
    /// Group display name.
    pub group_name: String,
    /// Theme configuration for the community.
    pub theme: Theme,

    /// Assigned ticket title.
    pub ticket_title: Option<String>,
}

/// Template for a newly created organizer admission offer notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_admission_offer_created.html")]
pub(crate) struct EventAdmissionOfferCreated {
    /// Link to claim or decline the offer.
    pub dashboard_url: String,
    /// Event display name.
    pub event_name: String,
    /// Offer expiration time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub expires_at: DateTime<Utc>,
    /// Group display name.
    pub group_name: String,
    /// Theme configuration for the community.
    pub theme: Theme,
    /// Event timezone used to display the offer deadline.
    pub timezone: Tz,

    /// Current ticket amount in minor units, when this is a ticket offer.
    pub amount_minor: Option<i64>,
    /// Currency used to display the current ticket amount.
    pub currency_code: Option<String>,
    /// Whether the offer belongs to a plain RSVP event.
    #[serde(default)]
    pub is_simple_rsvp: bool,
    /// Whether registration questions must be completed.
    #[serde(default)]
    pub registration_questions_required: bool,
    /// Assigned ticket title.
    pub ticket_title: Option<String>,
}

impl EventAdmissionOfferCreated {
    /// Formats the current displayed offer price.
    pub(crate) fn price_label(&self) -> String {
        format_offer_price(self.amount_minor, self.currency_code.as_deref())
    }
}

/// Template for an organizer notification that an offer was declined.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_admission_offer_declined.html")]
pub(crate) struct EventAdmissionOfferDeclined {
    /// Link to the organizer attendee view.
    pub dashboard_url: String,
    /// Event display name.
    pub event_name: String,
    /// Group display name.
    pub group_name: String,
    /// Display name of the recipient who declined.
    pub recipient_name: String,
    /// Theme configuration for the community.
    pub theme: Theme,

    /// Assigned ticket title.
    pub ticket_title: Option<String>,
}

/// Template for event attendance canceled notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_attendance_canceled.html")]
pub(crate) struct EventAttendanceCanceled {
    /// Link to the user dashboard events page.
    pub dashboard_link: String,
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for event canceled notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_canceled.html")]
pub(crate) struct EventCanceled {
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for event custom notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_custom.html")]
pub(crate) struct EventCustom {
    /// Body text provided for the event notification.
    pub body: String,
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Subject provided for the event notification.
    #[serde(alias = "title")]
    pub subject: String,
    /// Theme configuration for the notification.
    pub theme: Theme,
}

/// Template for event invitation notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_invitation.html")]
pub(crate) struct EventInvitation {
    /// Event summary data.
    pub event: EventSummary,
    /// Whether the event has registration questions configured.
    pub has_registration_questions: bool,
    /// Link to manage invitations in the dashboard.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for event published notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_published.html")]
pub(crate) struct EventPublished {
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template event item for aggregate event series notifications.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventSeriesNotificationItem {
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
}

/// Template for attendee refund approval notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_refund_approved.html")]
pub(crate) struct EventRefundApproved {
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for attendee refund rejection notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_refund_rejected.html")]
pub(crate) struct EventRefundRejected {
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Attendee-visible reason supplied by the organizer.
    pub rejection_reason: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for organizer refund request notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_refund_requested.html")]
pub(crate) struct EventRefundRequested {
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for event reminder notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_reminder.html")]
pub(crate) struct EventReminder {
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Whether to show attendance cancellation copy.
    pub show_attendance_cancellation_copy: bool,
    /// Theme configuration for the community.
    pub theme: Theme,

    /// Link to the user dashboard events page.
    #[serde(default)]
    pub dashboard_link: Option<String>,
}

/// Template for event rescheduled notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_rescheduled.html")]
pub(crate) struct EventRescheduled {
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for aggregate event series canceled notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_series_canceled.html")]
pub(crate) struct EventSeriesCanceled {
    /// Number of events included in the notification.
    pub event_count: usize,
    /// Events included in the notification.
    pub events: Vec<EventSeriesNotificationItem>,
    /// Name of the group hosting the events.
    pub group_name: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for aggregate event series published notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_series_published.html")]
pub(crate) struct EventSeriesPublished {
    /// Community display name for the events.
    pub community_display_name: String,
    /// Number of events included in the notification.
    pub event_count: usize,
    /// Events included in the notification.
    pub events: Vec<EventSeriesNotificationItem>,
    /// Name of the group hosting the events.
    pub group_name: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for an approved ticket request notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_ticket_request_approved.html")]
pub(crate) struct EventTicketRequestApproved {
    /// Current ticket amount in minor units.
    pub amount_minor: i64,
    /// Link to claim or decline the approved offer.
    pub dashboard_url: String,
    /// Event display name.
    pub event_name: String,
    /// Offer expiration time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub expires_at: DateTime<Utc>,
    /// Group display name.
    pub group_name: String,
    /// Theme configuration for the community.
    pub theme: Theme,
    /// Assigned ticket title.
    pub ticket_title: String,
    /// Event timezone used to display the offer deadline.
    pub timezone: Tz,

    /// Currency used to display the current ticket amount.
    pub currency_code: Option<String>,
    /// Whether the offer belongs to a plain RSVP event.
    #[serde(default)]
    pub is_simple_rsvp: bool,
}

impl EventTicketRequestApproved {
    /// Formats the current displayed offer price.
    pub(crate) fn price_label(&self) -> String {
        format_offer_price(Some(self.amount_minor), self.currency_code.as_deref())
    }
}

/// Template for a ticket waitlist offer notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_ticket_waitlist_offer.html")]
pub(crate) struct EventTicketWaitlistOffer {
    /// Current ticket amount in minor units.
    pub amount_minor: i64,
    /// Link to claim or decline the offer.
    pub dashboard_url: String,
    /// Event display name.
    pub event_name: String,
    /// Offer expiration time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub expires_at: DateTime<Utc>,
    /// Group display name.
    pub group_name: String,
    /// Theme configuration for the community.
    pub theme: Theme,
    /// Assigned ticket title.
    pub ticket_title: String,
    /// Event timezone used to display the offer deadline.
    pub timezone: Tz,

    /// Currency used to display the current ticket amount.
    pub currency_code: Option<String>,
    /// Whether the offer belongs to a plain RSVP event.
    #[serde(default)]
    pub is_simple_rsvp: bool,
}

impl EventTicketWaitlistOffer {
    /// Formats the current displayed offer price.
    pub(crate) fn price_label(&self) -> String {
        format_offer_price(Some(self.amount_minor), self.currency_code.as_deref())
    }
}

/// Template for event waitlist joined notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_waitlist_joined.html")]
pub(crate) struct EventWaitlistJoined {
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for event waitlist left notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_waitlist_left.html")]
pub(crate) struct EventWaitlistLeft {
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for event waitlist promotion notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_waitlist_promoted.html")]
pub(crate) struct EventWaitlistPromoted {
    /// Event summary data.
    pub event: EventSummary,
    /// Whether the event has registration questions configured.
    pub has_registration_questions: bool,
    /// Link to the event page.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,

    /// Link to the user dashboard events page.
    #[serde(default)]
    pub dashboard_link: Option<String>,
}

/// Template for event welcome notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_welcome.html")]
pub(crate) struct EventWelcome {
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,

    /// Link to the user dashboard events page.
    #[serde(default)]
    pub dashboard_link: Option<String>,
}

/// Template for group custom notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/group_custom.html")]
pub(crate) struct GroupCustom {
    /// Body text provided for the group notification.
    pub body: String,
    /// Group summary data.
    pub group: GroupSummary,
    /// Link to the group page.
    pub link: String,
    /// Subject provided for the group notification.
    #[serde(alias = "title")]
    pub subject: String,
    /// Theme configuration for the notification.
    pub theme: Theme,
}

/// Template for group team invitation notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/group_team_invitation.html")]
pub(crate) struct GroupTeamInvitation {
    /// Group summary data.
    pub group: GroupSummary,
    /// Link to manage invitations in the dashboard.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for group welcome notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/group_welcome.html")]
pub(crate) struct GroupWelcome {
    /// Group summary data.
    pub group: GroupSummary,
    /// Link to the group page.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for session proposal co-speaker invitation notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/session_proposal_co_speaker_invitation.html")]
pub(crate) struct SessionProposalCoSpeakerInvitation {
    /// Link to review and respond to the invitation.
    pub link: String,
    /// Session proposal title included in the invitation.
    pub session_proposal_title: String,
    /// Name of the speaker who sent the invitation.
    pub speaker_name: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for speaker welcome notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/speaker_welcome.html")]
pub(crate) struct SpeakerWelcome {
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for aggregate speaker welcome notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/speaker_series_welcome.html")]
pub(crate) struct SpeakerSeriesWelcome {
    /// Number of events included in the notification.
    pub event_count: usize,
    /// Events included in the notification.
    pub events: Vec<EventSeriesNotificationItem>,
    /// Name of the group hosting the events.
    pub group_name: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Formats the attendee-facing current price for an admission offer.
fn format_offer_price(amount_minor: Option<i64>, currency_code: Option<&str>) -> String {
    match amount_minor {
        None | Some(0) => "Free".to_string(),
        Some(amount_minor) => currency_code.map_or_else(
            || "Price unavailable".to_string(),
            |currency_code| format_amount_minor(amount_minor, currency_code),
        ),
    }
}
