use anyhow::anyhow;
use axum::body::to_bytes;
use serde::Deserialize;

use crate::{db::contract_tests::helpers::contract_tests_pool, router::serde_qs_config};

use super::*;

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_raised_sqlstates_map_to_handler_responses() -> anyhow::Result<()> {
    // Setup a direct connection to raise errors with each SQLSTATE
    let client = contract_tests_pool()?.get().await?;

    // Check a raised OCG01 becomes a user-facing rejection with its message
    let rejection = client
        .batch_execute(
            "do $$ begin raise exception 'contract rejection' using errcode = 'OCG01'; end $$",
        )
        .await
        .expect_err("OCG01 raise should fail");
    let error = HandlerError::from(anyhow::Error::from(rejection));
    assert!(
        matches!(&error, HandlerError::Database(msg) if msg == "contract rejection"),
        "got {error:?}"
    );
    let (status, body) = render(error).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body, "contract rejection");

    // Check a raised P0001 stays an internal failure with an empty body
    let internal = client
        .batch_execute("do $$ begin raise exception 'contract internal failure'; end $$")
        .await
        .expect_err("P0001 raise should fail");
    let error = HandlerError::from(anyhow::Error::from(internal));
    assert!(matches!(error, HandlerError::Other(_)), "got {error:?}");
    let (status, body) = render(error).await;
    assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR);
    assert_eq!(body, "");

    Ok(())
}

#[tokio::test]
async fn test_handler_errors_map_to_responses() {
    // Setup one error per variant with the response it must render
    let mut report = garde::Report::new();
    report.append(
        garde::Path::new("name"),
        garde::Error::new("length is lower than 1"),
    );
    let cases: Vec<(&str, HandlerError, StatusCode, &str)> = vec![
        ("Auth", HandlerError::Auth, StatusCode::UNAUTHORIZED, ""),
        (
            "Database",
            HandlerError::Database("event has reached capacity".to_string()),
            StatusCode::UNPROCESSABLE_ENTITY,
            "event has reached capacity",
        ),
        (
            "Deserialization",
            HandlerError::Deserialization("missing field `name`".to_string()),
            StatusCode::UNPROCESSABLE_ENTITY,
            INVALID_REQUEST_PAYLOAD,
        ),
        (
            "Forbidden",
            HandlerError::Forbidden,
            StatusCode::FORBIDDEN,
            "",
        ),
        (
            "NotFound",
            HandlerError::NotFound,
            StatusCode::NOT_FOUND,
            "",
        ),
        (
            "Other",
            HandlerError::Other(anyhow!("database unavailable")),
            StatusCode::INTERNAL_SERVER_ERROR,
            "",
        ),
        (
            "Rejected",
            HandlerError::Rejected("ticket type is required".to_string()),
            StatusCode::UNPROCESSABLE_ENTITY,
            "ticket type is required",
        ),
        (
            "Serde",
            HandlerError::Serde(serde_json::from_str::<u8>("x").unwrap_err()),
            StatusCode::INTERNAL_SERVER_ERROR,
            "",
        ),
        (
            "Session",
            HandlerError::Session(tower_sessions::session::Error::SerdeJson(
                serde_json::from_str::<u8>("x").unwrap_err(),
            )),
            StatusCode::INTERNAL_SERVER_ERROR,
            "",
        ),
        (
            "Template",
            HandlerError::Template(askama::Error::Fmt),
            StatusCode::INTERNAL_SERVER_ERROR,
            "",
        ),
        (
            "Validation",
            HandlerError::Validation(report),
            StatusCode::UNPROCESSABLE_ENTITY,
            "name: length is lower than 1\n",
        ),
    ];

    // Check each variant renders its status and body
    for (case, error, expected_status, expected_body) in cases {
        let (status, body) = render(error).await;
        assert_eq!(status, expected_status, "{case}");
        assert_eq!(body, expected_body, "{case}");
    }
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_manager_errors_map_to_responses() {
    // Setup every typed manager and payments readiness error kind with the
    // response it must render.
    // A real OCG01 error needs a database connection, so the classified rows
    // carry the `HandlerError::Database` that `From<anyhow::Error>` produces
    // for it; `db_contracts_raised_sqlstates_map_to_handler_responses` proves
    // that classification against real raised errors.
    let classified_rejection = || {
        anyhow::Error::new(HandlerError::Database(
            "event has reached capacity".to_string(),
        ))
    };
    let internal_failure = || anyhow!("database unavailable");
    let rejected = || "ticket type is required".to_string();
    let cases: Vec<(&str, HandlerError, StatusCode, &str)> = vec![
        (
            "AutomaticTaxReadinessError carried classified rejection",
            AutomaticTaxReadinessError::Unexpected(classified_rejection()).into(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "event has reached capacity",
        ),
        (
            "AutomaticTaxReadinessError correctable rejection",
            AutomaticTaxReadinessError::InvalidAddress.into(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "the venue address is invalid",
        ),
        (
            "AutomaticTaxReadinessError internal failure",
            AutomaticTaxReadinessError::Unexpected(internal_failure()).into(),
            StatusCode::INTERNAL_SERVER_ERROR,
            "",
        ),
        (
            "EnrollmentError carried classified rejection",
            EnrollmentError::Other(classified_rejection()).into(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "event has reached capacity",
        ),
        (
            "EnrollmentError::Rejected",
            EnrollmentError::Rejected(rejected()).into(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "ticket type is required",
        ),
        (
            "EnrollmentError internal failure",
            EnrollmentError::Other(internal_failure()).into(),
            StatusCode::INTERNAL_SERVER_ERROR,
            "",
        ),
        (
            "EventsError carried classified rejection",
            EventsError::Other(classified_rejection()).into(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "event has reached capacity",
        ),
        (
            "EventsError::Rejected",
            EventsError::Rejected(rejected()).into(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "ticket type is required",
        ),
        (
            "EventsError internal failure",
            EventsError::Other(internal_failure()).into(),
            StatusCode::INTERNAL_SERVER_ERROR,
            "",
        ),
        (
            "FiscalSponsorReadinessError carried classified rejection",
            FiscalSponsorReadinessError::Unexpected(classified_rejection()).into(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "event has reached capacity",
        ),
        (
            "FiscalSponsorReadinessError::NotReady",
            FiscalSponsorReadinessError::NotReady(rejected()).into(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "ticket type is required",
        ),
        (
            "FiscalSponsorReadinessError internal failure",
            FiscalSponsorReadinessError::Unexpected(internal_failure()).into(),
            StatusCode::INTERNAL_SERVER_ERROR,
            "",
        ),
        (
            "InboxError carried classified rejection",
            InboxError::Other(classified_rejection()).into(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "event has reached capacity",
        ),
        (
            "InboxError::Rejected",
            InboxError::Rejected(rejected()).into(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "ticket type is required",
        ),
        (
            "InboxError internal failure",
            InboxError::Other(internal_failure()).into(),
            StatusCode::INTERNAL_SERVER_ERROR,
            "",
        ),
        (
            "PaymentsError carried classified rejection",
            PaymentsError::Other(classified_rejection()).into(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "event has reached capacity",
        ),
        (
            "PaymentsError::Rejected",
            PaymentsError::Rejected(rejected()).into(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "ticket type is required",
        ),
        (
            "PaymentsError internal failure",
            PaymentsError::Other(internal_failure()).into(),
            StatusCode::INTERNAL_SERVER_ERROR,
            "",
        ),
    ];

    // Check each kind renders its status and body
    for (case, error, expected_status, expected_body) in cases {
        let (status, body) = render(error).await;
        assert_eq!(status, expected_status, "{case}");
        assert_eq!(body, expected_body, "{case}");
    }
}

#[tokio::test]
async fn test_non_db_anyhow_error_returns_500() {
    let error: HandlerError = anyhow!("some internal error").into();

    assert!(matches!(error, HandlerError::Other(_)), "got {error:?}");
    let (status, body) = render(error).await;
    assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR);
    assert_eq!(body, "");
}

#[tokio::test]
async fn test_serde_qs_error_returns_422_with_fixed_body() {
    // Setup a query string that cannot deserialize into the target
    let parse_error = serde_qs_config()
        .deserialize_str::<Limit>("limit=invalid")
        .unwrap_err();

    // Convert the serde_qs error and render the response
    let error: HandlerError = parse_error.into();
    let (status, body) = render(error).await;

    // Check the parser detail is not exposed
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body, INVALID_REQUEST_PAYLOAD);
}

// Helpers.

/// Minimal query target used to produce deserialization failures.
#[derive(Debug, Deserialize)]
struct Limit {
    #[allow(dead_code)]
    limit: usize,
}

/// Renders the error into a response and returns its status and body text.
async fn render(error: HandlerError) -> (StatusCode, String) {
    let (parts, body) = error.into_response().into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    (parts.status, String::from_utf8(bytes.to_vec()).unwrap())
}
