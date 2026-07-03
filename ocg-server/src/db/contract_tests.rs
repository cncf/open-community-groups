use std::{collections::HashMap, env, time::Duration};

use anyhow::{Context, Result};
use chrono::NaiveDate;
use deadpool_postgres::{Config as DbConfig, Runtime};
use tokio_postgres::NoTls;
use uuid::Uuid;

use crate::{
    auth::UserSummary,
    db::{
        PgDB,
        alliance::DBAlliance,
        auth::DBAuth,
        common::DBCommon,
        dashboard::{
            alliance::DBDashboardAlliance, common::DBDashboardCommon, group::DBDashboardGroup,
            user::DBDashboardUser,
        },
        event::DBEvent,
        group::DBGroup,
        meetings::DBMeetings,
        payments::{DBPayments, PrepareEventCheckoutPurchaseInput, ReconcileEventPurchaseResult},
        site::DBSite,
    },
    services::meetings::MeetingProvider,
    templates::{
        dashboard::{
            alliance::team::AllianceTeamFilters,
            audit::AuditLogFilters,
            group::{
                attendees::SearchEventAttendeesFilters,
                events::{Event as EventUpdate, EventsListFilters},
                invitation_requests::InvitationRequestsFilters,
                members::GroupMembersFilters,
                sponsors::GroupSponsorsFilters,
                submissions::CfsSubmissionsFilters as GroupCfsSubmissionsFilters,
                team::GroupTeamFilters,
                waitlist::WaitlistFilters,
            },
            user::{
                events::UserEventsFilters, session_proposals::SessionProposalsFilters,
                submissions::CfsSubmissionsFilters as UserCfsSubmissionsFilters,
            },
        },
        site::explore::Entity,
    },
    types::{
        alliance::AllianceRole,
        event::{EventAttendanceStatus, EventInvitationRequestStatus, EventKind},
        group::GroupRole,
        payments::{EventPurchaseStatus, PaymentProvider},
        questionnaire::QuestionnaireAnswerValue,
        search::{SearchEventsFilters, SearchGroupsFilters},
        user::UserProvider,
    },
};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_activate_pre_registered_user_external_provider_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let user_summary = UserSummary {
        email: "activation.contract@example.com".to_string(),
        name: "Contract Activation".to_string(),
        username: "contract-activation".to_string(),

        photo_url: None,
        has_password: None,
        password: None,
        provider: Some(UserProvider::from_github_username(
            "contract-activation".to_string(),
        )),
    };
    let user = db
        .activate_pre_registered_user_external_provider(&activation_id(), &user_summary)
        .await?;

    assert!(user.email_verified);
    assert_eq!(user.name, "Contract Activation");
    assert_eq!(user.registration_status, "registered");
    assert_eq!(user.user_id, activation_id());
    assert_eq!(user.username, "contract-activation");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_approve_event_refund_request_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let purchase = db
        .approve_event_refund_request(
            organizer_id(),
            group_id(),
            ticketed_event_id(),
            refund_approve_buyer_id(),
            "re_contract_refund_approve".to_string(),
            Some("Approved by contract test".to_string()),
        )
        .await?;

    assert_eq!(purchase.alliance_id, alliance_id());
    assert_eq!(purchase.event_id, ticketed_event_id());
    assert_eq!(purchase.user_id, refund_approve_buyer_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_begin_event_refund_approval_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let summary = db
        .begin_event_refund_approval(group_id(), ticketed_event_id(), refund_begin_buyer_id())
        .await?;

    assert_eq!(summary.amount_minor, 2500);
    assert_eq!(summary.currency_code, "USD");
    assert_eq!(summary.event_purchase_id, refund_begin_purchase_id());
    assert_eq!(
        summary.provider_payment_reference.as_deref(),
        Some("pi_contract_refund_begin")
    );
    assert_eq!(summary.status, EventPurchaseStatus::RefundRequested);
    assert_eq!(summary.ticket_title, "Contract Paid Ticket");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_cancel_event_attendee_attendance_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let outcome = db
        .cancel_event_attendee_attendance(
            organizer_id(),
            group_id(),
            mutation_event_id(),
            cancelee_id(),
        )
        .await?;

    assert_eq!(outcome.left_status, EventAttendanceStatus::Attendee);
    assert!(outcome.promoted_user_ids.is_empty());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_meeting_for_auto_end_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let candidate = db
        .claim_meeting_for_auto_end()
        .await?
        .expect("contract auto-end candidate should exist");

    assert_eq!(candidate.meeting_id, auto_end_meeting_id());
    assert_eq!(candidate.provider, MeetingProvider::Zoom);
    assert_eq!(candidate.provider_meeting_id, "contract-auto-end");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_meeting_out_of_sync_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let meeting = db
        .claim_meeting_out_of_sync()
        .await?
        .expect("contract meeting sync candidate should exist");

    assert_eq!(meeting.duration, Some(Duration::from_hours(1)));
    assert_eq!(meeting.event_id, Some(sync_event_id()));
    assert_eq!(meeting.provider, MeetingProvider::Zoom);
    assert!(meeting.sync_claimed_at.is_some());
    assert!(meeting.sync_state_hash.is_some());
    assert_eq!(
        meeting.topic.as_deref(),
        Some("Contract Meeting Sync Event")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_complete_free_event_purchase_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let purchase = db.complete_free_event_purchase(free_purchase_id()).await?;

    assert_eq!(purchase.alliance_id, alliance_id());
    assert_eq!(purchase.event_id, ticketed_event_id());
    assert_eq!(purchase.user_id, free_buyer_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_cfs_submission_notification_data_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let data = db
        .get_cfs_submission_notification_data(event_id(), cfs_submission_id())
        .await?;

    assert_eq!(data.action_required_message, None);
    assert_eq!(data.status_id, "approved");
    assert_eq!(data.status_name, "Approved");
    assert_eq!(data.user_id, attendee_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_alliance_full_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let alliance = db.get_alliance_full(alliance_id()).await?;

    assert!(alliance.active);
    assert_eq!(
        alliance.ad_banner_link_url.as_deref(),
        Some("https://example.com/alliance-ad")
    );
    assert_eq!(alliance.alliance_id, alliance_id());
    assert_eq!(alliance.display_name, "Contract Alliance");
    assert_eq!(alliance.name, "contract-alliance");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_alliance_recently_added_groups_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let groups = db.get_alliance_recently_added_groups(alliance_id()).await?;

    assert_eq!(groups.len(), 1);
    assert_eq!(groups[0].group_id, group_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_alliance_site_stats_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let stats = db.get_alliance_site_stats(alliance_id()).await?;

    assert_eq!(stats.events, 2);
    assert_eq!(stats.events_attendees, 1);
    assert_eq!(stats.groups, 1);
    assert_eq!(stats.groups_members, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_alliance_stats_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let stats = db.get_alliance_stats(alliance_id()).await?;

    assert_eq!(stats.attendees.total, 1);
    assert_eq!(stats.events.total, 2);
    assert_eq!(stats.groups.total, 1);
    assert_eq!(stats.members.total, 1);
    assert_eq!(stats.page_views.alliance.total_views, 0);
    assert_eq!(stats.page_views.events.total_views, 2);
    assert_eq!(stats.page_views.groups.total_views, 3);
    assert_eq!(stats.page_views.total_views, 5);
    assert_eq!(
        stats.reports.events.hosted_total + stats.reports.events.upcoming_total,
        2
    );
    assert_eq!(stats.reports.members.leaders_total, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_alliance_summary_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let alliance = db.get_alliance_summary(alliance_id()).await?;

    assert_eq!(
        alliance.ad_banner_url.as_deref(),
        Some("https://example.com/alliance-ad-banner.png")
    );
    assert_eq!(alliance.alliance_id, alliance_id());
    assert_eq!(alliance.name, "contract-alliance");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_alliance_upcoming_events_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let events = db
        .get_alliance_upcoming_events(alliance_id(), vec![EventKind::Hybrid])
        .await?;

    assert_eq!(events.len(), 1);
    assert_eq!(events[0].event_id, event_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_attendance_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let attendance = db
        .get_event_attendance(alliance_id(), event_id(), attendee_id())
        .await?;

    assert_eq!(attendance.status, EventAttendanceStatus::Attendee);
    assert!(attendance.is_checked_in);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_full_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let event = db.get_event_full(alliance_id(), group_id(), event_id()).await?;

    assert_eq!(
        event.alliance.ad_banner_link_url.as_deref(),
        Some("https://example.com/alliance-ad")
    );
    assert_eq!(
        event.alliance.ad_banner_url.as_deref(),
        Some("https://example.com/alliance-ad-banner.png")
    );
    assert_eq!(event.event_id, event_id());
    assert!(event.has_registration_questions);
    assert_eq!(
        event.luma_url.as_deref(),
        Some("https://luma.com/contract-event")
    );
    assert_eq!(event.registration_questions.len(), 1);
    assert_eq!(event.registration_questions[0].prompt, "Meal preference");
    assert!(event.registration_questions_locked);
    assert_eq!(event.sessions.len(), 1);
    assert_eq!(event.sponsors.len(), 1);
    assert_eq!(
        event.hosts[0].github_url.as_deref(),
        Some("https://github.com/contract-organizer")
    );
    assert_eq!(event.organizers.len(), 1);
    assert_eq!(
        event.organizers[0].github_url.as_deref(),
        Some("https://github.com/contract-organizer")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_full_by_slug_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let event = db
        .get_event_full_by_slug(alliance_id(), "contract-group", "future-contract-event")
        .await?
        .expect("contract event should exist");

    assert_eq!(event.event_id, event_id());
    assert_eq!(event.name, "Future Contract Event");
    assert_eq!(event.sessions.len(), 1);
    assert_eq!(event.sponsors.len(), 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_purchase_summary_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let summary = db.get_event_purchase_summary(summary_purchase_id()).await?;

    assert_eq!(summary.amount_minor, 2500);
    assert_eq!(summary.currency_code, "USD");
    assert_eq!(summary.discount_amount_minor, 0);
    assert_eq!(summary.event_purchase_id, summary_purchase_id());
    assert_eq!(summary.event_ticket_type_id, paid_ticket_type_id());
    assert!(summary.hold_expires_at.is_some());
    assert_eq!(summary.status, EventPurchaseStatus::Pending);
    assert_eq!(summary.ticket_title, "Contract Paid Ticket");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_registration_questions_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let questions = db.get_event_registration_questions(alliance_id(), event_id()).await?;

    assert_eq!(questions.len(), 1);
    assert_eq!(questions[0].prompt, "Meal preference");
    assert_eq!(questions[0].options.len(), 1);
    assert_eq!(questions[0].options[0].label, "Vegetarian");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_summary_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let event = db.get_event_summary(alliance_id(), group_id(), event_id()).await?;

    assert_eq!(event.event_id, event_id());
    assert!(event.has_registration_questions);
    assert_eq!(event.kind, EventKind::Hybrid);
    assert_eq!(event.waitlist_count, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_summary_by_id_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let event = db.get_event_summary_by_id(alliance_id(), event_id()).await?;

    assert_eq!(event.event_id, event_id());
    assert_eq!(event.kind, EventKind::Hybrid);
    assert_eq!(event.name, "Future Contract Event");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_filters_options_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let options = db
        .get_filters_options(Some("contract-alliance".to_string()), Some(Entity::Events))
        .await?;

    assert_eq!(options.alliances.len(), 1);
    assert_eq!(options.alliances[0].value, "contract-alliance");
    assert!(!options.distance.is_empty());
    let event_category = options.event_category.expect("event categories should be present");
    assert_eq!(event_category.len(), 1);
    assert_eq!(event_category[0].name, "Conference");
    let groups = options.groups.expect("groups should be present");
    assert_eq!(groups.len(), 1);
    assert_eq!(groups[0].name, "Contract Group");
    let region = options.region.expect("regions should be present");
    assert_eq!(region.len(), 1);
    assert_eq!(region[0].name, "North America");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_full_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let group = db.get_group_full(alliance_id(), group_id()).await?;

    assert_eq!(
        group.alliance.ad_banner_link_url.as_deref(),
        Some("https://example.com/alliance-ad")
    );
    assert_eq!(
        group.alliance.ad_banner_url.as_deref(),
        Some("https://example.com/alliance-ad-banner.png")
    );
    assert_eq!(group.group_id, group_id());
    assert_eq!(group.organizers.len(), 1);
    assert_eq!(group.sponsors.len(), 1);
    assert_eq!(
        group.organizers[0].github_url.as_deref(),
        Some("https://github.com/contract-organizer")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_full_by_slug_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let group = db
        .get_group_full_by_slug(alliance_id(), "contract-group")
        .await?
        .expect("contract group should exist");

    assert_eq!(group.group_id, group_id());
    assert_eq!(group.name, "Contract Group");
    assert_eq!(group.organizers.len(), 1);
    assert_eq!(group.sponsors.len(), 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_past_events_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let events = db
        .get_group_past_events(
            alliance_id(),
            "contract-group",
            vec![EventKind::Virtual],
            10,
        )
        .await?;

    assert_eq!(events.len(), 1);
    assert_eq!(events[0].event_id, past_event_id());
    assert_eq!(events[0].kind, EventKind::Virtual);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_payment_recipient_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let payment_recipient = db
        .get_group_payment_recipient(alliance_id(), group_id())
        .await?
        .expect("contract group should have a payment recipient");

    assert_eq!(payment_recipient.provider, PaymentProvider::Stripe);
    assert_eq!(payment_recipient.recipient_id, "acct_contract_group");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_sponsor_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let sponsor = db.get_group_sponsor(group_id(), group_sponsor_id()).await?;

    assert_eq!(sponsor.group_sponsor_id, group_sponsor_id());
    assert_eq!(sponsor.name, "Contract Sponsor");
    assert!(sponsor.featured);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_stats_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let stats = db.get_group_stats(alliance_id(), group_id()).await?;

    assert_eq!(stats.attendees.total, 1);
    assert_eq!(stats.events.total, 2);
    assert_eq!(stats.members.total, 1);
    assert_eq!(stats.page_views.events.total_views, 2);
    assert_eq!(stats.page_views.group.total_views, 3);
    assert_eq!(stats.page_views.total_views, 5);
    assert_eq!(
        stats.reports.events.hosted_total + stats.reports.events.upcoming_total,
        2
    );
    assert_eq!(stats.reports.members.leaders_total, 1);
    assert!(stats.gamification.total_points >= 10);
    assert!(!stats.gamification.rules.is_empty());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_summary_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let group = db.get_group_summary(alliance_id(), group_id()).await?;

    assert_eq!(group.group_id, group_id());
    assert_eq!(group.alliance_name, "contract-alliance");
    assert!(group.region.is_some());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_upcoming_events_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let events = db
        .get_group_upcoming_events(alliance_id(), "contract-group", vec![EventKind::Hybrid], 10)
        .await?;

    assert_eq!(events.len(), 1);
    assert_eq!(events[0].event_id, event_id());
    assert_eq!(events[0].kind, EventKind::Hybrid);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_site_home_stats_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let stats = db.get_site_home_stats().await?;

    assert_eq!(stats.alliances, 1);
    assert_eq!(stats.events, 2);
    assert_eq!(stats.events_attendees, 1);
    assert_eq!(stats.groups, 1);
    assert_eq!(stats.groups_members, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_site_recently_added_groups_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let groups = db.get_site_recently_added_groups().await?;

    assert_eq!(groups.len(), 1);
    assert_eq!(groups[0].group_id, group_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_site_settings_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let settings = db.get_site_settings().await?;

    assert_eq!(
        settings.copyright_notice.as_deref(),
        Some("Copyright Contract Site")
    );
    assert_eq!(settings.site_id, site_id());
    assert_eq!(
        settings.theme.palette.get(&50).map(String::as_str),
        Some("#eff6ff")
    );
    assert_eq!(settings.theme.primary_color, "#0066cc");
    assert_eq!(settings.title, "Contract Site");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_site_stats_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let stats = db.get_site_stats().await?;

    assert_eq!(stats.attendees.total, 1);
    assert_eq!(stats.events.total, 2);
    assert_eq!(stats.groups.total, 1);
    assert_eq!(stats.members.total, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_site_upcoming_events_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let events = db.get_site_upcoming_events(vec![EventKind::Hybrid]).await?;

    assert_eq!(events.len(), 1);
    assert_eq!(events[0].event_id, event_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_user_by_email_for_external_auth_pre_registered_deserializes() -> Result<()>
{
    let db = contract_tests_db()?;
    let user = db
        .get_user_by_email_for_external_auth("PRE-REGISTERED.CONTRACT@example.com")
        .await?
        .expect("contract pre-registered user should exist");

    assert_eq!(user.user_id, pre_registered_id());
    assert_eq!(user.name, "");
    assert_eq!(user.registration_status, "pre-registered");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_user_by_id_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let user = db
        .get_user_by_id(&attendee_id())
        .await?
        .expect("contract attendee should exist");

    assert!(user.email_verified);
    assert_eq!(user.email, "attendee.contract@example.com");
    assert_eq!(
        user.github_url.as_deref(),
        Some("https://github.com/contract-attendee")
    );
    assert_eq!(user.user_id, attendee_id());
    assert_eq!(user.username, "contract-attendee");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_user_by_username_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let user = db
        .get_user_by_username("contract-organizer")
        .await?
        .expect("contract organizer should exist");

    assert_eq!(user.name, "Contract Organizer");
    assert_eq!(user.user_id, organizer_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_leave_event_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let outcome = db
        .leave_event(alliance_id(), mutation_event_id(), leaver_id())
        .await?;

    assert_eq!(outcome.left_status, EventAttendanceStatus::Attendee);
    assert!(outcome.promoted_user_ids.is_empty());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_cfs_submission_statuses_for_review_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let statuses = db.list_cfs_submission_statuses_for_review().await?;

    assert_eq!(statuses.len(), 4);
    assert_eq!(statuses[0].cfs_submission_status_id, "approved");
    assert_eq!(statuses[0].display_name, "Approved");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_alliances_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let alliances = db.list_alliances().await?;

    assert_eq!(alliances.len(), 1);
    assert_eq!(alliances[0].alliance_id, alliance_id());
    assert_eq!(alliances[0].name, "contract-alliance");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_alliance_audit_logs_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = AuditLogFilters {
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };
    let output = db.list_alliance_audit_logs(alliance_id(), &filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.logs.len(), 1);
    assert_eq!(output.logs[0].action, "group_payment_recipient_updated");
    assert_eq!(
        output.logs[0].actor_username.as_deref(),
        Some("contract-organizer")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_alliance_roles_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let roles = db.list_alliance_roles().await?;

    assert_eq!(roles.len(), 3);
    assert_eq!(roles[0].alliance_role_id, "admin");
    assert_eq!(roles[0].display_name, "Admin");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_alliance_team_members_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = AllianceTeamFilters {
        limit: Some(10),
        offset: Some(0),
    };
    let output = db.list_alliance_team_members(alliance_id(), &filters).await?;

    assert_eq!(output.total, 2);
    assert_eq!(output.members.len(), 2);
    assert!(output.members[0].accepted);
    assert_eq!(output.members[0].role, Some(AllianceRole::Admin));
    assert_eq!(output.members[0].user_id, organizer_id());
    assert!(!output.members[1].accepted);
    assert_eq!(output.members[1].user_id, waitlist_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_event_approved_cfs_submissions_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let submissions = db.list_event_approved_cfs_submissions(event_id()).await?;

    assert_eq!(submissions.len(), 1);
    assert_eq!(submissions[0].cfs_submission_id, cfs_submission_id());
    assert_eq!(submissions[0].session_proposal_id, session_proposal_id());
    assert_eq!(submissions[0].speaker_name, "Contract Attendee");
    assert_eq!(submissions[0].title, "Contract Rust Proposal");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_event_categories_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let categories = db.list_event_categories(alliance_id()).await?;

    assert_eq!(categories.len(), 1);
    assert_eq!(categories[0].name, "Conference");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_event_cfs_labels_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let labels = db.list_event_cfs_labels(event_id()).await?;

    assert_eq!(labels.len(), 1);
    assert_eq!(labels[0].color, "#DBEAFE");
    assert_eq!(labels[0].name, "track / backend");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_event_cfs_submissions_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = GroupCfsSubmissionsFilters {
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };
    let output = db.list_event_cfs_submissions(event_id(), &filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.submissions.len(), 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_event_kinds_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let kinds = db.list_event_kinds().await?;

    assert_eq!(kinds.len(), 3);
    assert_eq!(kinds[0].event_kind_id, "hybrid");
    assert_eq!(kinds[0].display_name, "Hybrid");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_audit_logs_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = AuditLogFilters {
        // Scope to the fixture action so refund mutation tests don't interfere.
        action: Some("group_payment_recipient_updated".to_string()),
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };
    let output = db.list_group_audit_logs(group_id(), &filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.logs.len(), 1);
    assert_eq!(output.logs[0].action, "group_payment_recipient_updated");
    assert_eq!(
        output.logs[0].actor_username.as_deref(),
        Some("contract-organizer")
    );
    assert_eq!(output.logs[0].resource_id, group_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_categories_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let categories = db.list_group_categories(alliance_id()).await?;

    assert_eq!(categories.len(), 1);
    assert_eq!(categories[0].name, "Technology");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_events_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = EventsListFilters {
        limit: Some(10),
        past_offset: Some(0),
        upcoming_offset: Some(0),

        ..Default::default()
    };
    let events = db.list_group_events(group_id(), &filters).await?;

    assert_eq!(events.past.total, 1);
    // Includes the regular upcoming event and the two upcoming test events.
    assert_eq!(events.upcoming.total, 3);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_members_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = GroupMembersFilters {
        limit: Some(10),
        offset: Some(0),
        query: None,
    };
    let output = db
        .list_group_members(group_id(), attendee_id(), false, &filters)
        .await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.members.len(), 1);
    assert_eq!(output.members[0].username, "contract-attendee");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_roles_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let roles = db.list_group_roles().await?;

    assert_eq!(roles.len(), 3);
    assert_eq!(roles[0].group_role_id, "admin");
    assert_eq!(roles[0].display_name, "Admin");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_sponsors_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = GroupSponsorsFilters {
        limit: Some(10),
        offset: Some(0),
    };
    let output = db.list_group_sponsors(group_id(), &filters, false).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.sponsors.len(), 1);
    assert_eq!(output.sponsors[0].group_sponsor_id, group_sponsor_id());
    assert_eq!(
        output.sponsors[0].website_url.as_deref(),
        Some("https://example.com/sponsor")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_team_members_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = GroupTeamFilters {
        limit: Some(10),
        offset: Some(0),
    };
    let output = db.list_group_team_members(group_id(), &filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.total_accepted, 1);
    assert_eq!(output.total_admins_accepted, 1);
    assert_eq!(output.members[0].role, Some(GroupRole::Admin));
    assert_eq!(output.members[0].user_id, organizer_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_regions_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let regions = db.list_regions(alliance_id()).await?;

    assert_eq!(regions.len(), 1);
    assert_eq!(regions[0].name, "North America");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_session_kinds_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let kinds = db.list_session_kinds().await?;

    assert_eq!(kinds.len(), 3);
    assert_eq!(kinds[0].session_kind_id, "hybrid");
    assert_eq!(kinds[0].display_name, "Hybrid");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_session_proposal_levels_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let levels = db.list_session_proposal_levels().await?;

    assert_eq!(levels.len(), 3);
    assert_eq!(levels[0].session_proposal_level_id, "advanced");
    assert_eq!(levels[0].display_name, "Advanced");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_audit_logs_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = AuditLogFilters {
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };
    let output = db.list_user_audit_logs(attendee_id(), &filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.logs.len(), 1);
    assert_eq!(output.logs[0].action, "event_attendee_invitation_rejected");
    assert_eq!(
        output.logs[0].actor_username.as_deref(),
        Some("contract-attendee")
    );
    assert_eq!(output.logs[0].resource_id, event_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_cfs_submissions_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = UserCfsSubmissionsFilters {
        limit: Some(10),
        offset: Some(0),
    };
    let output = db.list_user_cfs_submissions(attendee_id(), &filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.submissions.len(), 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_alliances_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let alliances = db.list_user_alliances(&organizer_id()).await?;

    assert_eq!(alliances.len(), 1);
    assert_eq!(alliances[0].alliance_id, alliance_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_alliance_team_invitations_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let invitations = db.list_user_alliance_team_invitations(waitlist_id()).await?;

    assert_eq!(invitations.len(), 1);
    assert_eq!(invitations[0].alliance_id, alliance_id());
    assert_eq!(invitations[0].alliance_name, "contract-alliance");
    assert_eq!(invitations[0].role, AllianceRole::Viewer);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_event_invitations_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let invitations = db.list_user_event_invitations(pre_registered_id()).await?;

    assert_eq!(invitations.len(), 1);
    assert_eq!(invitations[0].event_id, event_id());
    assert_eq!(invitations[0].event_name, "Future Contract Event");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_events_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = UserEventsFilters {
        limit: Some(10),
        offset: Some(0),
    };
    let output = db.list_user_events(attendee_id(), &filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.events.len(), 1);
    assert_eq!(
        output.events[0].attendance_status,
        Some(EventAttendanceStatus::Attendee)
    );
    assert!(output.events[0].can_complete_registration_questions());
    assert!(output.events[0].event.has_registration_questions);
    assert_eq!(output.events[0].registration_questions.len(), 1);
    assert!(!output.events[0].registration_questions_pending());
    let answers = output.events[0]
        .registration_answers
        .as_ref()
        .expect("contract event should include registration answers");
    assert_eq!(answers.answers.len(), 1);
    match &answers.answers[0].value {
        QuestionnaireAnswerValue::One(value) => {
            assert_eq!(value, "00000000-0000-0000-0000-00000000c072");
        }
        QuestionnaireAnswerValue::Many(_) => panic!("expected single-select answer"),
    }

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_group_team_invitations_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let invitations = db.list_user_group_team_invitations(attendee_id()).await?;

    assert_eq!(invitations.len(), 1);
    assert_eq!(invitations[0].alliance_name, "contract-alliance");
    assert_eq!(invitations[0].group_id, claim_group_id());
    assert_eq!(invitations[0].group_name, "Contract Meeting Claim Group");
    assert_eq!(invitations[0].role, GroupRole::Viewer);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_groups_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let output = db.list_user_groups(&organizer_id()).await?;

    assert_eq!(output.len(), 1);
    assert_eq!(output[0].alliance.alliance_id, alliance_id());
    assert_eq!(output[0].groups.len(), 2);
    assert_eq!(output[0].groups[0].group_id, group_id());
    assert_eq!(output[0].groups[1].group_id, claim_group_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_pending_session_proposal_co_speaker_invitations_deserializes()
-> Result<()> {
    let db = contract_tests_db()?;
    let invitations = db
        .list_user_pending_session_proposal_co_speaker_invitations(waitlist_id())
        .await?;

    assert_eq!(invitations.len(), 1);
    assert_eq!(
        invitations[0].session_proposal.session_proposal_id,
        co_speaker_proposal_id()
    );
    assert_eq!(
        invitations[0].session_proposal.title,
        "Contract Go Proposal"
    );
    assert_eq!(invitations[0].speaker_name, "Contract Attendee");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_session_proposals_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = SessionProposalsFilters {
        limit: Some(10),
        offset: Some(0),
    };
    let output = db.list_user_session_proposals(attendee_id(), &filters).await?;

    assert_eq!(output.total, 2);
    assert_eq!(output.session_proposals.len(), 2);
    assert_eq!(output.session_proposals[0].title, "Contract Go Proposal");
    assert!(
        output.session_proposals[0]
            .co_speaker
            .as_ref()
            .is_some_and(|co_speaker| co_speaker.user_id == waitlist_id())
    );
    assert_eq!(output.session_proposals[1].title, "Contract Rust Proposal");
    assert!(output.session_proposals[1].has_submissions);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_session_proposals_for_cfs_event_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let proposals = db
        .list_user_session_proposals_for_cfs_event(attendee_id(), event_id())
        .await?;

    assert_eq!(proposals.len(), 1);
    assert!(proposals[0].is_submitted);
    assert_eq!(proposals[0].session_proposal_id, session_proposal_id());
    assert_eq!(
        proposals[0].submission_status_id.as_deref(),
        Some("approved")
    );
    assert_eq!(proposals[0].title, "Contract Rust Proposal");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_prepare_event_checkout_purchase_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let input = PrepareEventCheckoutPurchaseInput {
        event_id: ticketed_event_id(),
        event_ticket_type_id: paid_ticket_type_id(),
        user_id: checkout_buyer_id(),

        configured_provider: Some(PaymentProvider::Stripe),
        discount_code: None,
        registration_answers: None,
    };
    let checkout = db.prepare_event_checkout_purchase(alliance_id(), &input).await?;

    assert_eq!(checkout.alliance_name, "contract-alliance");
    assert_eq!(checkout.event_id, ticketed_event_id());
    assert_eq!(checkout.event_slug, "contract-ticketed-event");
    assert_eq!(checkout.group_slug, "contract-group");
    assert_eq!(checkout.purchase.amount_minor, 2500);
    assert!(checkout.purchase.hold_expires_at.is_some());
    assert_eq!(checkout.purchase.status, EventPurchaseStatus::Pending);
    assert_eq!(checkout.purchase.ticket_title, "Contract Paid Ticket");
    assert_eq!(checkout.recipient.provider, PaymentProvider::Stripe);
    assert_eq!(checkout.recipient.recipient_id, "acct_contract_group");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_reconcile_event_purchase_for_checkout_session_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let result = db
        .reconcile_event_purchase_for_checkout_session(
            PaymentProvider::Stripe,
            "cs_contract_reconcile",
            Some("pi_contract_reconcile".to_string()),
        )
        .await?;

    let ReconcileEventPurchaseResult::Completed(purchase) = result else {
        panic!("reconciliation should complete the purchase");
    };
    assert_eq!(purchase.alliance_id, alliance_id());
    assert_eq!(purchase.event_id, ticketed_event_id());
    assert_eq!(purchase.user_id, reconcile_buyer_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_reject_event_refund_request_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let purchase = db
        .reject_event_refund_request(
            organizer_id(),
            group_id(),
            ticketed_event_id(),
            refund_reject_buyer_id(),
            Some("Rejected by contract test".to_string()),
        )
        .await?;

    assert_eq!(purchase.alliance_id, alliance_id());
    assert_eq!(purchase.event_id, ticketed_event_id());
    assert_eq!(purchase.user_id, refund_reject_buyer_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_event_attendees_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = SearchEventAttendeesFilters {
        event_id: event_id(),
        limit: Some(10),
        offset: Some(0),
        ts_query: None,
    };
    let output = db.search_event_attendees(group_id(), &filters).await?;

    assert_eq!(output.all_attendees_email_recipient_total, 1);
    assert_eq!(output.total, 2);
    assert_eq!(output.attendees.len(), 2);
    assert_eq!(output.attendees[0].user_id, attendee_id());
    assert_eq!(output.attendees[0].username, "contract-attendee");
    assert!(output.attendees[0].can_receive_attendee_email);
    assert!(output.attendees[0].checked_in);
    assert!(output.attendees[0].registration_answers.is_some());
    assert_eq!(
        output.attendees[1].email,
        "pre-registered.contract@example.com"
    );
    assert!(output.attendees[1].manually_invited);
    assert_eq!(output.attendees[1].name, None);
    assert_eq!(output.attendees[1].status, "invitation-pending");
    assert_eq!(output.attendees[1].user_id, pre_registered_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_event_invitation_requests_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = InvitationRequestsFilters {
        event_id: event_id(),

        limit: Some(10),
        offset: Some(0),
        ts_query: None,
    };
    let output = db.search_event_invitation_requests(group_id(), &filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.invitation_requests.len(), 1);
    assert_eq!(
        output.invitation_requests[0].invitation_request_status,
        EventInvitationRequestStatus::Pending
    );
    assert_eq!(output.invitation_requests[0].user_id, waitlist_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_event_waitlist_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = WaitlistFilters {
        event_id: event_id(),

        limit: Some(10),
        offset: Some(0),
        ts_query: None,
    };
    let output = db.search_event_waitlist(group_id(), &filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.waitlist.len(), 1);
    assert_eq!(output.waitlist[0].user_id, waitlist_id());
    assert_eq!(output.waitlist[0].username, "contract-waitlist");
    assert_eq!(output.waitlist[0].waitlist_position, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_events_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = SearchEventsFilters {
        alliance: vec!["contract-alliance".to_string()],

        date_from: Some("2099-01-01".to_string()),
        date_to: Some("2099-12-31".to_string()),
        include_bbox: Some(true),
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };
    let output = db.search_events(&filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.events.len(), 1);
    assert!(output.bbox.is_some());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_groups_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let filters = SearchGroupsFilters {
        alliance: vec!["contract-alliance".to_string()],

        include_bbox: Some(true),
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };
    let output = db.search_groups(&filters).await?;

    assert_eq!(output.total, 1);
    assert_eq!(output.groups.len(), 1);
    assert!(output.bbox.is_some());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_user_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let users = db.search_user("contract-att").await?;

    assert_eq!(users.len(), 1);
    assert_eq!(users[0].user_id, attendee_id());
    assert_eq!(users[0].username, "contract-attendee");
    assert_eq!(users[0].name.as_deref(), Some("Contract Attendee"));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_update_event_deserializes() -> Result<()> {
    let db = contract_tests_db()?;
    let starts_at = NaiveDate::from_ymd_opt(2099, 8, 1)
        .expect("date should be valid")
        .and_hms_opt(10, 0, 0)
        .expect("time should be valid");
    let ends_at = NaiveDate::from_ymd_opt(2099, 8, 1)
        .expect("date should be valid")
        .and_hms_opt(11, 0, 0)
        .expect("time should be valid");
    let event = EventUpdate {
        category_id: event_category_id(),
        description: "A mutation event updated by Rust database contract tests".to_string(),
        kind_id: "virtual".to_string(),
        name: "Contract Mutation Event".to_string(),
        timezone: "UTC".to_string(),

        capacity: Some(100),
        ends_at: Some(ends_at),
        starts_at: Some(starts_at),
        test_event: Some(true),

        ..Default::default()
    };
    let payload = event.to_db_payload()?;
    let promoted_user_ids = db
        .update_event(
            organizer_id(),
            group_id(),
            mutation_event_id(),
            &payload,
            &HashMap::new(),
        )
        .await?;

    assert!(promoted_user_ids.is_empty());

    Ok(())
}

// Helpers.

const ACTIVATION_ID: &str = "00000000-0000-0000-0000-00000000c045";
const ATTENDEE_ID: &str = "00000000-0000-0000-0000-00000000c042";
const AUTO_END_MEETING_ID: &str = "00000000-0000-0000-0000-00000000c0a3";
const CANCELEE_ID: &str = "00000000-0000-0000-0000-00000000c0e9";
const CFS_SUBMISSION_ID: &str = "00000000-0000-0000-0000-00000000c0c5";
const CHECKOUT_BUYER_ID: &str = "00000000-0000-0000-0000-00000000c0e1";
const CLAIM_GROUP_ID: &str = "00000000-0000-0000-0000-00000000c0a0";
const CO_SPEAKER_PROPOSAL_ID: &str = "00000000-0000-0000-0000-00000000c0c2";
const ALLIANCE_ID: &str = "00000000-0000-0000-0000-00000000c001";
const EVENT_CATEGORY_ID: &str = "00000000-0000-0000-0000-00000000c013";
const EVENT_ID: &str = "00000000-0000-0000-0000-00000000c031";
const FREE_BUYER_ID: &str = "00000000-0000-0000-0000-00000000c0e4";
const FREE_PURCHASE_ID: &str = "00000000-0000-0000-0000-00000000c0f3";
const GROUP_ID: &str = "00000000-0000-0000-0000-00000000c021";
const GROUP_SPONSOR_ID: &str = "00000000-0000-0000-0000-00000000c061";
const LEAVER_ID: &str = "00000000-0000-0000-0000-00000000c0e8";
const MUTATION_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c0d5";
const ORGANIZER_ID: &str = "00000000-0000-0000-0000-00000000c041";
const PAID_TICKET_TYPE_ID: &str = "00000000-0000-0000-0000-00000000c0d1";
const PAST_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c032";
const PRE_REGISTERED_ID: &str = "00000000-0000-0000-0000-00000000c044";
const RECONCILE_BUYER_ID: &str = "00000000-0000-0000-0000-00000000c0e3";
const REFUND_APPROVE_BUYER_ID: &str = "00000000-0000-0000-0000-00000000c0e6";
const REFUND_BEGIN_BUYER_ID: &str = "00000000-0000-0000-0000-00000000c0e5";
const REFUND_BEGIN_PURCHASE_ID: &str = "00000000-0000-0000-0000-00000000c0f4";
const REFUND_REJECT_BUYER_ID: &str = "00000000-0000-0000-0000-00000000c0e7";
const SESSION_PROPOSAL_ID: &str = "00000000-0000-0000-0000-00000000c0c1";
const SITE_ID: &str = "00000000-0000-0000-0000-00000000c0b1";
const SUMMARY_PURCHASE_ID: &str = "00000000-0000-0000-0000-00000000c0f1";
const SYNC_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c0a1";
const TICKETED_EVENT_ID: &str = "00000000-0000-0000-0000-00000000c0d0";
const WAITLIST_ID: &str = "00000000-0000-0000-0000-00000000c043";

fn activation_id() -> Uuid {
    parse_uuid(ACTIVATION_ID)
}

fn attendee_id() -> Uuid {
    parse_uuid(ATTENDEE_ID)
}

fn auto_end_meeting_id() -> Uuid {
    parse_uuid(AUTO_END_MEETING_ID)
}

fn cancelee_id() -> Uuid {
    parse_uuid(CANCELEE_ID)
}

fn cfs_submission_id() -> Uuid {
    parse_uuid(CFS_SUBMISSION_ID)
}

fn checkout_buyer_id() -> Uuid {
    parse_uuid(CHECKOUT_BUYER_ID)
}

fn claim_group_id() -> Uuid {
    parse_uuid(CLAIM_GROUP_ID)
}

fn co_speaker_proposal_id() -> Uuid {
    parse_uuid(CO_SPEAKER_PROPOSAL_ID)
}

fn alliance_id() -> Uuid {
    parse_uuid(ALLIANCE_ID)
}

fn contract_tests_db() -> Result<PgDB> {
    let port = env_or_default("OCG_DB_PORT", "5432")
        .parse()
        .context("OCG_DB_PORT must be a valid port number")?;

    let mut cfg = DbConfig::new();
    cfg.dbname = Some(env_or_default(
        "OCG_DB_NAME_TESTS_CONTRACT",
        "ocg_tests_contract",
    ));
    cfg.host = Some(env_or_default("OCG_DB_HOST", "localhost"));
    cfg.port = Some(port);
    cfg.user = Some(env_or_default("OCG_DB_USER", "postgres"));

    if let Ok(password) = env::var("OCG_DB_PASSWORD")
        && !password.is_empty()
    {
        cfg.password = Some(password);
    }

    let pool = cfg.create_pool(Some(Runtime::Tokio1), NoTls)?;
    Ok(PgDB::new(pool))
}

fn env_or_default(name: &str, default: &str) -> String {
    env::var(name).unwrap_or_else(|_| default.to_string())
}

fn event_category_id() -> Uuid {
    parse_uuid(EVENT_CATEGORY_ID)
}

fn event_id() -> Uuid {
    parse_uuid(EVENT_ID)
}

fn free_buyer_id() -> Uuid {
    parse_uuid(FREE_BUYER_ID)
}

fn free_purchase_id() -> Uuid {
    parse_uuid(FREE_PURCHASE_ID)
}

fn group_id() -> Uuid {
    parse_uuid(GROUP_ID)
}

fn group_sponsor_id() -> Uuid {
    parse_uuid(GROUP_SPONSOR_ID)
}

fn leaver_id() -> Uuid {
    parse_uuid(LEAVER_ID)
}

fn mutation_event_id() -> Uuid {
    parse_uuid(MUTATION_EVENT_ID)
}

fn organizer_id() -> Uuid {
    parse_uuid(ORGANIZER_ID)
}

fn paid_ticket_type_id() -> Uuid {
    parse_uuid(PAID_TICKET_TYPE_ID)
}

fn parse_uuid(value: &str) -> Uuid {
    Uuid::parse_str(value).expect("contract fixture UUID should be valid")
}

fn past_event_id() -> Uuid {
    parse_uuid(PAST_EVENT_ID)
}

fn reconcile_buyer_id() -> Uuid {
    parse_uuid(RECONCILE_BUYER_ID)
}

fn refund_approve_buyer_id() -> Uuid {
    parse_uuid(REFUND_APPROVE_BUYER_ID)
}

fn refund_begin_buyer_id() -> Uuid {
    parse_uuid(REFUND_BEGIN_BUYER_ID)
}

fn refund_begin_purchase_id() -> Uuid {
    parse_uuid(REFUND_BEGIN_PURCHASE_ID)
}

fn refund_reject_buyer_id() -> Uuid {
    parse_uuid(REFUND_REJECT_BUYER_ID)
}

fn session_proposal_id() -> Uuid {
    parse_uuid(SESSION_PROPOSAL_ID)
}

fn pre_registered_id() -> Uuid {
    parse_uuid(PRE_REGISTERED_ID)
}

fn site_id() -> Uuid {
    parse_uuid(SITE_ID)
}

fn summary_purchase_id() -> Uuid {
    parse_uuid(SUMMARY_PURCHASE_ID)
}

fn sync_event_id() -> Uuid {
    parse_uuid(SYNC_EVENT_ID)
}

fn ticketed_event_id() -> Uuid {
    parse_uuid(TICKETED_EVENT_ID)
}

fn waitlist_id() -> Uuid {
    parse_uuid(WAITLIST_ID)
}
