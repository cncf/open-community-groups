//! Templates for the user dashboard invitations tab.

use askama::Template;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    templates::helpers::DATE_FORMAT_2,
    types::{
        community::CommunityRole,
        event::{EventAdmissionOfferSource, EventAdmissionOfferStatus},
        group::GroupRole,
        payments::format_amount_minor,
        questionnaire::{QuestionnaireAnswers, QuestionnaireQuestion},
    },
};

// Pages templates.

/// List page showing pending invitations for the user.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/user/invitations_list.html")]
pub(crate) struct ListPage {
    /// Pending community invitations for the current user.
    pub community_invitations: Vec<CommunityTeamInvitation>,
    /// Active event admission offers for the current user.
    pub event_invitations: Vec<EventInvitation>,
    /// Pending group invitations for the current user.
    pub group_invitations: Vec<GroupTeamInvitation>,
}

// Types.

/// Community team invitation summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CommunityTeamInvitation {
    /// Community identifier.
    pub community_id: Uuid,
    /// Community name (slug).
    pub community_name: String,
    /// Role within the community.
    pub role: CommunityRole,

    /// Invitation creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
}

/// Event admission offer summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventInvitation {
    /// Admission offer identifier.
    pub admission_offer_id: Uuid,
    /// Workflow that created the admission offer.
    pub admission_offer_source: EventAdmissionOfferSource,
    /// Current offer lifecycle status.
    pub admission_offer_status: EventAdmissionOfferStatus,
    /// Human-readable display name of the community.
    pub community_display_name: String,
    /// Community slug.
    pub community_name: String,
    /// Offer creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Event identifier.
    pub event_id: Uuid,
    /// Event display name.
    pub event_name: String,
    /// Group display name.
    pub group_name: String,
    /// Timezone in which event dates should be displayed.
    pub timezone: chrono_tz::Tz,

    /// Current or snapshotted offer amount in minor units.
    pub amount_minor: Option<i64>,
    /// Currency used to display the offer amount.
    pub currency_code: Option<String>,
    /// Ticket type assigned to the offer.
    pub event_ticket_type_id: Option<Uuid>,
    /// Offer expiration time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub expires_at: Option<DateTime<Utc>>,
    /// Existing registration answers from a ticket request or checkout.
    pub registration_answers: Option<QuestionnaireAnswers>,
    /// Registration questions configured for the event.
    #[serde(default)]
    pub registration_questions: Vec<QuestionnaireQuestion>,
    /// Provider URL where an active checkout can be resumed.
    pub resume_checkout_url: Option<String>,
    /// Event start time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub starts_at: Option<DateTime<Utc>>,
    /// Assigned ticket title.
    pub ticket_title: Option<String>,
}

impl EventInvitation {
    /// Returns true when this offer currently owns a checkout hold.
    pub(crate) fn checkout_started(&self) -> bool {
        self.event_ticket_type_id.is_some()
            && self.admission_offer_status == EventAdmissionOfferStatus::CheckoutPending
    }

    /// Returns the attendee-facing action label for this offer.
    pub(crate) fn claim_label(&self) -> &'static str {
        if self.event_ticket_type_id.is_some() {
            "Claim ticket"
        } else {
            "Accept invitation"
        }
    }

    /// Returns whether a discount code can apply to this ticket offer.
    pub(crate) fn discount_code_available(&self) -> bool {
        self.event_ticket_type_id.is_some() && self.amount_minor != Some(0)
    }

    /// Returns the attendee-facing price label for a ticket offer.
    pub(crate) fn price_label(&self) -> Option<String> {
        match (self.amount_minor, self.currency_code.as_deref()) {
            (Some(0), _) => Some("Free".to_string()),
            (Some(amount_minor), Some(currency_code)) => {
                Some(format_amount_minor(amount_minor, currency_code))
            }
            _ => None,
        }
    }

    /// Returns a label describing how the offer was created.
    pub(crate) fn source_label(&self) -> &'static str {
        match self.admission_offer_source {
            EventAdmissionOfferSource::Approval => "Ticket request approved",
            EventAdmissionOfferSource::OrganizerInvitation => "Organizer invitation",
            EventAdmissionOfferSource::Waitlist => "Waiting list offer",
        }
    }
}

/// Group team invitation summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupTeamInvitation {
    /// Community name (slug).
    pub community_name: String,
    /// Group identifier.
    pub group_id: Uuid,
    /// Group name.
    pub group_name: String,
    /// Role within the group.
    pub role: GroupRole,

    /// Invitation creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
}

#[cfg(test)]
mod tests {
    use chrono::{TimeZone, Utc};
    use chrono_tz::UTC;
    use uuid::Uuid;

    use super::EventInvitation;
    use crate::types::event::{EventAdmissionOfferSource, EventAdmissionOfferStatus};

    #[test]
    fn event_invitation_claim_label_distinguishes_ticket_offers() {
        let mut invitation = sample_event_invitation();

        assert_eq!(invitation.claim_label(), "Accept invitation");

        invitation.event_ticket_type_id = Some(Uuid::from_u128(2));

        assert_eq!(invitation.claim_label(), "Claim ticket");
    }

    #[test]
    fn event_invitation_discount_code_available_rejects_free_offers() {
        let mut invitation = sample_event_invitation();
        invitation.event_ticket_type_id = Some(Uuid::from_u128(2));

        assert!(invitation.discount_code_available());

        invitation.amount_minor = Some(0);

        assert!(!invitation.discount_code_available());
    }

    #[test]
    fn event_invitation_price_label_formats_free_and_paid_offers() {
        let mut invitation = sample_event_invitation();
        invitation.amount_minor = Some(0);

        assert_eq!(invitation.price_label().as_deref(), Some("Free"));

        invitation.amount_minor = Some(2_500);
        invitation.currency_code = Some("usd".to_string());

        assert_eq!(invitation.price_label().as_deref(), Some("USD 25.00"));
    }

    // Helpers.

    /// Sample event invitation used by display-helper tests.
    fn sample_event_invitation() -> EventInvitation {
        EventInvitation {
            admission_offer_id: Uuid::from_u128(1),
            admission_offer_source: EventAdmissionOfferSource::OrganizerInvitation,
            admission_offer_status: EventAdmissionOfferStatus::Pending,
            community_display_name: "Test Community".to_string(),
            community_name: "test-community".to_string(),
            created_at: Utc.with_ymd_and_hms(2024, 1, 1, 12, 0, 0).unwrap(),
            event_id: Uuid::from_u128(3),
            event_name: "Test Event".to_string(),
            group_name: "Test Group".to_string(),
            timezone: UTC,

            amount_minor: None,
            currency_code: None,
            event_ticket_type_id: None,
            expires_at: None,
            registration_answers: None,
            registration_questions: vec![],
            resume_checkout_url: None,
            starts_at: None,
            ticket_title: None,
        }
    }
}
