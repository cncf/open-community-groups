//! Notification type definitions.

use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    types::dashboard::community::contact::CommunityContactFilters,
    validation::{MAX_LEN_M, MAX_LEN_NOTIFICATION_BODY, trimmed_non_empty},
};

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

/// Community-authored custom notification addressed to group team members.
///
/// Recipients are resolved by the database from the filters when the
/// notification is enqueued, so this input deliberately carries none.
#[derive(Debug, Clone)]
pub(crate) struct CommunityCustomNotificationInput {
    /// User sending the notification.
    pub actor_user_id: Uuid,
    /// Community the notification is sent from.
    pub community_id: Uuid,
    /// Subject and body of the notification.
    pub content: CustomNotificationContent,
    /// Filters selecting the group team members to notify.
    pub filters: CommunityContactFilters,
}

/// Subject and body of an organizer-authored custom notification.
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub(crate) struct CustomNotificationContent {
    /// Body text of the notification.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_NOTIFICATION_BODY))]
    pub body: String,
    /// Subject line of the notification email.
    #[serde(alias = "title")]
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub subject: String,
}

/// Organizer-authored custom notification addressed to event attendees.
#[derive(Debug, Clone)]
pub(crate) struct EventCustomNotificationInput {
    /// User sending the notification.
    pub actor_user_id: Uuid,
    /// Community containing the event.
    pub community_id: Uuid,
    /// Subject and body of the notification.
    pub content: CustomNotificationContent,
    /// Event the notification is about.
    pub event_id: Uuid,
    /// Group organizing the event.
    pub group_id: Uuid,
    /// Resolved recipient user identifiers.
    pub recipients: Vec<Uuid>,
}

/// Organizer-authored custom notification addressed to group members.
///
/// The enqueue service resolves the group members and team as recipients.
#[derive(Debug, Clone)]
pub(crate) struct GroupCustomNotificationInput {
    /// User sending the notification.
    pub actor_user_id: Uuid,
    /// Community containing the group.
    pub community_id: Uuid,
    /// Subject and body of the notification.
    pub content: CustomNotificationContent,
    /// Group the notification is about.
    pub group_id: Uuid,
}

/// Data required to create a new notification.
#[derive(Debug, Clone)]
pub(crate) struct NewNotification {
    /// Files to include in the notification email.
    pub attachments: Vec<Attachment>,
    /// Groups named in the notification; recipients who muted any of them skip
    /// group-mutable categories.
    pub group_ids: Vec<Uuid>,
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
    /// Notification for a custom community message to group teams.
    CommunityCustom,
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
    /// Notification inviting a group's admins to co-host events.
    EventCohostInvitation,
    /// Notification that a group's co-hosting of events ended.
    EventCohostRemoved,
    /// Notification that a co-host group responded to a co-hosting invitation.
    EventCohostResponded,
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
    /// Notification telling group team members that a user wrote to the group inbox.
    InboxMessageReceived,
    /// Notification telling a user that the group replied to their inbox conversation.
    InboxReplyReceived,
    /// Notification inviting a co-speaker to respond to a session proposal invitation.
    SessionProposalCoSpeakerInvitation,
    /// Notification welcoming a speaker to multiple events in a linked series.
    SpeakerSeriesWelcome,
    /// Notification welcoming a speaker to an event.
    SpeakerWelcome,
}
