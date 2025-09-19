//! DB trait mock implementation for testing.

use anyhow::Result;
use async_trait::async_trait;
use mockall::mock;
use uuid::Uuid;

mock! {
    /// Mock `DB` struct for testing purposes, implementing the DB trait.
    pub(crate) DB {}

    #[async_trait]
    impl crate::db::DB for DB {
        async fn tx_begin(&self) -> Result<Uuid>;
        async fn tx_commit(&self, client_id: Uuid) -> Result<()>;
        async fn tx_rollback(&self, client_id: Uuid) -> Result<()>;
    }

    #[async_trait]
    impl crate::db::auth::DBAuth for DB {
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
        async fn get_user_by_email(
            &self,
            community_id: &Uuid,
            email: &str,
        ) -> Result<Option<crate::auth::User>>;
        async fn get_user_by_id(&self, user_id: &Uuid) -> Result<Option<crate::auth::User>>;
        async fn get_user_by_username(
            &self,
            community_id: &Uuid,
            username: &str,
        ) -> Result<Option<crate::auth::User>>;
        async fn get_user_password(&self, user_id: &Uuid) -> Result<Option<String>>;
        async fn sign_up_user(
            &self,
            community_id: &Uuid,
            user_summary: &crate::auth::UserSummary,
            email_verified: bool,
        ) -> Result<(crate::auth::User, Option<Uuid>)>;
        async fn update_session(
            &self,
            record: &axum_login::tower_sessions::session::Record,
        ) -> Result<()>;
        async fn update_user_details(
            &self,
            user_id: &Uuid,
            user: &crate::templates::auth::UserDetails,
        ) -> Result<()>;
        async fn update_user_password(
            &self,
            user_id: &Uuid,
            new_password: &str,
        ) -> Result<()>;
        async fn user_owns_community(&self, community_id: &Uuid, user_id: &Uuid) -> Result<bool>;
        async fn user_owns_group(
            &self,
            community_id: &Uuid,
            group_id: &Uuid,
            user_id: &Uuid,
        ) -> Result<bool>;
        async fn verify_email(&self, code: &Uuid) -> Result<()>;
    }

    #[async_trait]
    impl crate::db::common::DBCommon for DB {
        async fn get_community(
            &self,
            community_id: Uuid,
        ) -> Result<crate::types::community::Community>;
        async fn get_event_full(&self, event_id: Uuid)
            -> Result<crate::types::event::EventFull>;
        async fn get_event_summary(&self, event_id: Uuid)
            -> Result<crate::types::event::EventSummary>;
        async fn get_group_full(&self, group_id: Uuid)
            -> Result<crate::types::group::GroupFull>;
        async fn get_group_summary(&self, group_id: Uuid)
            -> Result<crate::types::group::GroupSummary>;
        async fn list_timezones(&self) -> Result<Vec<String>>;
        async fn search_community_events(
            &self,
            community_id: Uuid,
            filters: &crate::templates::community::explore::EventsFilters,
        ) -> Result<crate::db::common::SearchCommunityEventsOutput>;
        async fn search_community_groups(
            &self,
            community_id: Uuid,
            filters: &crate::templates::community::explore::GroupsFilters,
        ) -> Result<crate::db::common::SearchCommunityGroupsOutput>;
    }

    #[async_trait]
    impl crate::db::community::DBCommunity for DB {
        async fn get_community_filters_options(
            &self,
            community_id: Uuid,
        ) -> Result<crate::templates::community::explore::FiltersOptions>;
        async fn get_community_home_stats(
            &self,
            community_id: Uuid,
        ) -> Result<crate::templates::community::home::Stats>;
        async fn get_community_id(&self, host: &str) -> Result<Option<Uuid>>;
        async fn get_community_recently_added_groups(
            &self,
            community_id: Uuid,
        ) -> Result<Vec<crate::types::group::GroupSummary>>;
        async fn get_community_upcoming_events(
            &self,
            community_id: Uuid,
            event_kinds: Vec<crate::types::event::EventKind>,
        ) -> Result<Vec<crate::types::event::EventSummary>>;
    }

    impl crate::db::dashboard::DBDashboard for DB {}

    #[async_trait]
    impl crate::db::dashboard::common::DBDashboardCommon for DB {
        async fn search_user(
            &self,
            community_id: Uuid,
            query: &str,
        ) -> Result<Vec<crate::db::dashboard::common::User>>;
        async fn update_group(
            &self,
            community_id: Uuid,
            group_id: Uuid,
            group: &crate::templates::dashboard::community::groups::Group,
        ) -> Result<()>;
    }

    #[async_trait]
    impl crate::db::dashboard::community::DBDashboardCommunity for DB {
        async fn activate_group(&self, community_id: Uuid, group_id: Uuid) -> Result<()>;
        async fn add_community_team_member(
            &self,
            community_id: Uuid,
            user_id: Uuid,
        ) -> Result<()>;
        async fn add_group(
            &self,
            community_id: Uuid,
            group: &crate::templates::dashboard::community::groups::Group,
        ) -> Result<Uuid>;
        async fn deactivate_group(&self, community_id: Uuid, group_id: Uuid) -> Result<()>;
        async fn delete_community_team_member(
            &self,
            community_id: Uuid,
            user_id: Uuid,
        ) -> Result<()>;
        async fn delete_group(&self, community_id: Uuid, group_id: Uuid) -> Result<()>;
        async fn list_community_team_members(
            &self,
            community_id: Uuid,
        ) -> Result<Vec<crate::templates::dashboard::community::team::CommunityTeamMember>>;
        async fn list_group_categories(
            &self,
            community_id: Uuid,
        ) -> Result<Vec<crate::types::group::GroupCategory>>;
        async fn list_regions(
            &self,
            community_id: Uuid,
        ) -> Result<Vec<crate::types::group::GroupRegion>>;
        async fn update_community(
            &self,
            community_id: Uuid,
            community: &crate::templates::dashboard::community::settings::CommunityUpdate,
        ) -> Result<()>;
    }

    #[async_trait]
    impl crate::db::dashboard::group::DBDashboardGroup for DB {
        async fn add_event(
            &self,
            group_id: Uuid,
            event: &crate::templates::dashboard::group::events::Event,
        ) -> Result<Uuid>;
        async fn add_group_sponsor(
            &self,
            group_id: Uuid,
            sponsor: &crate::templates::dashboard::group::sponsors::Sponsor,
        ) -> Result<Uuid>;
        async fn add_group_team_member(
            &self,
            group_id: Uuid,
            user_id: Uuid,
            role: &crate::types::group::GroupRole,
        ) -> Result<()>;
        async fn cancel_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()>;
        async fn delete_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()>;
        async fn delete_group_sponsor(
            &self,
            group_id: Uuid,
            group_sponsor_id: Uuid,
        ) -> Result<()>;
        async fn delete_group_team_member(
            &self,
            group_id: Uuid,
            user_id: Uuid,
        ) -> Result<()>;
        async fn get_group_sponsor(
            &self,
            group_id: Uuid,
            group_sponsor_id: Uuid,
        ) -> Result<crate::types::group::GroupSponsor>;
        async fn list_event_attendees_ids(
            &self,
            event_id: Uuid,
        ) -> Result<Vec<Uuid>>;
        async fn list_event_categories(
            &self,
            community_id: Uuid,
        ) -> Result<Vec<crate::types::event::EventCategory>>;
        async fn list_event_kinds(&self)
            -> Result<Vec<crate::types::event::EventKindSummary>>;
        async fn list_group_events(
            &self,
            group_id: Uuid,
        ) -> Result<crate::templates::dashboard::group::events::GroupEvents>;
        async fn list_group_members(
            &self,
            group_id: Uuid,
        ) -> Result<Vec<crate::templates::dashboard::group::members::GroupMember>>;
        async fn list_group_members_ids(
            &self,
            group_id: Uuid,
        ) -> Result<Vec<Uuid>>;
        async fn list_group_roles(&self)
            -> Result<Vec<crate::types::group::GroupRoleSummary>>;
        async fn list_group_sponsors(
            &self,
            group_id: Uuid,
        ) -> Result<Vec<crate::types::group::GroupSponsor>>;
        async fn list_group_team_members(
            &self,
            group_id: Uuid,
        ) -> Result<Vec<crate::templates::dashboard::group::team::GroupTeamMember>>;
        async fn list_session_kinds(&self)
            -> Result<Vec<crate::types::event::SessionKindSummary>>;
        async fn list_user_groups(
            &self,
            user_id: &Uuid,
        ) -> Result<Vec<crate::types::group::GroupSummary>>;
        async fn publish_event(
            &self,
            group_id: Uuid,
            event_id: Uuid,
            user_id: Uuid,
        ) -> Result<()>;
        async fn search_event_attendees(
            &self,
            group_id: Uuid,
            filters: &crate::templates::dashboard::group::attendees::AttendeesFilters,
        ) -> Result<Vec<crate::templates::dashboard::group::attendees::Attendee>>;
        async fn unpublish_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()>;
        async fn update_event(
            &self,
            group_id: Uuid,
            event_id: Uuid,
            event: &crate::templates::dashboard::group::events::Event,
        ) -> Result<()>;
        async fn update_group_sponsor(
            &self,
            group_id: Uuid,
            group_sponsor_id: Uuid,
            sponsor: &crate::templates::dashboard::group::sponsors::Sponsor,
        ) -> Result<()>;
        async fn update_group_team_member_role(
            &self,
            group_id: Uuid,
            user_id: Uuid,
            role: &crate::types::group::GroupRole,
        ) -> Result<()>;
    }

    #[async_trait]
    impl crate::db::dashboard::user::DBDashboardUser for DB {
        async fn accept_community_team_invitation(
            &self,
            community_id: Uuid,
            user_id: Uuid,
        ) -> Result<()>;
        async fn accept_group_team_invitation(
            &self,
            community_id: Uuid,
            group_id: Uuid,
            user_id: Uuid,
        ) -> Result<()>;
        async fn list_user_community_team_invitations(
            &self,
            community_id: Uuid,
            user_id: Uuid,
        ) -> Result<Vec<
            crate::templates::dashboard::user::invitations::CommunityTeamInvitation,
        >>;
        async fn list_user_group_team_invitations(
            &self,
            community_id: Uuid,
            user_id: Uuid,
        ) -> Result<Vec<
            crate::templates::dashboard::user::invitations::GroupTeamInvitation,
        >>;
    }

    #[async_trait]
    impl crate::db::event::DBEvent for DB {
        async fn attend_event(
            &self,
            community_id: Uuid,
            event_id: Uuid,
            user_id: Uuid,
        ) -> Result<()>;
        async fn get_event(
            &self,
            community_id: Uuid,
            group_slug: &str,
            event_slug: &str,
        ) -> Result<crate::types::event::EventFull>;
        async fn is_event_attendee(
            &self,
            community_id: Uuid,
            event_id: Uuid,
            user_id: Uuid,
        ) -> Result<bool>;
        async fn leave_event(
            &self,
            community_id: Uuid,
            event_id: Uuid,
            user_id: Uuid,
        ) -> Result<()>;
    }

    #[async_trait]
    impl crate::db::group::DBGroup for DB {
        async fn get_group(
            &self,
            community_id: Uuid,
            group_slug: &str,
        ) -> Result<crate::types::group::GroupFull>;
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
        ) -> Result<Vec<crate::types::event::EventDetailed>>;
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
    impl crate::db::notifications::DBNotifications for DB {
        async fn enqueue_notification(
            &self,
            notification: &crate::services::notifications::NewNotification,
        ) -> Result<()>;
        async fn get_pending_notification(
            &self,
            client_id: Uuid,
        ) -> Result<Option<crate::services::notifications::Notification>>;
        async fn update_notification(
            &self,
            client_id: Uuid,
            notification: &crate::services::notifications::Notification,
            error: Option<String>,
        ) -> Result<()>;
    }
}
