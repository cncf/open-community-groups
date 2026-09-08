//! Notification type definitions.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Represents a file that should be sent with a notification.
#[derive(Debug, Clone)]
pub(crate) struct Attachment {
    /// MIME type for the attachment body.
    pub content_type: String,
    /// Raw attachment data.
    pub data: Vec<u8>,
    /// File name shown to recipients.
    pub file_name: String,
}

/// Data required to create a new notification.
#[derive(Debug, Clone)]
pub(crate) struct NewNotification {
    /// Files to include in the notification email.
    pub attachments: Vec<Attachment>,
    /// The type of notification to send.
    pub kind: NotificationKind,
    /// The user IDs to notify.
    pub recipients: Vec<Uuid>,

    /// Optional template data for the notification content.
    pub template_data: Option<serde_json::Value>,
}

/// Data required to deliver a notification to a user.
#[derive(Debug, Clone)]
pub(crate) struct Notification {
    /// Files included with the notification.
    pub attachments: Vec<Attachment>,
    /// Timestamp identifying the active delivery claim.
    pub delivery_claimed_at: DateTime<Utc>,
    /// Email address to send the notification to.
    pub email: String,
    /// The type of notification.
    pub kind: NotificationKind,
    /// Unique identifier for the notification.
    pub notification_id: Uuid,

    /// Optional template data for the notification content.
    pub template_data: Option<serde_json::Value>,
}

/// Supported notification types.
#[derive(Debug, Clone, Serialize, Deserialize, strum::Display, strum::EnumString)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum NotificationKind {
    /// Notification for a newly awarded badge.
    BadgeAwarded,
    /// Notification for a permanently revoked badge.
    BadgeRevoked,
    /// Notification for a CFS submission update.
    CfsSubmissionUpdated,
    /// Notification for a community team invitation.
    CommunityTeamInvitation,
    /// Notification for email verification.
    EmailVerification,
    /// Notification for a canceled event admission offer.
    EventAdmissionOfferCanceled,
    /// Notification for a newly created organizer event admission offer.
    EventAdmissionOfferCreated,
    /// Notification for an organizer whose event admission offer was declined.
    EventAdmissionOfferDeclined,
    /// Notification for a canceled event attendance.
    EventAttendanceCanceled,
    /// Notification for an event canceled.
    EventCanceled,
    /// Notification for a custom event message.
    EventCustom,
    /// Notification that an external payment window expired.
    EventExternalPaymentExpired,
    /// Notification with instructions for a pending external payment.
    EventExternalPaymentPending,
    /// Notification reminding an attendee that an external payment is due.
    EventExternalPaymentReminder,
    /// Notification for an organizer-created event invitation.
    EventInvitation,
    /// Notification for paid events configured by an organizer.
    EventPaidConfigured,
    /// Notification for an event published.
    EventPublished,
    /// Notification for an approved refund.
    EventRefundApproved,
    /// Notification for a rejected refund request.
    EventRefundRejected,
    /// Notification for a newly requested refund.
    EventRefundRequested,
    /// Notification reminding users about an upcoming event.
    EventReminder,
    /// Notification for an event rescheduled.
    EventRescheduled,
    /// Notification for multiple canceled events in a linked series.
    EventSeriesCanceled,
    /// Notification for multiple published events in a linked series.
    EventSeriesPublished,
    /// Notification for an approved ticket request offer.
    EventTicketRequestApproved,
    /// Notification for an offer created from a ticket waiting list.
    EventTicketWaitlistOffer,
    /// Notification for joining an event waiting list.
    EventWaitlistJoined,
    /// Notification for leaving an event waiting list.
    EventWaitlistLeft,
    /// Notification for being promoted from an event waiting list.
    EventWaitlistPromoted,
    /// Notification welcoming a new event attendee.
    EventWelcome,
    /// Notification for a custom group message.
    GroupCustom,
    /// Notification for a group team invitation.
    GroupTeamInvitation,
    /// Notification welcoming a new group member.
    GroupWelcome,
    /// Notification inviting a co-speaker to respond to a session proposal invitation.
    SessionProposalCoSpeakerInvitation,
    /// Notification welcoming a speaker to multiple events in a linked series.
    SpeakerSeriesWelcome,
    /// Notification welcoming a speaker to an event.
    SpeakerWelcome,
}
