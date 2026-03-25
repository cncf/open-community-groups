//! Database operations for authentication and authorization.

use anyhow::Result;
use async_trait::async_trait;
use axum_login::tower_sessions::session;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    auth::{User, UserSummary},
    db::PgDB,
    templates::auth::UserDetails,
    types::permissions::{CommunityPermission, GroupPermission},
    types::user::UserProvider,
};

/// Trait for database operations related to authentication and authorization.
#[async_trait]
pub(crate) trait DBAuth {
    /// Creates a new session in the database.
    async fn create_session(&self, record: &session::Record) -> Result<()>;

    /// Deletes a session from the database.
    async fn delete_session(&self, session_id: &session::Id) -> Result<()>;

    /// Retrieves a session by its ID.
    async fn get_session(&self, session_id: &session::Id) -> Result<Option<session::Record>>;

    /// Retrieves a user by their email address.
    async fn get_user_by_email(&self, email: &str) -> Result<Option<User>>;

    /// Retrieves a user by their unique ID.
    async fn get_user_by_id(&self, user_id: &Uuid) -> Result<Option<User>>;

    /// Retrieves a user by their username.
    async fn get_user_by_username(&self, username: &str) -> Result<Option<User>>;

    /// Retrieves the password hash for a user.
    async fn get_user_password(&self, user_id: &Uuid) -> Result<Option<String>>;

    /// Registers a new user in the database.
    async fn sign_up_user(
        &self,
        user_summary: &UserSummary,
        email_verified: bool,
    ) -> Result<(User, Option<Uuid>)>;

    /// Updates an existing session in the database.
    async fn update_session(&self, record: &session::Record) -> Result<()>;

    /// Updates user details in the database.
    async fn update_user_details(&self, actor_user_id: &Uuid, user: &UserDetails) -> Result<()>;

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

/// Implementation of `DBAuth` for `PgDB`, providing all authentication and authorization
/// related database operations.
#[async_trait]
impl DBAuth for PgDB {
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
            &[&record.id.to_string(), &Json(&record.data), &record.expiry_date],
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
        let db = self.pool.get().await?;
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
    async fn get_user_by_email(&self, email: &str) -> Result<Option<User>> {
        self.fetch_json_opt("select get_user_by_email($1::text);", &[&email])
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

    #[instrument(skip(self, user_id), err)]
    async fn get_user_password(&self, user_id: &Uuid) -> Result<Option<String>> {
        self.fetch_scalar_opt(
            r#"select password from "user" where user_id = $1::uuid;"#,
            &[&user_id],
        )
        .await
    }

    #[instrument(skip(self, user_summary), err)]
    async fn sign_up_user(
        &self,
        user_summary: &UserSummary,
        email_verified: bool,
    ) -> Result<(User, Option<Uuid>)> {
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select * from sign_up_user($1::jsonb, $2::boolean);",
                &[&Json(user_summary), &email_verified],
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
            &[&record.id.to_string(), &Json(&record.data), &record.expiry_date],
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

    #[instrument(skip(self), err)]
    async fn verify_email(&self, code: &Uuid) -> Result<()> {
        self.execute("select verify_email($1::uuid);", &[&code]).await
    }
}
