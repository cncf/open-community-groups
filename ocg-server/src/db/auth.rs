//! Database operations for authentication and authorization.

use anyhow::Result;
use async_trait::async_trait;
use axum_login::tower_sessions::session;
use tokio_postgres::types::Json;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    auth::{User, UserSummary},
    db::PgDB,
    templates::auth::UserDetails,
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
        community_id: &Uuid,
        user_summary: &UserSummary,
        email_verified: bool,
    ) -> Result<(User, Option<Uuid>)>;

    /// Updates an existing session in the database.
    async fn update_session(&self, record: &session::Record) -> Result<()>;

    /// Updates user details in the database.
    async fn update_user_details(&self, user_id: &Uuid, user: &UserDetails) -> Result<()>;

    /// Updates a user's password in the database.
    async fn update_user_password(&self, user_id: &Uuid, new_password: &str) -> Result<()>;

    /// Checks if a user owns a specific community.
    async fn user_owns_community(&self, user_id: &Uuid, community_id: &Uuid) -> Result<bool>;

    /// Checks if a user owns a specific group.
    async fn user_owns_group(&self, user_id: &Uuid, group_id: &Uuid) -> Result<bool>;

    /// Verifies a user's email address using a verification code.
    async fn verify_email(&self, code: &Uuid) -> Result<()>;
}

/// Implementation of `DBAuth` for `PgDB`, providing all authentication and authorization
/// related database operations.
#[async_trait]
impl DBAuth for PgDB {
    #[instrument(skip(self, record), err)]
    async fn create_session(&self, record: &session::Record) -> Result<()> {
        trace!("db: create session");

        let db = self.pool.get().await?;
        db.execute(
            "
            insert into auth_session (
                session_id,
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
        .await?;

        Ok(())
    }

    #[instrument(skip(self, session_id), err)]
    async fn delete_session(&self, session_id: &session::Id) -> Result<()> {
        trace!("db: delete session");

        let db = self.pool.get().await?;
        db.execute(
            "delete from auth_session where session_id = $1::text;",
            &[&session_id.to_string()],
        )
        .await?;

        Ok(())
    }

    #[instrument(skip(self, session_id), err)]
    async fn get_session(&self, session_id: &session::Id) -> Result<Option<session::Record>> {
        trace!("db: get session");

        let db = self.pool.get().await?;
        let row = db
            .query_opt(
                "select data, expires_at from auth_session where session_id = $1::text;",
                &[&session_id.to_string()],
            )
            .await?;

        if let Some(row) = row {
            let record = session::Record {
                id: *session_id,
                data: serde_json::from_value(row.get("data"))?,
                expiry_date: row.get("expires_at"),
            };
            return Ok(Some(record));
        }

        Ok(None)
    }

    #[instrument(skip(self, email), err)]
    async fn get_user_by_email(&self, email: &str) -> Result<Option<User>> {
        trace!("db: get user (by email)");

        let db = self.pool.get().await?;
        let user = db
            .query_one(
                r#"
                select get_user_by_id(
                    (
                        select user_id
                        from "user"
                        where email = $1::text
                        and email_verified = true
                    ),
                    false
                );
                "#,
                &[&email],
            )
            .await?
            .get::<_, Option<serde_json::Value>>(0)
            .map(serde_json::from_value)
            .transpose()?;

        Ok(user)
    }

    #[instrument(skip(self, user_id), err)]
    async fn get_user_by_id(&self, user_id: &Uuid) -> Result<Option<User>> {
        trace!("db: get user (by id)");

        let db = self.pool.get().await?;
        let user = db
            .query_one(
                r#"
                select get_user_by_id(
                    (
                        select user_id from "user"
                        where user_id = $1::uuid
                        and email_verified = true
                    ),
                    false
                );
                "#,
                &[&user_id],
            )
            .await?
            .get::<_, Option<serde_json::Value>>(0)
            .map(serde_json::from_value)
            .transpose()?;

        Ok(user)
    }

    #[instrument(skip(self, username), err)]
    async fn get_user_by_username(&self, username: &str) -> Result<Option<User>> {
        trace!("db: get user (by username)");

        let db = self.pool.get().await?;
        let user = db
            .query_one(
                r#"
                select get_user_by_id(
                    (
                        select user_id from "user"
                        where username = $1::text
                        and email_verified = true
                        and password is not null
                    ),
                    true
                );
                "#,
                &[&username],
            )
            .await?
            .get::<_, Option<serde_json::Value>>(0)
            .map(serde_json::from_value)
            .transpose()?;

        Ok(user)
    }

    #[instrument(skip(self, user_id), err)]
    async fn get_user_password(&self, user_id: &Uuid) -> Result<Option<String>> {
        trace!("db: get user password");

        let db = self.pool.get().await?;
        let password = db
            .query_opt(
                r#"select password from "user" where user_id = $1::uuid;"#,
                &[&user_id],
            )
            .await?
            .map(|row| row.get("password"));

        Ok(password)
    }

    #[instrument(skip(self, user_summary), err)]
    async fn sign_up_user(
        &self,
        community_id: &Uuid,
        user_summary: &UserSummary,
        email_verified: bool,
    ) -> Result<(User, Option<Uuid>)> {
        trace!("db: sign up user");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select * from sign_up_user($1::uuid, $2::jsonb, $3::boolean);",
                &[community_id, &Json(user_summary), &email_verified],
            )
            .await?;

        let user = serde_json::from_value(row.get(0))?;
        let verification_code: Option<Uuid> = row.get(1);

        Ok((user, verification_code))
    }

    #[instrument(skip(self, record), err)]
    async fn update_session(&self, record: &session::Record) -> Result<()> {
        trace!("db: update session");

        let db = self.pool.get().await?;
        db.execute(
            "
            update auth_session
            set
                data = $2::jsonb,
                expires_at = $3::timestamptz
            where session_id = $1::text;
            ",
            &[&record.id.to_string(), &Json(&record.data), &record.expiry_date],
        )
        .await?;

        Ok(())
    }

    #[instrument(skip(self, user), err)]
    async fn update_user_details(&self, user_id: &Uuid, user: &UserDetails) -> Result<()> {
        trace!("db: update user details");

        let db = self.pool.get().await?;
        db.execute(
            "select update_user_details($1::uuid, $2::jsonb);",
            &[user_id, &Json(user)],
        )
        .await?;

        Ok(())
    }

    #[instrument(skip(self, new_password), err)]
    async fn update_user_password(&self, user_id: &Uuid, new_password: &str) -> Result<()> {
        trace!("db: update user password");

        let db = self.pool.get().await?;
        db.execute(
            r#"update "user" set password = $2::text where user_id = $1::uuid;"#,
            &[&user_id, &new_password],
        )
        .await?;

        Ok(())
    }

    #[instrument(skip(self), err)]
    async fn user_owns_community(&self, user_id: &Uuid, community_id: &Uuid) -> Result<bool> {
        trace!("db: check if user owns community");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select user_owns_community($1::uuid, $2::uuid) as owns_community;",
                &[&user_id, &community_id],
            )
            .await?;

        Ok(row.get("owns_community"))
    }

    #[instrument(skip(self), err)]
    async fn user_owns_group(&self, user_id: &Uuid, group_id: &Uuid) -> Result<bool> {
        trace!("db: check if user owns group");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select user_owns_group($1::uuid, $2::uuid) as owns_group;",
                &[&user_id, &group_id],
            )
            .await?;

        Ok(row.get("owns_group"))
    }

    #[instrument(skip(self), err)]
    async fn verify_email(&self, code: &Uuid) -> Result<()> {
        trace!("db: verify email");

        let db = self.pool.get().await?;
        db.execute("select verify_email($1::uuid);", &[&code]).await?;

        Ok(())
    }
}
