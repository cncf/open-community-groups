//! Custom extractors for handlers.

use std::{collections::HashMap, sync::Arc};

use axum::{
    Form,
    extract::{FromRequest, FromRequestParts, Path, Request},
    http::{StatusCode, request::Parts},
    response::{IntoResponse, Response},
};
use garde::Validate;
use serde::de::DeserializeOwned;
use tracing::{error, instrument};
use uuid::Uuid;

use crate::{
    auth::{AuthSession, OAuth2ProviderDetails, OidcProviderDetails, User as AuthUser},
    config::{OAuth2Provider, OidcProvider},
    handlers::error::HandlerError,
    router::{self, serde_qs_config},
};

#[cfg(test)]
mod tests;

/// Extractor that resolves a community ID from the request path parameter.
pub(crate) struct CommunityId(pub Uuid);

impl FromRequestParts<router::State> for CommunityId {
    type Rejection = (StatusCode, &'static str);

    #[instrument(skip_all, err(Debug))]
    async fn from_request_parts(
        parts: &mut Parts,
        state: &router::State,
    ) -> Result<Self, Self::Rejection> {
        // Extract community name from path parameter
        let path_params: Path<HashMap<String, String>> = Path::from_request_parts(parts, state)
            .await
            .map_err(|_| (StatusCode::BAD_REQUEST, "invalid path parameters"))?;
        let Some(community_name) = path_params.get("community") else {
            return Err((StatusCode::BAD_REQUEST, "missing community parameter"));
        };

        // Lookup the community id in the database (cached at DB layer)
        if community_name.is_empty() {
            return Err((StatusCode::NOT_FOUND, "community not found"));
        }
        let Some(community_id) =
            state
                .db
                .get_community_id_by_name(community_name)
                .await
                .map_err(|err| {
                    error!(?err, "error looking up community id");
                    (StatusCode::INTERNAL_SERVER_ERROR, "")
                })?
        else {
            return Err((StatusCode::NOT_FOUND, "community not found"));
        };

        Ok(CommunityId(community_id))
    }
}

/// Extractor for the authenticated user from the auth session.
pub(crate) struct CurrentUser(pub AuthUser);

impl FromRequestParts<router::State> for CurrentUser {
    type Rejection = (StatusCode, &'static str);

    #[instrument(skip_all, err(Debug))]
    async fn from_request_parts(
        parts: &mut Parts,
        state: &router::State,
    ) -> Result<Self, Self::Rejection> {
        let Ok(auth_session) = AuthSession::from_request_parts(parts, state).await else {
            return Err((StatusCode::UNAUTHORIZED, "user not logged in"));
        };
        let Some(user) = auth_session.user else {
            return Err((StatusCode::UNAUTHORIZED, "user not logged in"));
        };

        Ok(CurrentUser(user))
    }
}

/// Extractor for `OAuth2` provider details from the authenticated session.
pub(crate) struct OAuth2(pub Arc<OAuth2ProviderDetails>);

impl FromRequestParts<router::State> for OAuth2 {
    type Rejection = (StatusCode, &'static str);

    #[instrument(skip_all, err(Debug))]
    async fn from_request_parts(
        parts: &mut Parts,
        state: &router::State,
    ) -> Result<Self, Self::Rejection> {
        let Ok(provider) = Path::<OAuth2Provider>::from_request_parts(parts, state).await else {
            return Err((StatusCode::BAD_REQUEST, "missing oauth2 provider"));
        };
        let Ok(auth_session) = AuthSession::from_request_parts(parts, state).await else {
            return Err((StatusCode::BAD_REQUEST, "missing auth session"));
        };
        let Some(provider_details) = auth_session.backend.oauth2_providers.get(&provider) else {
            return Err((StatusCode::BAD_REQUEST, "oauth2 provider not supported"));
        };
        Ok(OAuth2(provider_details.clone()))
    }
}

/// Extractor for `Oidc` provider details from the authenticated session.
pub(crate) struct Oidc(pub Arc<OidcProviderDetails>);

impl FromRequestParts<router::State> for Oidc {
    type Rejection = (StatusCode, &'static str);

    #[instrument(skip_all, err(Debug))]
    async fn from_request_parts(
        parts: &mut Parts,
        state: &router::State,
    ) -> Result<Self, Self::Rejection> {
        let Ok(provider) = Path::<OidcProvider>::from_request_parts(parts, state).await else {
            return Err((StatusCode::BAD_REQUEST, "missing oidc provider"));
        };
        let Ok(auth_session) = AuthSession::from_request_parts(parts, state).await else {
            return Err((StatusCode::BAD_REQUEST, "missing auth session"));
        };
        let Some(provider_details) = auth_session.backend.oidc_providers.get(&provider) else {
            return Err((StatusCode::BAD_REQUEST, "oidc provider not supported"));
        };
        Ok(Oidc(provider_details.clone()))
    }
}

/// Extractor for the selected community ID from request context.
/// Returns the Uuid from request extensions populated by middleware.
#[derive(Clone, Copy)]
pub(crate) struct SelectedCommunityId(pub Uuid);

impl FromRequestParts<router::State> for SelectedCommunityId {
    type Rejection = (StatusCode, &'static str);

    #[instrument(skip_all, err(Debug))]
    async fn from_request_parts(
        parts: &mut Parts,
        _state: &router::State,
    ) -> Result<Self, Self::Rejection> {
        parts.extensions.get::<SelectedCommunityId>().copied().ok_or((
            StatusCode::INTERNAL_SERVER_ERROR,
            "missing selected community context",
        ))
    }
}

/// Extractor for the selected group ID from request context.
/// Returns the Uuid from request extensions populated by middleware.
#[derive(Clone, Copy)]
pub(crate) struct SelectedGroupId(pub Uuid);

impl FromRequestParts<router::State> for SelectedGroupId {
    type Rejection = (StatusCode, &'static str);

    #[instrument(skip_all, err(Debug))]
    async fn from_request_parts(
        parts: &mut Parts,
        _state: &router::State,
    ) -> Result<Self, Self::Rejection> {
        parts.extensions.get::<SelectedGroupId>().copied().ok_or((
            StatusCode::INTERNAL_SERVER_ERROR,
            "missing selected group context",
        ))
    }
}

/// Extractor that deserializes and validates form data using Axum's Form extractor.
///
/// Use this for simple, flat form structures. For complex nested structures
/// (arrays, maps), use `ValidatedFormQs` instead. Deserialization failures
/// follow the `HandlerError::Deserialization` contract (fixed body, detail
/// logged) and validation failures return the `garde` report.
pub(crate) struct ValidatedForm<T>(pub T);

impl<T> FromRequest<router::State> for ValidatedForm<T>
where
    T: DeserializeOwned + Validate,
    T::Context: Default,
{
    type Rejection = Response;

    async fn from_request(req: Request, state: &router::State) -> Result<Self, Self::Rejection> {
        // Deserialize form data
        let Form(value) = Form::<T>::from_request(req, state)
            .await
            .map_err(|e| HandlerError::Deserialization(e.to_string()).into_response())?;

        // Validate the deserialized value
        value
            .validate()
            .map_err(|report| HandlerError::Validation(report).into_response())?;

        Ok(ValidatedForm(value))
    }
}

/// Extractor that deserializes and validates form data using `serde_qs`.
///
/// Use this for complex form structures with nested arrays, maps, or deep
/// nesting that Axum's Form extractor cannot handle. Failures follow the same
/// contract as `ValidatedForm`.
pub(crate) struct ValidatedFormQs<T>(pub T);

impl<T> FromRequest<router::State> for ValidatedFormQs<T>
where
    T: DeserializeOwned + Validate,
    T::Context: Default,
{
    type Rejection = Response;

    async fn from_request(req: Request, state: &router::State) -> Result<Self, Self::Rejection> {
        // Read body as string
        let body = String::from_request(req, state)
            .await
            .map_err(|e| (StatusCode::BAD_REQUEST, e.to_string()).into_response())?;

        // Deserialize using serde_qs
        let value: T = state
            .serde_qs_de
            .deserialize_str(&body)
            .map_err(|e| HandlerError::Deserialization(e.to_string()).into_response())?;

        // Validate the deserialized value
        value
            .validate()
            .map_err(|report| HandlerError::Validation(report).into_response())?;

        Ok(ValidatedFormQs(value))
    }
}

/// Extractor that deserializes and validates the request query string.
///
/// The query string is parsed with `serde_qs`, so nested arrays and maps are
/// supported. Failures follow the same contract as `ValidatedForm`.
pub(crate) struct ValidatedQuery<T>(pub T);

impl<T> ValidatedQuery<T>
where
    T: DeserializeOwned + Validate,
    T::Context: Default,
{
    /// Deserializes and validates a raw query string outside of extraction.
    ///
    /// Shared page preparation helpers that receive the query string from
    /// several handlers use this so the parsing contract stays in one place.
    pub(crate) fn parse(raw_query: &str) -> Result<T, HandlerError> {
        Self::parse_with(&serde_qs_config(), raw_query)
    }

    /// Deserializes and validates a raw query string with the given config.
    fn parse_with(config: &serde_qs::Config, raw_query: &str) -> Result<T, HandlerError> {
        let value: T = config.deserialize_str(raw_query)?;
        value.validate()?;
        Ok(value)
    }
}

impl<T> FromRequestParts<router::State> for ValidatedQuery<T>
where
    T: DeserializeOwned + Validate + Send,
    T::Context: Default,
{
    type Rejection = Response;

    fn from_request_parts(
        parts: &mut Parts,
        state: &router::State,
    ) -> impl Future<Output = Result<Self, Self::Rejection>> + Send {
        let raw_query = parts.uri.query().unwrap_or_default();
        let result = Self::parse_with(&state.serde_qs_de, raw_query)
            .map(ValidatedQuery)
            .map_err(IntoResponse::into_response);
        std::future::ready(result)
    }
}
