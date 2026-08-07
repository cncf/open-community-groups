//! DB trait mock implementation for testing.

use std::collections::HashMap;

use anyhow::Result;
use async_trait::async_trait;
use mockall::mock;
use uuid::Uuid;

mock! {
    /// Mock `DB` struct for testing purposes, implementing the DB traits.
    pub(crate) DB {}

    #[async_trait]
    impl crate::db::DB for DB {
        async fn begin(&self) -> Result<crate::db::DynDBUnitOfWork>;
    }

    #[async_trait]
    impl crate::db::DBUnitOfWork for DB {
        async fn commit(self: Box<Self>) -> Result<()>;
        async fn rollback(self: Box<Self>) -> Result<()>;
    }

    #[async_trait]
    impl crate::db::badges::DBBadges for DB {
        async fn claim_badge_award_job(
            &self,
        ) -> Result<Option<crate::db::badges::ClaimedBadgeAwardJob>>;
        async fn cleanup_badge_award_jobs(
            &self,
            retention: std::time::Duration,
        ) -> Result<usize>;
        async fn process_badge_award_job_batch(
            &self,
            badge_award_job_id: Uuid,
            claim_id: Uuid,
            batch_size: usize,
            rate_limit: usize,
        ) -> Result<crate::db::badges::BadgeAwardBatchOutcome>;
        async fn record_badge_award_job_failure(
            &self,
            badge_award_job_id: Uuid,
            claim_id: Uuid,
            error: String,
            max_failures: usize,
        ) -> Result<bool>;
        async fn recover_stale_badge_award_jobs(
            &self,
            max_failures: usize,
            processing_timeout: std::time::Duration,
        ) -> Result<usize>;
    }

    #[async_trait]
    impl crate::db::auth::DBAuth for DB {
        async fn activate_pre_registered_user_email_password(
            &self,
            user_summary: &crate::auth::UserSummary,
            verification: &crate::db::auth::EmailVerificationNotification,
        ) -> Result<Option<(crate::auth::User, Uuid)>>;
        async fn activate_pre_registered_user_external_provider(
            &self,
            user_id: &Uuid,
            user_summary: &crate::auth::UserSummary,
        ) -> Result<crate::auth::User>;
        async fn create_session(
            &self,
            record: &axum_login::tower_sessions::session::Record,
        ) -> Result<()>;
        async fn delete_session(
            &self,
            session_id: &axum_login::tower_sessions::session::Id,
        ) -> Result<()>;
        async fn get_session(
            &self,
            session_id: &axum_login::tower_sessions::session::Id,
        ) -> Result<Option<axum_login::tower_sessions::session::Record>>;
        async fn get_user_by_email_for_external_auth(
            &self,
            email: &str,
        ) -> Result<Option<crate::auth::User>>;
        async fn get_user_by_id(&self, user_id: &Uuid) -> Result<Option<crate::auth::User>>;
        async fn get_user_by_linuxfoundation_identity_for_external_auth(
            &self,
            issuer: &str,
            subject: &str,
        ) -> Result<Option<crate::auth::User>>;
        async fn get_user_by_username(
            &self,
            username: &str,
        ) -> Result<Option<crate::auth::User>>;
        async fn get_user_password(&self, user_id: &Uuid) -> Result<Option<String>>;
        async fn group_belongs_to_community(
            &self,
            community_id: &Uuid,
            group_id: &Uuid,
        ) -> Result<bool>;
        async fn sign_up_user(
            &self,
            user_summary: &crate::auth::UserSummary,
            email_verified: bool,
            verification: Option<crate::db::auth::EmailVerificationNotification>,
        ) -> Result<(crate::auth::User, Option<Uuid>)>;
        async fn update_session(
            &self,
            record: &axum_login::tower_sessions::session::Record,
        ) -> Result<()>;
        async fn update_user_details(
            &self,
            actor_user_id: &Uuid,
            user: &crate::templates::auth::UserDetails,
        ) -> Result<()>;
        async fn update_user_external_auth(
            &self,
            user_id: &Uuid,
            user_summary: &crate::auth::UserSummary,
        ) -> Result<crate::auth::User>;
        async fn update_user_password(
            &self,
            actor_user_id: &Uuid,
            new_password: &str,
        ) -> Result<()>;
        async fn update_user_provider(
            &self,
            user_id: &Uuid,
            provider: &crate::types::user::UserProvider,
        ) -> Result<()>;
        async fn user_has_community_permission(
            &self,
            community_id: &Uuid,
            user_id: &Uuid,
            permission: crate::types::permissions::CommunityPermission,
        ) -> Result<bool>;
        async fn user_has_group_permission(
            &self,
            community_id: &Uuid,
            group_id: &Uuid,
            user_id: &Uuid,
            permission: crate::types::permissions::GroupPermission,
        ) -> Result<bool>;
        async fn verify_email(&self, code: &Uuid) -> Result<()>;
    }

    #[async_trait]
    impl crate::db::common::DBCommon for DB {
        async fn get_badge_status_list(
            &self,
            badge_status_list_id: Uuid,
        ) -> Result<Option<crate::types::badges::BadgeStatusList>>;
        async fn get_community_full(
            &self,
            community_id: Uuid,
        ) -> Result<crate::types::community::CommunityFull>;
        async fn get_community_summary(
            &self,
            community_id: Uuid,
        ) -> Result<crate::types::community::CommunitySummary>;
        async fn get_event_full(
            &self,
            community_id: Uuid,
            group_id: Uuid,
            event_id: Uuid,
        )
            -> Result<crate::types::event::EventFull>;
        async fn get_event_summary(
            &self,
            community_id: Uuid,
            group_id: Uuid,
            event_id: Uuid,
        )
            -> Result<crate::types::event::EventSummary>;
        async fn list_event_cfs_labels(&self, event_id: Uuid) -> Result<Vec<crate::types::event::EventCfsLabel>>;
        async fn get_group_full(
            &self,
            community_id: Uuid,
            group_id: Uuid,
        )
            -> Result<crate::types::group::GroupFull>;
        async fn get_group_summary(
            &self,
            community_id: Uuid,
            group_id: Uuid,
        )
            -> Result<crate::types::group::GroupSummary>;
        async fn get_public_user_badge(
            &self,
            user_badge_id: Uuid,
        ) -> Result<Option<crate::types::badges::UserBadge>>;
        async fn list_timezones(&self) -> Result<Vec<String>>;
        async fn list_user_public_badges(
            &self,
            limit: usize,
            offset: usize,
            username: &str,
        ) -> Result<Vec<crate::types::badges::PublicUserBadge>>;
        async fn search_events(
            &self,
            filters: &crate::types::search::SearchEventsFilters,
        ) -> Result<crate::db::common::SearchEventsOutput>;
        async fn search_groups(
            &self,
            filters: &crate::types::search::SearchGroupsFilters,
        ) -> Result<crate::db::common::SearchGroupsOutput>;
    }

    #[async_trait]
    impl crate::db::community::DBCommunity for DB {
        async fn get_community_id_by_name(&self, name: &str) -> Result<Option<Uuid>>;
        async fn get_community_name_by_id(&self, community_id: Uuid) -> Result<Option<String>>;
        async fn get_community_recently_added_groups(
            &self,
            community_id: Uuid,
        ) -> Result<Vec<crate::types::group::GroupSummary>>;
        async fn get_community_site_stats(
            &self,
            community_id: Uuid,
        ) -> Result<crate::templates::community::Stats>;
        async fn get_community_upcoming_events(
            &self,
            community_id: Uuid,
            event_kinds: Vec<crate::types::event::EventKind>,
        ) -> Result<Vec<crate::types::event::EventSummary>>;
    }

    impl crate::db::dashboard::DBDashboard for DB {}

    #[async_trait]
    impl crate::db::dashboard::common::DBDashboardCommon for DB {
        async fn group_has_active_subgroups(
            &self,
            community_id: Uuid,
            group_id: Uuid,
        ) -> Result<bool>;
        async fn group_has_child_links(
            &self,
            community_id: Uuid,
            group_id: Uuid,
        ) -> Result<bool>;
        async fn list_group_parent_options(
            &self,
            community_id: Uuid,
            user_id: Uuid,
            group_id: Option<Uuid>,
        ) -> Result<Vec<crate::types::group::GroupParentOption>>;
        async fn search_user(
            &self,
            query: &str,
        ) -> Result<Vec<crate::db::dashboard::common::User>>;
        async fn update_group(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            group_id: Uuid,
            group: &crate::templates::dashboard::community::groups::Group,
        ) -> Result<()>;
    }

    #[async_trait]
    impl crate::db::dashboard::community::DBDashboardCommunity for DB {
        async fn activate_group(&self, actor_user_id: Uuid, community_id: Uuid, group_id: Uuid) -> Result<()>;
        async fn add_community_team_member(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            user_id: Uuid,
            role: &crate::types::community::CommunityRole,
        ) -> Result<()>;
        async fn add_event_category(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            event_category: &crate::templates::dashboard::community::event_categories::EventCategoryInput,
        ) -> Result<Uuid>;
        async fn add_group(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            group: &crate::templates::dashboard::community::groups::Group,
        ) -> Result<Uuid>;
        async fn add_group_category(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            group_category: &crate::templates::dashboard::community::group_categories::GroupCategoryInput,
        ) -> Result<Uuid>;
        async fn add_region(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            region: &crate::templates::dashboard::community::regions::RegionInput,
        ) -> Result<Uuid>;
        async fn deactivate_group(&self, actor_user_id: Uuid, community_id: Uuid, group_id: Uuid)
            -> Result<()>;
        async fn delete_community_team_member(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            user_id: Uuid,
        ) -> Result<()>;
        async fn delete_event_category(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            event_category_id: Uuid,
        ) -> Result<()>;
        async fn delete_group(&self, actor_user_id: Uuid, community_id: Uuid, group_id: Uuid) -> Result<()>;
        async fn delete_group_category(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            group_category_id: Uuid,
        ) -> Result<()>;
        async fn delete_region(&self, actor_user_id: Uuid, community_id: Uuid, region_id: Uuid) -> Result<()>;
        async fn get_community_stats(
            &self,
            community_id: Uuid,
        ) -> Result<crate::templates::dashboard::community::analytics::CommunityDashboardStats>;
        async fn list_community_audit_logs(
            &self,
            community_id: Uuid,
            filters: &crate::templates::dashboard::audit::AuditLogFilters,
        ) -> Result<crate::templates::dashboard::audit::AuditLogsOutput>;
        async fn list_community_team_members(
            &self,
            community_id: Uuid,
            filters: &crate::templates::dashboard::community::team::CommunityTeamFilters,
        ) -> Result<crate::templates::dashboard::community::team::CommunityTeamOutput>;
        async fn list_community_roles(
            &self,
        ) -> Result<Vec<crate::types::community::CommunityRoleSummary>>;
        async fn list_group_categories(
            &self,
            community_id: Uuid,
        ) -> Result<Vec<crate::types::group::GroupCategory>>;
        async fn list_regions(
            &self,
            community_id: Uuid,
        ) -> Result<Vec<crate::types::group::GroupRegion>>;
        async fn list_user_communities(
            &self,
            user_id: &Uuid,
        ) -> Result<Vec<crate::types::community::CommunitySummary>>;
        async fn update_community(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            community: &crate::templates::dashboard::community::settings::CommunityUpdate,
        ) -> Result<()>;
        async fn update_community_team_member_role(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            user_id: Uuid,
            role: &crate::types::community::CommunityRole,
        ) -> Result<()>;
        async fn update_event_category(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            event_category_id: Uuid,
            event_category: &crate::templates::dashboard::community::event_categories::EventCategoryInput,
        ) -> Result<()>;
        async fn update_group_category(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            group_category_id: Uuid,
            group_category: &crate::templates::dashboard::community::group_categories::GroupCategoryInput,
        ) -> Result<()>;
        async fn update_region(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            region_id: Uuid,
            region: &crate::templates::dashboard::community::regions::RegionInput,
        ) -> Result<()>;
    }

    #[async_trait]
    impl crate::db::dashboard::group::DBDashboardGroup for DB {
        async fn accept_event_invitation_request(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            event_id: Uuid,
            user_id: Uuid,
            event_ticket_type_id: Option<Uuid>,
            payment_provider: Option<crate::types::payments::PaymentProvider>,
        ) -> Result<crate::db::dashboard::group::EventAdmissionAllocationResult>;
        async fn add_badge(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            group_id: Uuid,
            badge: &crate::types::badges::BadgeInput,
        ) -> Result<()>;
        async fn add_badge_artwork(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            group_id: Uuid,
            file_name: &str,
        ) -> Result<()>;
        async fn add_event(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            event: &serde_json::Value,
            cfg_max_participants: &HashMap<crate::services::meetings::MeetingProvider, i32>,
            payment_provider: Option<crate::types::payments::PaymentProvider>,
        ) -> Result<Uuid>;
        async fn add_event_series(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            events: &[serde_json::Value],
            recurrence: &serde_json::Value,
            cfg_max_participants: &HashMap<crate::services::meetings::MeetingProvider, i32>,
            payment_provider: Option<crate::types::payments::PaymentProvider>,
        ) -> Result<Vec<Uuid>>;
        async fn add_group_sponsor(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            sponsor: &crate::templates::dashboard::group::sponsors::Sponsor,
        ) -> Result<Uuid>;
        async fn add_group_team_member(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            user_id: Uuid,
            role: &crate::types::group::GroupRole,
        ) -> Result<()>;
        async fn award_badge(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            group_id: Uuid,
            input: &crate::types::badges::BadgeAwardInput,
        ) -> Result<crate::types::badges::AwardBadgeOutcome>;
        async fn cancel_event(&self, actor_user_id: Uuid, group_id: Uuid, event_id: Uuid) -> Result<()>;
        async fn cancel_event_admission_offer(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            admission_offer_id: Uuid,
            payment_provider: Option<crate::types::payments::PaymentProvider>,
        ) -> Result<crate::types::event::EventEnrollmentReconciliationOutcome>;
        async fn cancel_event_attendee_attendance(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            event_id: Uuid,
            user_id: Uuid,
            payment_provider: Option<crate::types::payments::PaymentProvider>,
        ) -> Result<crate::types::event::EventLeaveOutcome>;
        async fn cancel_event_series_events(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            event_ids: &[Uuid],
        ) -> Result<()>;
        async fn delete_badge(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            group_id: Uuid,
            badge_id: Uuid,
        ) -> Result<()>;
        async fn delete_badge_artwork(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            group_id: Uuid,
            badge_artwork_id: Uuid,
        ) -> Result<()>;
        async fn delete_event(&self, actor_user_id: Uuid, group_id: Uuid, event_id: Uuid) -> Result<()>;
        async fn delete_event_series_events(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            event_ids: &[Uuid],
        ) -> Result<()>;
        async fn delete_group_sponsor(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            group_sponsor_id: Uuid,
        ) -> Result<()>;
        async fn delete_group_team_member(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            user_id: Uuid,
        ) -> Result<()>;
        async fn get_cfs_submission_notification_data(
            &self,
            event_id: Uuid,
            cfs_submission_id: Uuid,
        ) -> Result<crate::templates::dashboard::group::submissions::CfsSubmissionNotificationData>;
        async fn get_event_summary_dashboard(
            &self,
            community_id: Uuid,
            group_id: Uuid,
            event_id: Uuid,
        ) -> Result<crate::types::event::EventSummary>;
        async fn get_group_payment_recipient(
            &self,
            community_id: Uuid,
            group_id: Uuid,
        ) -> Result<Option<crate::types::payments::GroupPaymentRecipient>>;
        async fn get_group_sponsor(
            &self,
            group_id: Uuid,
            group_sponsor_id: Uuid,
        ) -> Result<crate::types::group::GroupSponsor>;
        async fn get_group_stats(
            &self,
            community_id: Uuid,
            group_id: Uuid,
            include_subgroups: bool,
        ) -> Result<crate::templates::dashboard::group::analytics::GroupDashboardStats>;
        async fn invite_event_attendee(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            event_id: Uuid,
            invitation: &crate::db::dashboard::group::EventAttendeeInvitationInput,
            payment_provider: Option<crate::types::payments::PaymentProvider>,
        ) -> Result<crate::db::dashboard::group::EventAdmissionAllocationResult>;
        async fn list_awarded_badges(
            &self,
            group_id: Uuid,
            filters: &crate::types::badges::AwardedBadgesFilters,
        ) -> Result<crate::types::badges::GroupAwardedBadges>;
        async fn list_badge_artwork(
            &self,
            group_id: Uuid,
        ) -> Result<Vec<crate::types::badges::BadgeArtwork>>;
        async fn list_badges(
            &self,
            group_id: Uuid,
            filters: &crate::types::badges::BadgeFilters,
        ) -> Result<crate::types::badges::GroupBadges>;
        async fn list_cfs_submission_statuses_for_review(
            &self,
        ) -> Result<Vec<crate::templates::dashboard::group::events::CfsSubmissionStatus>>;
        async fn list_community_admin_ids(
            &self,
            community_id: Uuid,
        ) -> Result<Vec<Uuid>>;
        async fn list_event_attendees_ids(
            &self,
            group_id: Uuid,
            event_id: Uuid,
            checked_in_only: bool,
        ) -> Result<Vec<Uuid>>;
        async fn list_event_categories(
            &self,
            community_id: Uuid,
        ) -> Result<Vec<crate::types::event::EventCategory>>;
        async fn list_event_approved_cfs_submissions(
            &self,
            event_id: Uuid,
        ) -> Result<Vec<crate::templates::dashboard::group::events::ApprovedSubmissionSummary>>;
        async fn list_event_cfs_submissions(
            &self,
            event_id: Uuid,
            filters: &crate::templates::dashboard::group::submissions::CfsSubmissionsFilters,
        ) -> Result<crate::templates::dashboard::group::submissions::CfsSubmissionsOutput>;
        async fn list_event_kinds(&self)
            -> Result<Vec<crate::types::event::EventKindSummary>>;
        async fn list_event_series_cancelable_event_ids(
            &self,
            group_id: Uuid,
            event_id: Uuid,
        ) -> Result<Vec<Uuid>>;
        async fn list_event_series_event_ids(
            &self,
            group_id: Uuid,
            event_id: Uuid,
        ) -> Result<Vec<Uuid>>;
        async fn list_event_series_publishable_event_ids(
            &self,
            group_id: Uuid,
            event_id: Uuid,
        ) -> Result<Vec<Uuid>>;
        async fn list_event_waitlist_ids(
            &self,
            group_id: Uuid,
            event_id: Uuid,
        ) -> Result<Vec<Uuid>>;
        async fn list_group_audit_logs(
            &self,
            group_id: Uuid,
            filters: &crate::templates::dashboard::audit::AuditLogFilters,
        ) -> Result<crate::templates::dashboard::audit::AuditLogsOutput>;
        async fn list_group_events(
            &self,
            group_id: Uuid,
            filters: &crate::templates::dashboard::group::events::EventsListFilters,
        ) -> Result<crate::templates::dashboard::group::events::GroupEvents>;
        async fn list_group_members(
            &self,
            group_id: Uuid,
            filters: &crate::templates::dashboard::group::members::GroupMembersFilters,
        ) -> Result<crate::templates::dashboard::group::members::GroupMembersOutput>;
        async fn list_group_members_ids(
            &self,
            group_id: Uuid,
        ) -> Result<Vec<Uuid>>;
        async fn list_group_refunds(
            &self,
            group_id: Uuid,
            filters: &crate::templates::dashboard::group::refunds::RefundsFilters,
        ) -> Result<crate::templates::dashboard::group::refunds::RefundsOutput>;
        async fn list_group_roles(&self)
            -> Result<Vec<crate::types::group::GroupRoleSummary>>;
        async fn list_group_sponsors(
            &self,
            group_id: Uuid,
            filters: &crate::templates::dashboard::group::sponsors::GroupSponsorsFilters,
            full_list: bool,
        ) -> Result<crate::templates::dashboard::group::sponsors::GroupSponsorsOutput>;
        async fn list_group_team_members(
            &self,
            group_id: Uuid,
            filters: &crate::templates::dashboard::group::team::GroupTeamFilters,
        ) -> Result<crate::templates::dashboard::group::team::GroupTeamOutput>;
        async fn list_group_team_members_ids(
            &self,
            group_id: Uuid,
        ) -> Result<Vec<Uuid>>;
        async fn list_payment_currency_codes(&self) -> Result<Vec<String>>;
        async fn list_session_kinds(&self)
            -> Result<Vec<crate::types::event::SessionKindSummary>>;
        async fn list_user_groups(
            &self,
            user_id: &Uuid,
        ) -> Result<Vec<crate::templates::dashboard::group::home::UserGroupsByCommunity>>;
        async fn lock_events_for_cancellation(
            &self,
            group_id: Uuid,
            event_ids: &[Uuid],
        ) -> Result<()>;
        async fn manual_check_in_event(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            event_id: Uuid,
            user_id: Uuid,
        ) -> Result<()>;
        async fn publish_event(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            event_id: Uuid,
            payment_provider: Option<crate::types::payments::PaymentProvider>,
        ) -> Result<()>;
        async fn publish_event_series_events(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            event_ids: &[Uuid],
            payment_provider: Option<crate::types::payments::PaymentProvider>,
        ) -> Result<()>;
        async fn reject_event_invitation_request(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            event_id: Uuid,
            user_id: Uuid,
        ) -> Result<()>;
        async fn resolve_event_custom_notification_recipient_ids(
            &self,
            group_id: Uuid,
            event_id: Uuid,
            recipient_scope: &str,
            requested_user_ids: Option<Vec<Uuid>>,
        ) -> Result<Vec<Uuid>>;
        async fn revoke_group_user_badge(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            group_id: Uuid,
            user_badge_id: Uuid,
            reason: &str,
        ) -> Result<()>;
        async fn search_event_attendees(
            &self,
            group_id: Uuid,
            event_id: Uuid,
            filters: &crate::templates::dashboard::group::attendees::AttendeesFilters,
        ) -> Result<crate::templates::dashboard::group::attendees::AttendeesOutput>;
        async fn search_event_invitation_requests(
            &self,
            group_id: Uuid,
            event_id: Uuid,
            filters: &crate::templates::dashboard::group::invitation_requests::InvitationRequestsFilters,
        ) -> Result<crate::templates::dashboard::group::invitation_requests::InvitationRequestsOutput>;
        async fn search_event_waitlist(
            &self,
            group_id: Uuid,
            event_id: Uuid,
            filters: &crate::templates::dashboard::group::waitlist::WaitlistFilters,
        ) -> Result<crate::templates::dashboard::group::waitlist::WaitlistOutput>;
        async fn unpublish_event(&self, actor_user_id: Uuid, group_id: Uuid, event_id: Uuid)
            -> Result<()>;
        async fn unpublish_event_series_events(&self, actor_user_id: Uuid, group_id: Uuid, event_ids: &[Uuid])
            -> Result<()>;
        async fn update_badge(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            group_id: Uuid,
            badge_id: Uuid,
            badge: &crate::types::badges::BadgeInput,
        ) -> Result<()>;
        async fn update_cfs_submission(
            &self,
            reviewer_id: Uuid,
            event_id: Uuid,
            cfs_submission_id: Uuid,
            submission: &crate::templates::dashboard::group::submissions::CfsSubmissionUpdate,
        ) -> Result<bool>;
        async fn update_event(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            event_id: Uuid,
            event: &serde_json::Value,
            cfg_max_participants: &HashMap<crate::services::meetings::MeetingProvider, i32>,
            payment_provider: Option<crate::types::payments::PaymentProvider>,
        ) -> Result<bool>;
        async fn update_group_sponsor(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            group_sponsor_id: Uuid,
            sponsor: &crate::templates::dashboard::group::sponsors::Sponsor,
        ) -> Result<()>;
        async fn update_group_sponsor_featured(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            group_sponsor_id: Uuid,
            featured: bool,
        ) -> Result<()>;
        async fn update_group_team_member_role(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            user_id: Uuid,
            role: &crate::types::group::GroupRole,
        ) -> Result<()>;
    }

    #[async_trait]
    impl crate::db::dashboard::user::DBDashboardUser for DB {
        async fn accept_community_team_invitation(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
        ) -> Result<()>;
        async fn accept_group_team_invitation(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
        ) -> Result<()>;
        async fn accept_session_proposal_co_speaker_invitation(
            &self,
            actor_user_id: Uuid,
            session_proposal_id: Uuid,
        ) -> Result<()>;
        async fn add_session_proposal(
            &self,
            actor_user_id: Uuid,
            session_proposal: &crate::templates::dashboard::user::session_proposals::SessionProposalInput,
        ) -> Result<Uuid>;
        async fn decline_event_admission_offer(
            &self,
            actor_user_id: Uuid,
            admission_offer_id: Uuid,
            payment_provider: Option<crate::types::payments::PaymentProvider>,
        ) -> Result<crate::types::event::EventEnrollmentReconciliationOutcome>;
        async fn delete_session_proposal(
            &self,
            actor_user_id: Uuid,
            session_proposal_id: Uuid,
        ) -> Result<()>;
        async fn get_session_proposal_co_speaker_user_id(
            &self,
            user_id: Uuid,
            session_proposal_id: Uuid,
        ) -> Result<Option<crate::db::dashboard::user::SessionProposalCoSpeakerUser>>;
        async fn get_user_badge(
            &self,
            user_id: Uuid,
            user_badge_id: Uuid,
        ) -> Result<Option<crate::types::badges::UserBadge>>;
        async fn list_session_proposal_levels(
            &self,
        ) -> Result<Vec<crate::templates::dashboard::user::session_proposals::SessionProposalLevel>>;
        async fn list_user_audit_logs(
            &self,
            actor_user_id: Uuid,
            filters: &crate::templates::dashboard::audit::AuditLogFilters,
        ) -> Result<crate::templates::dashboard::audit::AuditLogsOutput>;
        async fn list_user_badges(
            &self,
            user_id: Uuid,
        ) -> Result<Vec<crate::types::badges::UserBadge>>;
        async fn list_user_cfs_submissions(
            &self,
            user_id: Uuid,
            filters: &crate::templates::dashboard::user::submissions::CfsSubmissionsFilters,
        ) -> Result<crate::templates::dashboard::user::submissions::CfsSubmissionsOutput>;
        async fn list_user_community_team_invitations(
            &self,
            user_id: Uuid,
        ) -> Result<Vec<
            crate::templates::dashboard::user::invitations::CommunityTeamInvitation,
        >>;
        async fn list_user_dashboard_groups(
            &self,
            user_id: Uuid,
            filters: &crate::templates::dashboard::user::groups::UserGroupsFilters,
        ) -> Result<crate::templates::dashboard::user::groups::UserGroupsOutput>;
        async fn list_user_event_invitations(
            &self,
            user_id: Uuid,
        ) -> Result<Vec<
            crate::templates::dashboard::user::invitations::EventInvitation,
        >>;
        async fn list_user_events(
            &self,
            user_id: Uuid,
            filters: &crate::templates::dashboard::user::events::UserEventsFilters,
        ) -> Result<crate::templates::dashboard::user::events::UserEventsOutput>;
        async fn list_user_group_team_invitations(
            &self,
            user_id: Uuid,
        ) -> Result<Vec<
            crate::templates::dashboard::user::invitations::GroupTeamInvitation,
        >>;
        async fn list_user_pending_session_proposal_co_speaker_invitations(
            &self,
            user_id: Uuid,
        ) -> Result<Vec<
            crate::templates::dashboard::user::session_proposals::PendingCoSpeakerInvitation,
        >>;
        async fn list_user_session_proposals(
            &self,
            user_id: Uuid,
            filters: &crate::templates::dashboard::user::session_proposals::SessionProposalsFilters,
        ) -> Result<crate::templates::dashboard::user::session_proposals::SessionProposalsOutput>;
        async fn refresh_user_badge_identity(
            &self,
            user_id: Uuid,
            user_badge_id: Uuid,
        ) -> Result<crate::types::badges::UserBadgeIdentity>;
        async fn reject_community_team_invitation(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
        ) -> Result<()>;
        async fn reject_group_team_invitation(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
        ) -> Result<()>;
        async fn reject_session_proposal_co_speaker_invitation(
            &self,
            actor_user_id: Uuid,
            session_proposal_id: Uuid,
        ) -> Result<()>;
        async fn resubmit_cfs_submission(
            &self,
            actor_user_id: Uuid,
            cfs_submission_id: Uuid,
        ) -> Result<()>;
        async fn revoke_user_badge(
            &self,
            actor_user_id: Uuid,
            user_badge_id: Uuid,
        ) -> Result<()>;
        async fn submit_event_registration_answers(
            &self,
            actor_user_id: Uuid,
            community_id: Uuid,
            event_id: Uuid,
            registration_answers: &crate::types::questionnaire::QuestionnaireAnswers,
        ) -> Result<()>;
        async fn update_session_proposal(
            &self,
            actor_user_id: Uuid,
            session_proposal_id: Uuid,
            session_proposal: &crate::templates::dashboard::user::session_proposals::SessionProposalInput,
        ) -> Result<()>;
        async fn update_user_badge_listing(
            &self,
            actor_user_id: Uuid,
            user_badge_id: Uuid,
            is_listed: bool,
        ) -> Result<()>;
        async fn update_user_badges_order(
            &self,
            actor_user_id: Uuid,
            user_badge_ids: &[Uuid],
        ) -> Result<()>;
        async fn withdraw_cfs_submission(
            &self,
            actor_user_id: Uuid,
            cfs_submission_id: Uuid,
        ) -> Result<()>;
    }

    #[async_trait]
    impl crate::db::event::DBEvent for DB {
        async fn add_cfs_submission(
            &self,
            community_id: Uuid,
            event_id: Uuid,
            user_id: Uuid,
            session_proposal_id: Uuid,
            label_ids: &[Uuid],
        ) -> Result<Uuid>;
        async fn attend_event(
            &self,
            community_id: Uuid,
            event_id: Uuid,
            user_id: Uuid,
            registration_answers: Option<crate::types::questionnaire::QuestionnaireAnswers>,
            event_ticket_type_id: Option<Uuid>,
        ) -> Result<crate::db::event::AttendEventResult>;
        async fn check_in_event(
            &self,
            community_id: Uuid,
            event_id: Uuid,
            user_id: Uuid,
            bypass_window: bool,
        ) -> Result<()>;
        async fn ensure_event_is_active(
            &self,
            community_id: Uuid,
            event_id: Uuid,
        ) -> Result<()>;
        async fn get_event_enrollment(
            &self,
            community_id: Uuid,
            event_id: Uuid,
            user_id: Uuid,
        ) -> Result<crate::types::event::EventEnrollmentState>;
        async fn get_event_full_by_slug(
            &self,
            community_id: Uuid,
            group_slug: &str,
            event_slug: &str,
        ) -> Result<Option<crate::types::event::EventFull>>;
        async fn get_event_registration_questions(
            &self,
            community_id: Uuid,
            event_id: Uuid,
        ) -> Result<Vec<crate::types::questionnaire::QuestionnaireQuestion>>;
        async fn get_event_summary_by_id(
            &self,
            community_id: Uuid,
            event_id: Uuid,
        ) -> Result<crate::types::event::EventSummary>;
        async fn is_event_check_in_window_open(
            &self,
            community_id: Uuid,
            event_id: Uuid,
        ) -> Result<bool>;
        async fn leave_event(
            &self,
            community_id: Uuid,
            event_id: Uuid,
            user_id: Uuid,
            payment_provider: Option<crate::types::payments::PaymentProvider>,
        ) -> Result<crate::types::event::EventLeaveOutcome>;
        async fn list_user_session_proposals_for_cfs_event(
            &self,
            user_id: Uuid,
            event_id: Uuid,
        ) -> Result<Vec<crate::templates::event::SessionProposal>>;
    }

    #[async_trait]
    impl crate::db::activity_tracker::DBActivityTracker for DB {
        async fn update_community_views(&self, data: Vec<(Uuid, String, u32)>) -> Result<()>;
        async fn update_event_views(&self, data: Vec<(Uuid, String, u32)>) -> Result<()>;
        async fn update_group_views(&self, data: Vec<(Uuid, String, u32)>) -> Result<()>;
    }

    #[async_trait]
    impl crate::db::group::DBGroup for DB {
        async fn get_group_full_by_slug(
            &self,
            community_id: Uuid,
            group_slug: &str,
        ) -> Result<Option<crate::types::group::GroupFull>>;
        async fn get_group_past_events(
            &self,
            community_id: Uuid,
            group_slug: &str,
            event_kinds: Vec<crate::types::event::EventKind>,
            limit: i32,
        ) -> Result<Vec<crate::types::event::EventSummary>>;
        async fn get_group_upcoming_events(
            &self,
            community_id: Uuid,
            group_slug: &str,
            event_kinds: Vec<crate::types::event::EventKind>,
            limit: i32,
        ) -> Result<Vec<crate::types::event::EventSummary>>;
        async fn is_group_member(
            &self,
            community_id: Uuid,
            group_id: Uuid,
            user_id: Uuid,
        ) -> Result<bool>;
        async fn join_group(
            &self,
            community_id: Uuid,
            group_id: Uuid,
            user_id: Uuid,
        ) -> Result<()>;
        async fn leave_group(
            &self,
            community_id: Uuid,
            group_id: Uuid,
            user_id: Uuid,
        ) -> Result<()>;
    }

    #[async_trait]
    impl crate::db::images::DBImages for DB {
        async fn get_image(
            &self,
            file_name: &str,
        ) -> Result<Option<crate::services::images::Image>>;
        async fn is_badge_image(
            &self,
            file_name: &str,
        ) -> Result<bool>;
        async fn is_open_graph_image(
            &self,
            file_name: &str,
        ) -> Result<bool>;
        async fn save_image(
            &self,
            user_id: Uuid,
            file_name: &str,
            data: &[u8],
            content_type: &str,
        ) -> Result<()>;
    }

    #[async_trait]
    impl crate::db::meetings::DBMeetings for DB {
        async fn add_meeting(
            &self,
            meeting: &crate::services::meetings::Meeting,
        ) -> Result<()>;
        async fn append_meeting_recording_url(
            &self,
            provider: crate::services::meetings::MeetingProvider,
            provider_meeting_id: &str,
            recording_url: &str,
        ) -> Result<()>;
        async fn assign_zoom_host_user(
            &self,
            meeting: &crate::services::meetings::Meeting,
            pool_users: &[String],
            max_simultaneous_meetings_per_user: i32,
            starts_at: chrono::DateTime<chrono::Utc>,
            ends_at: chrono::DateTime<chrono::Utc>,
        ) -> Result<Option<String>>;
        async fn claim_meeting_for_auto_end(
            &self,
        ) -> Result<Option<crate::db::meetings::MeetingAutoEndCandidate>>;
        async fn claim_meeting_out_of_sync(
            &self,
        ) -> Result<Option<crate::services::meetings::Meeting>>;
        async fn delete_meeting(
            &self,
            meeting: &crate::services::meetings::Meeting,
        ) -> Result<()>;
        async fn mark_stale_meeting_auto_end_checks_unknown(
            &self,
            timeout: std::time::Duration,
        ) -> Result<usize>;
        async fn mark_stale_meeting_syncs_unknown(
            &self,
            timeout: std::time::Duration,
        ) -> Result<usize>;
        async fn release_meeting_auto_end_check_claim(
            &self,
            candidate: &crate::db::meetings::MeetingAutoEndCandidate,
        ) -> Result<()>;
        async fn release_meeting_sync_claim(
            &self,
            meeting: &crate::services::meetings::Meeting,
        ) -> Result<()>;
        async fn set_meeting_auto_end_check_outcome(
            &self,
            candidate: &crate::db::meetings::MeetingAutoEndCandidate,
            outcome: crate::services::meetings::MeetingAutoEndCheckOutcome,
        ) -> Result<()>;
        async fn set_meeting_error(
            &self,
            meeting: &crate::services::meetings::Meeting,
            error: &str,
        ) -> Result<()>;
        async fn update_meeting(
            &self,
            meeting: &crate::services::meetings::Meeting,
        ) -> Result<()>;
    }

    #[async_trait]
    impl crate::db::notifications::DBNotifications for DB {
        async fn claim_pending_notification(
            &self,
        ) -> Result<Option<crate::services::notifications::Notification>>;
        async fn enqueue_due_event_reminders(
            &self,
            base_url: &str,
        ) -> Result<usize>;
        async fn enqueue_notification(
            &self,
            notification: &crate::services::notifications::NewNotification,
        ) -> Result<()>;
        async fn enqueue_tracked_custom_notification(
            &self,
            notification: &crate::services::notifications::NewNotification,
            tracking: crate::db::notifications::CustomNotificationTracking,
        ) -> Result<()>;
        async fn get_notification_attachment(
            &self,
            attachment_id: Uuid
        ) -> Result<crate::services::notifications::Attachment>;
        async fn mark_notification_delivery_unknown(
            &self,
            notification: &crate::services::notifications::Notification,
            error: &str,
        ) -> Result<()>;
        async fn mark_stale_processing_notifications_unknown(
            &self,
            timeout: std::time::Duration,
        ) -> Result<usize>;
        async fn requeue_notification(
            &self,
            notification: &crate::services::notifications::Notification,
            error: &str,
            base_retry_after: std::time::Duration,
            max_retry_after: std::time::Duration,
            max_delivery_attempts: usize,
        ) -> Result<()>;
        async fn update_notification(
            &self,
            notification: &crate::services::notifications::Notification,
            error: Option<String>,
        ) -> Result<()>;
    }

    #[async_trait]
    impl crate::db::payments::DBPayments for DB {
        async fn attach_checkout_session_to_event_purchase(
            &self,
            event_purchase_id: Uuid,
            payment_provider: crate::types::payments::PaymentProvider,
            checkout_session: &crate::services::payments::CheckoutSession,
        ) -> Result<()>;
        async fn cancel_event_checkout(
            &self,
            community_id: Uuid,
            event_id: Uuid,
            user_id: Uuid,
            payment_provider: Option<crate::types::payments::PaymentProvider>,
        ) -> Result<()>;
        async fn claim_event_purchase_refund(
            &self,
            payment_provider: crate::types::payments::PaymentProvider,
        ) -> Result<Option<crate::db::payments::ClaimedEventPurchaseRefund>>;
        async fn complete_event_purchase_refund_recovery(
            &self,
            input: &crate::db::payments::CompleteEventPurchaseRefundRecoveryInput,
        ) -> Result<()>;
        async fn complete_free_event_purchase(
            &self,
            event_purchase_id: Uuid,
        ) -> Result<crate::db::payments::CompletedEventPurchase>;
        async fn expire_event_purchase_for_checkout_session(
            &self,
            payment_provider: crate::types::payments::PaymentProvider,
            provider_session_id: &str,
        ) -> Result<()>;
        async fn finalize_event_purchase_refund(
            &self,
            event_purchase_refund_id: Uuid,
            claim_id: Uuid,
            notification_template_data: serde_json::Value,
            payment_provider: Option<crate::types::payments::PaymentProvider>,
        ) -> Result<()>;
        async fn get_event_purchase_refund(
            &self,
            event_purchase_id: Uuid,
        ) -> Result<crate::db::payments::EventPurchaseRefund>;
        async fn get_event_purchase_refund_recovery_context(
            &self,
            group_id: Uuid,
            event_purchase_id: Uuid,
        ) -> Result<crate::db::payments::EventPurchaseRefundRecoveryContext>;
        async fn get_event_purchase_summary(
            &self,
            event_purchase_id: Uuid,
        ) -> Result<crate::types::payments::EventPurchaseSummary>;
        async fn prepare_event_checkout_purchase(
            &self,
            community_id: Uuid,
            input: &crate::db::payments::PrepareEventCheckoutPurchaseInput,
        ) -> Result<crate::db::payments::PrepareEventCheckoutPurchaseResult>;
        async fn queue_event_refund_request_approval(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            event_purchase_id: Uuid,
            review_note: Option<String>,
        ) -> Result<()>;
        async fn reconcile_event_purchase_for_checkout_session(
            &self,
            payment_provider: crate::types::payments::PaymentProvider,
            provider_session_id: &str,
            provider_payment_reference: Option<String>,
        ) -> Result<crate::db::payments::ReconcileEventPurchaseResult>;
        async fn reconcile_next_event_enrollment(
            &self,
            payment_provider: Option<crate::types::payments::PaymentProvider>,
        ) -> Result<Option<crate::types::event::EventEnrollmentReconciliationOutcome>>;
        async fn record_event_purchase_refund_pending(
            &self,
            event_purchase_refund_id: Uuid,
            expected_idempotency_key: String,
            provider_refund_id: String,
            expected_claim_id: Option<Uuid>,
        ) -> Result<crate::db::payments::EventPurchaseRefund>;
        async fn record_event_purchase_refund_retryable_failure(
            &self,
            event_purchase_refund_id: Uuid,
            claim_id: Uuid,
            failure_message: String,
        ) -> Result<()>;
        async fn record_event_purchase_refund_succeeded(
            &self,
            event_purchase_refund_id: Uuid,
            expected_idempotency_key: String,
            provider_refund_id: String,
            expected_claim_id: Option<Uuid>,
        ) -> Result<crate::db::payments::EventPurchaseRefund>;
        async fn record_event_purchase_refund_terminal_failed(
            &self,
            event_purchase_refund_id: Uuid,
            expected_idempotency_key: String,
            provider_refund_id: String,
            failure_message: String,
            expected_claim_id: Option<Uuid>,
        ) -> Result<()>;
        async fn reject_event_refund_request(
            &self,
            actor_user_id: Uuid,
            group_id: Uuid,
            event_purchase_id: Uuid,
            review_note: String,
        ) -> Result<crate::db::payments::CompletedEventPurchase>;
        async fn request_event_refund(
            &self,
            community_id: Uuid,
            event_id: Uuid,
            user_id: Uuid,
            requested_reason: Option<String>,
            notification_template_data: serde_json::Value,
        ) -> Result<()>;
        async fn requeue_event_purchase_refund(
            &self,
            group_id: Uuid,
            event_purchase_id: Uuid,
        ) -> Result<()>;
        async fn requeue_stale_event_purchase_refund_claims(&self) -> Result<i32>;
    }

    #[async_trait]
    impl crate::db::site::DBSite for DB {
        async fn get_filters_options(
            &self,
            community_name: Option<String>,
            entity: Option<crate::templates::site::explore::Entity>,
        ) -> Result<crate::templates::site::explore::FiltersOptions>;
        async fn get_site_home_stats(&self) -> Result<crate::types::site::SiteHomeStats>;
        async fn get_site_recently_added_groups(
            &self,
        ) -> Result<Vec<crate::types::group::GroupSummary>>;
        async fn get_site_settings(&self) -> Result<crate::types::site::SiteSettings>;
        async fn get_site_stats(&self) -> Result<crate::templates::site::stats::SiteStats>;
        async fn get_site_upcoming_events(
            &self,
            event_kinds: Vec<crate::types::event::EventKind>,
        ) -> Result<Vec<crate::types::event::EventSummary>>;
        async fn list_communities(&self) -> Result<Vec<crate::types::community::CommunitySummary>>;
    }
}
