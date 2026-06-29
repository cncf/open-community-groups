//! Database operations for authentication and authorization.

use anyhow::Result;
use async_trait::async_trait;
use axum_login::tower_sessions::session;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    auth::{User, UserSummary},
    db::PgExecutor,
    handlers::api::auth::{ApiScope, ApiToken, ApiUser},
    templates::site::profile::{
        CoffeeMeetRequestInput, CoffeeMeetRequestRecord, MentorshipRequestInput,
        MentorshipRequestRecord,
    },
    templates::{auth::UserDetails, notifications::EmailVerification},
    types::permissions::{AlliancePermission, GroupPermission},
    types::user::{PublicUserProfile, UserProvider},
};

/// Trait for database operations related to authentication and authorization.
#[async_trait]
pub(crate) trait DBAuth {
    /// Activates a pre-registered user using password signup details.
    async fn activate_pre_registered_user_email_password(
        &self,
        user_summary: &UserSummary,
        verification: &EmailVerificationNotification,
    ) -> Result<Option<(User, Uuid)>>;

    /// Activates a pre-registered user using externally verified identity details.
    async fn activate_pre_registered_user_external_provider(
        &self,
        user_id: &Uuid,
        user_summary: &UserSummary,
    ) -> Result<User>;

    /// Creates a new session in the database.
    async fn create_session(&self, record: &session::Record) -> Result<()>;

    /// Creates a new API token.
    async fn create_api_token(
        &self,
        user_id: Uuid,
        token_hash: &str,
        token_prefix: &str,
        name: Option<String>,
        scopes: &[ApiScope],
    ) -> Result<ApiToken>;

    /// Records a mentorship request.
    async fn add_mentorship_request(
        &self,
        requester_user_id: Uuid,
        mentor_username: &str,
        input: &MentorshipRequestInput,
    ) -> Result<MentorshipRequestRecord>;

    /// Records a direct `CoffeeMeet` request.
    async fn add_coffee_meet_request(
        &self,
        requester_user_id: Uuid,
        recipient_username: &str,
        input: &CoffeeMeetRequestInput,
    ) -> Result<CoffeeMeetRequestRecord>;

    /// Deletes a session from the database.
    async fn delete_session(&self, session_id: &session::Id) -> Result<()>;

    /// Retrieves a session by its ID.
    async fn get_session(&self, session_id: &session::Id) -> Result<Option<session::Record>>;

    /// Retrieves a registered or pre-registered user by email for external auth.
    async fn get_user_by_email_for_external_auth(&self, email: &str) -> Result<Option<User>>;

    /// Resolves a non-revoked API token to an authenticated API user.
    async fn get_api_token_auth(&self, token_hash: &str) -> Result<Option<ApiUser>>;

    /// Lists a user's API tokens.
    async fn list_api_tokens(&self, user_id: Uuid) -> Result<Vec<ApiToken>>;

    /// Retrieves a user by their unique ID.
    async fn get_user_by_id(&self, user_id: &Uuid) -> Result<Option<User>>;

    /// Retrieves a user by their username.
    async fn get_user_by_username(&self, username: &str) -> Result<Option<User>>;

    /// Retrieves public, non-email profile fields by username.
    async fn get_public_user_profile_by_username(
        &self,
        username: &str,
    ) -> Result<Option<PublicUserProfile>>;

    /// Retrieves the password hash for a user.
    async fn get_user_password(&self, user_id: &Uuid) -> Result<Option<String>>;

    /// Checks whether a `LinkedIn` OIDC subject is blocked.
    async fn is_linkedin_subject_blocked(&self, linkedin_subject: &str) -> Result<bool>;

    /// Checks whether a group belongs to a alliance.
    async fn group_belongs_to_alliance(&self, alliance_id: &Uuid, group_id: &Uuid) -> Result<bool>;

    /// Registers a new user in the database.
    async fn sign_up_user(
        &self,
        user_summary: &UserSummary,
        email_verified: bool,
        verification: Option<EmailVerificationNotification>,
    ) -> Result<(User, Option<Uuid>)>;

    /// Revokes one API token owned by a user.
    async fn revoke_api_token(&self, user_id: Uuid, api_token_id: Uuid) -> Result<()>;

    /// Updates an existing session in the database.
    async fn update_session(&self, record: &session::Record) -> Result<()>;

    /// Updates user details in the database.
    async fn update_user_details(&self, actor_user_id: &Uuid, user: &UserDetails) -> Result<()>;

    /// Updates a user's password in the database.
    async fn update_user_password(&self, actor_user_id: &Uuid, new_password: &str) -> Result<()>;

    /// Updates externally sourced provider metadata for a user.
    async fn update_user_provider(&self, user_id: &Uuid, provider: &UserProvider) -> Result<()>;

    /// Updates externally sourced profile fields for a user.
    async fn update_user_external_profile(
        &self,
        user_id: &Uuid,
        user_summary: &UserSummary,
    ) -> Result<()>;

    /// Checks whether a user has a permission in a specific alliance.
    async fn user_has_alliance_permission(
        &self,
        alliance_id: &Uuid,
        user_id: &Uuid,
        permission: AlliancePermission,
    ) -> Result<bool>;

    /// Checks whether a user has a permission in a specific group.
    async fn user_has_group_permission(
        &self,
        alliance_id: &Uuid,
        group_id: &Uuid,
        user_id: &Uuid,
        permission: GroupPermission,
    ) -> Result<bool>;

    /// Verifies a user's email address using a verification code.
    async fn verify_email(&self, code: &Uuid) -> Result<()>;
}

#[async_trait]
impl<T> DBAuth for T
where
    T: PgExecutor + Send + Sync,
{
    #[instrument(skip(self, user_summary, verification), err)]
    async fn activate_pre_registered_user_email_password(
        &self,
        user_summary: &UserSummary,
        verification: &EmailVerificationNotification,
    ) -> Result<Option<(User, Uuid)>> {
        let template_data = serde_json::to_value(&verification.template_data)?;
        let db = self.client().await?;
        let row = db
            .query_opt(
                "
                select *
                from activate_pre_registered_user_email_password(
                    $1::jsonb,
                    $2::uuid,
                    $3::jsonb
                );
                ",
                &[&Json(user_summary), &verification.code, &template_data],
            )
            .await?;

        let Some(row) = row else {
            return Ok(None);
        };

        let user = row.try_get::<_, Json<User>>(0)?.0;
        let verification_code = row.get(1);

        Ok(Some((user, verification_code)))
    }

    #[instrument(skip(self, user_summary), err)]
    async fn activate_pre_registered_user_external_provider(
        &self,
        user_id: &Uuid,
        user_summary: &UserSummary,
    ) -> Result<User> {
        self.fetch_json_one(
            "select activate_pre_registered_user_external_provider($1::uuid, $2::jsonb);",
            &[user_id, &Json(user_summary)],
        )
        .await
    }

    #[instrument(skip(self, record), err)]
    async fn create_session(&self, record: &session::Record) -> Result<()> {
        self.execute(
            "
            insert into auth_session (
                auth_session_id,
                data,
                expires_at
            ) values (
                $1::text,
                $2::jsonb,
                $3::timestamptz
            );
            ",
            &[
                &record.id.to_string(),
                &Json(&record.data),
                &record.expiry_date,
            ],
        )
        .await
    }

    #[instrument(skip(self, token_hash), err)]
    async fn create_api_token(
        &self,
        user_id: Uuid,
        token_hash: &str,
        token_prefix: &str,
        name: Option<String>,
        scopes: &[ApiScope],
    ) -> Result<ApiToken> {
        let scope_texts = scopes.iter().map(|scope| scope.as_str()).collect::<Vec<_>>();
        self.fetch_json_one(
            "
            insert into api_token (
                user_id,
                token_hash,
                token_prefix,
                name,
                scopes
            ) values (
                $1::uuid,
                $2::text,
                $3::text,
                $4::text,
                $5::text[]
            )
            returning jsonb_build_object(
                'api_token_id', api_token_id,
                'user_id', user_id,
                'name', name,
                'token_prefix', token_prefix,
                'scopes', scopes,
                'created_at', extract(epoch from created_at)::bigint,
                'last_used_at', null,
                'revoked_at', null
            );
            ",
            &[&user_id, &token_hash, &token_prefix, &name, &scope_texts],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn add_mentorship_request(
        &self,
        requester_user_id: Uuid,
        mentor_username: &str,
        input: &MentorshipRequestInput,
    ) -> Result<MentorshipRequestRecord> {
        self.fetch_json_one(
            "select add_mentorship_request($1::uuid, $2::text, $3::jsonb)",
            &[&requester_user_id, &mentor_username, &Json(input)],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn add_coffee_meet_request(
        &self,
        requester_user_id: Uuid,
        recipient_username: &str,
        input: &CoffeeMeetRequestInput,
    ) -> Result<CoffeeMeetRequestRecord> {
        self.fetch_json_one(
            "select add_coffee_meet_request($1::uuid, $2::text, $3::jsonb)",
            &[&requester_user_id, &recipient_username, &Json(input)],
        )
        .await
    }

    #[instrument(skip(self, session_id), err)]
    async fn delete_session(&self, session_id: &session::Id) -> Result<()> {
        self.execute(
            "delete from auth_session where auth_session_id = $1::text;",
            &[&session_id.to_string()],
        )
        .await
    }

    #[instrument(skip(self, session_id), err)]
    async fn get_session(&self, session_id: &session::Id) -> Result<Option<session::Record>> {
        let db = self.client().await?;
        let row = db
            .query_opt(
                "select data, expires_at from auth_session where auth_session_id = $1::text;",
                &[&session_id.to_string()],
            )
            .await?;

        if let Some(row) = row {
            let record = session::Record {
                id: *session_id,
                data: row.try_get::<_, Json<_>>("data")?.0,
                expiry_date: row.get("expires_at"),
            };
            return Ok(Some(record));
        }

        Ok(None)
    }

    #[instrument(skip(self, email), err)]
    async fn get_user_by_email_for_external_auth(&self, email: &str) -> Result<Option<User>> {
        self.fetch_json_opt(
            "select get_user_by_email_for_external_auth($1::text);",
            &[&email],
        )
        .await
    }

    #[instrument(skip(self, token_hash), err)]
    async fn get_api_token_auth(&self, token_hash: &str) -> Result<Option<ApiUser>> {
        let db = self.client().await?;
        let Some(row) = db
            .query_opt(
                "
                update api_token
                set last_used_at = now()
                where token_hash = $1::text
                and revoked_at is null
                returning get_user_by_id(user_id), scopes;
                ",
                &[&token_hash],
            )
            .await?
        else {
            return Ok(None);
        };

        let user = row.try_get::<_, Json<User>>(0)?.0;
        let scopes = row
            .get::<_, Vec<String>>(1)
            .into_iter()
            .filter_map(|scope| scope.parse().ok())
            .collect();

        Ok(Some(ApiUser { user, scopes }))
    }

    #[instrument(skip(self), err)]
    async fn list_api_tokens(&self, user_id: Uuid) -> Result<Vec<ApiToken>> {
        self.fetch_json_one(
            "
            select coalesce(jsonb_agg(jsonb_build_object(
                'api_token_id', api_token_id,
                'user_id', user_id,
                'name', name,
                'token_prefix', token_prefix,
                'scopes', scopes,
                'created_at', extract(epoch from created_at)::bigint,
                'last_used_at', extract(epoch from last_used_at)::bigint,
                'revoked_at', extract(epoch from revoked_at)::bigint
            ) order by created_at desc), '[]'::jsonb)
            from api_token
            where user_id = $1::uuid;
            ",
            &[&user_id],
        )
        .await
    }

    #[instrument(skip(self, user_id), err)]
    async fn get_user_by_id(&self, user_id: &Uuid) -> Result<Option<User>> {
        self.fetch_json_opt("select get_user_by_id_verified($1::uuid);", &[&user_id])
            .await
    }

    #[instrument(skip(self, username), err)]
    async fn get_user_by_username(&self, username: &str) -> Result<Option<User>> {
        self.fetch_json_opt("select get_user_by_username($1::text);", &[&username])
            .await
    }

    #[instrument(skip(self, username), err)]
    async fn get_public_user_profile_by_username(
        &self,
        username: &str,
    ) -> Result<Option<PublicUserProfile>> {
        self.fetch_json_opt(
            r#"
            select jsonb_build_object(
                'user_id', user_id,
                'username', username,
                'bio', bio,
                'bluesky_url', bluesky_url,
                'coffee_meet_enabled', coffee_meet_enabled,
                'company', company,
                'facebook_url', facebook_url,
                'github_url', github_url,
                'linkedin_url', linkedin_url,
                'mentorship_businesses', mentorship_businesses,
                'mentorship_individuals', mentorship_individuals,
                'mentorship_note', mentorship_note,
                'mentorship_price', mentorship_price,
                'name', name,
                'photo_url', photo_url,
                'substack_url', substack_url,
                'title', title,
                'twitter_url', twitter_url,
                'website_url', website_url,
                'youtube_url', youtube_url
            )
            from "user"
            where lower(username) = lower($1::text)
            and email_verified = true
            and registration_status = 'registered';
            "#,
            &[&username],
        )
        .await
    }

    #[instrument(skip(self, user_id), err)]
    async fn get_user_password(&self, user_id: &Uuid) -> Result<Option<String>> {
        self.fetch_scalar_opt(
            r#"select password from "user" where user_id = $1::uuid;"#,
            &[&user_id],
        )
        .await
    }

    #[instrument(skip(self), err)]
    async fn is_linkedin_subject_blocked(&self, linkedin_subject: &str) -> Result<bool> {
        self.fetch_scalar_one(
            "select is_linkedin_subject_blocked($1::text)",
            &[&linkedin_subject],
        )
        .await
    }

    #[instrument(skip(self), err)]
    async fn group_belongs_to_alliance(&self, alliance_id: &Uuid, group_id: &Uuid) -> Result<bool> {
        self.fetch_scalar_one(
            r#"
            select exists (
                select 1
                from "group"
                where alliance_id = $1::uuid
                  and group_id = $2::uuid
                  and deleted = false
            );
            "#,
            &[&alliance_id, &group_id],
        )
        .await
    }

    #[instrument(skip(self, user_summary, verification), err)]
    async fn sign_up_user(
        &self,
        user_summary: &UserSummary,
        email_verified: bool,
        verification: Option<EmailVerificationNotification>,
    ) -> Result<(User, Option<Uuid>)> {
        let verification_code = verification.as_ref().map(|verification| verification.code);
        let verification_template_data = verification
            .as_ref()
            .map(|verification| serde_json::to_value(&verification.template_data))
            .transpose()?;

        let db = self.client().await?;
        let row = db
            .query_one(
                "
                select *
                from sign_up_user(
                    $1::jsonb,
                    $2::boolean,
                    $3::uuid,
                    $4::jsonb
                );
                ",
                &[
                    &Json(user_summary),
                    &email_verified,
                    &verification_code,
                    &verification_template_data,
                ],
            )
            .await?;

        let user = row.try_get::<_, Json<User>>(0)?.0;
        let verification_code: Option<Uuid> = row.get(1);

        Ok((user, verification_code))
    }

    #[instrument(skip(self), err)]
    async fn revoke_api_token(&self, user_id: Uuid, api_token_id: Uuid) -> Result<()> {
        self.execute(
            "
            update api_token
            set revoked_at = coalesce(revoked_at, now())
            where user_id = $1::uuid
            and api_token_id = $2::uuid;
            ",
            &[&user_id, &api_token_id],
        )
        .await
    }

    #[instrument(skip(self, record), err)]
    async fn update_session(&self, record: &session::Record) -> Result<()> {
        self.execute(
            "
            update auth_session
            set
                data = $2::jsonb,
                expires_at = $3::timestamptz
            where auth_session_id = $1::text;
            ",
            &[
                &record.id.to_string(),
                &Json(&record.data),
                &record.expiry_date,
            ],
        )
        .await
    }

    #[instrument(skip(self, user), err)]
    async fn update_user_details(&self, actor_user_id: &Uuid, user: &UserDetails) -> Result<()> {
        self.execute(
            "select update_user_details($1::uuid, $2::jsonb);",
            &[actor_user_id, &Json(user)],
        )
        .await
    }

    #[instrument(skip(self, new_password), err)]
    async fn update_user_password(&self, actor_user_id: &Uuid, new_password: &str) -> Result<()> {
        self.execute(
            "select update_user_password($1::uuid, $2::text);",
            &[actor_user_id, &new_password],
        )
        .await
    }

    #[instrument(skip(self, provider), err)]
    async fn update_user_provider(&self, user_id: &Uuid, provider: &UserProvider) -> Result<()> {
        self.execute(
            "select update_user_provider($1::uuid, $2::jsonb);",
            &[user_id, &Json(provider)],
        )
        .await
    }

    #[instrument(skip(self, user_summary), err)]
    async fn update_user_external_profile(
        &self,
        user_id: &Uuid,
        user_summary: &UserSummary,
    ) -> Result<()> {
        self.execute(
            "select update_user_external_profile($1::uuid, $2::jsonb);",
            &[user_id, &Json(user_summary)],
        )
        .await
    }

    #[instrument(skip(self, permission), err)]
    async fn user_has_alliance_permission(
        &self,
        alliance_id: &Uuid,
        user_id: &Uuid,
        permission: AlliancePermission,
    ) -> Result<bool> {
        self.fetch_scalar_one(
            "select user_has_alliance_permission($1::uuid, $2::uuid, $3::text);",
            &[&alliance_id, &user_id, &permission.as_str()],
        )
        .await
    }

    #[instrument(skip(self, permission), err)]
    async fn user_has_group_permission(
        &self,
        alliance_id: &Uuid,
        group_id: &Uuid,
        user_id: &Uuid,
        permission: GroupPermission,
    ) -> Result<bool> {
        self.fetch_scalar_one(
            "select user_has_group_permission($1::uuid, $2::uuid, $3::uuid, $4::text);",
            &[&alliance_id, &group_id, &user_id, &permission.as_str()],
        )
        .await
    }

    #[instrument(skip(self), err)]
    async fn verify_email(&self, code: &Uuid) -> Result<()> {
        self.execute("select verify_email($1::uuid);", &[&code]).await
    }
}

/// Verification notification data required for password signups.
#[derive(Debug, Clone)]
pub(crate) struct EmailVerificationNotification {
    /// Verification code stored in the database and sent to the user.
    pub(crate) code: Uuid,
    /// Typed notification template data serialized for enqueueing.
    pub(crate) template_data: EmailVerification,
}
