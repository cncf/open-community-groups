//! Database operations for authentication and authorization.

use std::fmt;

use anyhow::{Result, anyhow};
use async_trait::async_trait;
use axum_login::tower_sessions::session;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    auth::{ExternalUserProfile, User},
    db::PgExecutor,
    types::{
        permissions::{CommunityPermission, GroupPermission},
        user::{UserDetailsInput, UserProvider},
    },
};

/// Maximum rows deleted per auth cleanup batch; matches the SQL `1..=1000` ceiling.
pub(crate) const AUTH_CLEANUP_BATCH_SIZE: usize = 1000;

/// Trait for database operations related to authentication and authorization.
#[async_trait]
pub(crate) trait DBAuth {
    /// Activates a pre-registered user using password signup details.
    async fn activate_pre_registered_user_email_password(
        &self,
        profile: &ExternalUserProfile,
        verification: &EmailVerificationNotification,
    ) -> Result<Option<(User, Uuid)>>;

    /// Activates a pre-registered user using externally verified identity details.
    async fn activate_pre_registered_user_external_provider(
        &self,
        user_id: &Uuid,
        profile: &ExternalUserProfile,
    ) -> Result<User>;

    /// Creates a password reset token for an eligible user and queues the reset email.
    async fn create_password_reset_token(
        &self,
        email: &str,
        reset: &PasswordResetNotification,
    ) -> Result<bool>;

    /// Creates a new session in the database.
    async fn create_session(&self, record: &session::Record) -> Result<()>;

    /// Deletes one bounded batch of expired authentication sessions.
    async fn delete_expired_auth_sessions(&self, batch_size: usize) -> Result<usize>;

    /// Deletes one bounded batch of expired email verification codes.
    async fn delete_expired_email_verification_codes(&self, batch_size: usize) -> Result<usize>;

    /// Deletes one bounded batch of expired password reset tokens.
    async fn delete_expired_password_reset_tokens(&self, batch_size: usize) -> Result<usize>;

    /// Deletes a session from the database.
    async fn delete_session(&self, session_id: &session::Id) -> Result<()>;

    /// Retrieves an unexpired session by its ID.
    async fn get_session(&self, session_id: &session::Id) -> Result<Option<session::Record>>;

    /// Retrieves a registered or pre-registered user by email for external auth.
    async fn get_user_by_email_for_external_auth(&self, email: &str) -> Result<Option<User>>;

    /// Retrieves a user by their unique ID.
    async fn get_user_by_id(&self, user_id: &Uuid) -> Result<Option<User>>;

    /// Retrieves a verified registered user by Linux Foundation OIDC identity for external auth.
    async fn get_user_by_linuxfoundation_identity_for_external_auth(
        &self,
        issuer: &str,
        subject: &str,
    ) -> Result<Option<User>>;

    /// Retrieves a user by their username.
    async fn get_user_by_username(&self, username: &str) -> Result<Option<User>>;

    /// Retrieves the password hash for a user.
    async fn get_user_password(&self, user_id: &Uuid) -> Result<Option<String>>;

    /// Checks whether a group belongs to a community.
    async fn group_belongs_to_community(
        &self,
        community_id: &Uuid,
        group_id: &Uuid,
    ) -> Result<bool>;

    /// Checks whether a password reset token digest exists and is still valid.
    async fn has_valid_password_reset_token(&self, token_hash: &[u8; 32]) -> Result<bool>;

    /// Resends an email verification code for an unverified registered user after cooldown.
    async fn resend_email_verification(
        &self,
        email: &str,
        verification: &EmailVerificationNotification,
    ) -> Result<bool>;

    /// Consumes a single-use password reset token, updates the password, and rotates `auth_hash`.
    async fn reset_password(&self, token_hash: &[u8; 32], new_password: &str) -> Result<()>;

    /// Registers a new user in the database.
    async fn sign_up_user(
        &self,
        profile: &ExternalUserProfile,
        email_verified: bool,
        verification: Option<EmailVerificationNotification>,
    ) -> Result<(User, Option<Uuid>)>;

    /// Updates an existing session in the database.
    async fn update_session(&self, record: &session::Record) -> Result<()>;

    /// Updates user details in the database.
    async fn update_user_details(
        &self,
        actor_user_id: &Uuid,
        user: &UserDetailsInput,
    ) -> Result<()>;

    /// Updates verified external-auth identity details for a registered user.
    async fn update_user_external_auth(
        &self,
        user_id: &Uuid,
        profile: &ExternalUserProfile,
    ) -> Result<User>;

    /// Updates a user's password in the database.
    async fn update_user_password(&self, actor_user_id: &Uuid, new_password: &str) -> Result<()>;

    /// Updates externally sourced provider metadata for a user.
    async fn update_user_provider(&self, user_id: &Uuid, provider: &UserProvider) -> Result<()>;

    /// Checks whether a user has a permission in a specific community.
    async fn user_has_community_permission(
        &self,
        community_id: &Uuid,
        user_id: &Uuid,
        permission: CommunityPermission,
    ) -> Result<bool>;

    /// Checks whether a user has a permission in a specific group.
    async fn user_has_group_permission(
        &self,
        community_id: &Uuid,
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
    #[instrument(skip(self, profile, verification), err)]
    async fn activate_pre_registered_user_email_password(
        &self,
        profile: &ExternalUserProfile,
        verification: &EmailVerificationNotification,
    ) -> Result<Option<(User, Uuid)>> {
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
                &[
                    &Json(profile),
                    &verification.code,
                    &verification.template_data,
                ],
            )
            .await?;

        let Some(row) = row else {
            return Ok(None);
        };

        let user = row.try_get::<_, Json<User>>(0)?.0;
        let verification_code = row.get(1);

        Ok(Some((user, verification_code)))
    }

    #[instrument(skip(self, profile), err)]
    async fn activate_pre_registered_user_external_provider(
        &self,
        user_id: &Uuid,
        profile: &ExternalUserProfile,
    ) -> Result<User> {
        self.fetch_json_one(
            "select activate_pre_registered_user_external_provider($1::uuid, $2::jsonb);",
            &[user_id, &Json(profile)],
        )
        .await
    }

    /// [`DBAuth::create_password_reset_token`].
    #[instrument(skip(self, email, reset), err)]
    async fn create_password_reset_token(
        &self,
        email: &str,
        reset: &PasswordResetNotification,
    ) -> Result<bool> {
        let token_hash = reset.token_hash.as_slice();
        self.fetch_scalar_one(
            "select create_password_reset_token($1::text, $2::bytea, $3::jsonb);",
            &[&email, &token_hash, &reset.template_data],
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

    /// [`DBAuth::delete_expired_auth_sessions`].
    #[instrument(skip(self), err)]
    async fn delete_expired_auth_sessions(&self, batch_size: usize) -> Result<usize> {
        let batch_size = i32::try_from(batch_size)?;
        let count: i32 = self
            .fetch_scalar_one(
                "select delete_expired_auth_sessions($1::integer)::integer;",
                &[&batch_size],
            )
            .await?;

        usize::try_from(count).map_err(|_| anyhow!("invalid expired auth sessions cleanup count"))
    }

    /// [`DBAuth::delete_expired_email_verification_codes`].
    #[instrument(skip(self), err)]
    async fn delete_expired_email_verification_codes(&self, batch_size: usize) -> Result<usize> {
        let batch_size = i32::try_from(batch_size)?;
        let count: i32 = self
            .fetch_scalar_one(
                "select delete_expired_email_verification_codes($1::integer)::integer;",
                &[&batch_size],
            )
            .await?;

        usize::try_from(count)
            .map_err(|_| anyhow!("invalid expired email verification codes cleanup count"))
    }

    /// [`DBAuth::delete_expired_password_reset_tokens`].
    #[instrument(skip(self), err)]
    async fn delete_expired_password_reset_tokens(&self, batch_size: usize) -> Result<usize> {
        let batch_size = i32::try_from(batch_size)?;
        let count: i32 = self
            .fetch_scalar_one(
                "select delete_expired_password_reset_tokens($1::integer)::integer;",
                &[&batch_size],
            )
            .await?;

        usize::try_from(count)
            .map_err(|_| anyhow!("invalid expired password reset tokens cleanup count"))
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
                "select data, expires_at from get_auth_session($1::text);",
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

    #[instrument(skip(self, user_id), err)]
    async fn get_user_by_id(&self, user_id: &Uuid) -> Result<Option<User>> {
        self.fetch_json_opt("select get_user_by_id_verified($1::uuid);", &[&user_id])
            .await
    }

    #[instrument(skip(self, issuer, subject), err)]
    async fn get_user_by_linuxfoundation_identity_for_external_auth(
        &self,
        issuer: &str,
        subject: &str,
    ) -> Result<Option<User>> {
        self.fetch_json_opt(
            "select get_user_by_linuxfoundation_identity_for_external_auth($1::text, $2::text);",
            &[&issuer, &subject],
        )
        .await
    }

    #[instrument(skip(self, username), err)]
    async fn get_user_by_username(&self, username: &str) -> Result<Option<User>> {
        self.fetch_json_opt("select get_user_by_username($1::text);", &[&username])
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
    async fn group_belongs_to_community(
        &self,
        community_id: &Uuid,
        group_id: &Uuid,
    ) -> Result<bool> {
        self.fetch_scalar_one(
            "select group_belongs_to_community($1::uuid, $2::uuid);",
            &[&community_id, &group_id],
        )
        .await
    }

    /// [`DBAuth::has_valid_password_reset_token`].
    #[instrument(skip(self, token_hash), err)]
    async fn has_valid_password_reset_token(&self, token_hash: &[u8; 32]) -> Result<bool> {
        let token_hash = token_hash.as_slice();
        self.fetch_scalar_one(
            "select has_valid_password_reset_token($1::bytea);",
            &[&token_hash],
        )
        .await
    }

    /// [`DBAuth::resend_email_verification`].
    #[instrument(skip(self, email, verification), err)]
    async fn resend_email_verification(
        &self,
        email: &str,
        verification: &EmailVerificationNotification,
    ) -> Result<bool> {
        self.fetch_scalar_one(
            "select resend_email_verification($1::text, $2::uuid, $3::jsonb);",
            &[&email, &verification.code, &verification.template_data],
        )
        .await
    }

    /// [`DBAuth::reset_password`].
    #[instrument(skip(self, token_hash, new_password), err)]
    async fn reset_password(&self, token_hash: &[u8; 32], new_password: &str) -> Result<()> {
        let token_hash = token_hash.as_slice();
        self.execute(
            "select reset_password($1::bytea, $2::text);",
            &[&token_hash, &new_password],
        )
        .await
    }

    #[instrument(skip(self, profile, verification), err)]
    async fn sign_up_user(
        &self,
        profile: &ExternalUserProfile,
        email_verified: bool,
        verification: Option<EmailVerificationNotification>,
    ) -> Result<(User, Option<Uuid>)> {
        let verification_code = verification.as_ref().map(|verification| verification.code);
        let verification_template_data =
            verification.as_ref().map(|verification| &verification.template_data);

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
                    &Json(profile),
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
    async fn update_user_details(
        &self,
        actor_user_id: &Uuid,
        user: &UserDetailsInput,
    ) -> Result<()> {
        self.execute(
            "select update_user_details($1::uuid, $2::jsonb);",
            &[actor_user_id, &Json(user)],
        )
        .await
    }

    #[instrument(skip(self, profile), err)]
    async fn update_user_external_auth(
        &self,
        user_id: &Uuid,
        profile: &ExternalUserProfile,
    ) -> Result<User> {
        self.fetch_json_one(
            "select update_user_external_auth($1::uuid, $2::jsonb);",
            &[user_id, &Json(profile)],
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

    #[instrument(skip(self, permission), err)]
    async fn user_has_community_permission(
        &self,
        community_id: &Uuid,
        user_id: &Uuid,
        permission: CommunityPermission,
    ) -> Result<bool> {
        self.fetch_scalar_one(
            "select user_has_community_permission($1::uuid, $2::uuid, $3::text);",
            &[&community_id, &user_id, &permission.as_str()],
        )
        .await
    }

    #[instrument(skip(self, permission), err)]
    async fn user_has_group_permission(
        &self,
        community_id: &Uuid,
        group_id: &Uuid,
        user_id: &Uuid,
        permission: GroupPermission,
    ) -> Result<bool> {
        self.fetch_scalar_one(
            "select user_has_group_permission($1::uuid, $2::uuid, $3::uuid, $4::text);",
            &[&community_id, &group_id, &user_id, &permission.as_str()],
        )
        .await
    }

    #[instrument(skip(self, code), err)]
    async fn verify_email(&self, code: &Uuid) -> Result<()> {
        self.execute("select verify_email($1::uuid);", &[&code]).await
    }
}

/// Verification notification data required for password signups.
#[derive(Debug, Clone)]
pub(crate) struct EmailVerificationNotification {
    /// Verification code stored in the database and sent to the user.
    pub(crate) code: Uuid,
    /// Serialized `EmailVerification` template data for enqueueing.
    pub(crate) template_data: serde_json::Value,
}

/// Password reset notification data required when issuing a reset token.
#[derive(Clone)]
pub(crate) struct PasswordResetNotification {
    /// Serialized `PasswordReset` template data for enqueueing.
    pub(crate) template_data: serde_json::Value,
    /// SHA-256 digest of the raw reset token stored in the database.
    pub(crate) token_hash: [u8; 32],
}

impl fmt::Debug for PasswordResetNotification {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("PasswordResetNotification")
            .field("template_data", &"[redacted]")
            .field("token_hash", &"[redacted]")
            .finish()
    }
}
