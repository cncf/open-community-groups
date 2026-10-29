use axum::{
    body::Body,
    http::{
        HeaderMap, HeaderValue, Request, StatusCode,
        header::{ACCEPT, CACHE_CONTROL, CONTENT_TYPE},
    },
};
use chrono::{TimeZone, Utc};
use serde_json::{Value, json};
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::mock::MockDB,
    handlers::{
        error::{INVALID_REQUEST_PAYLOAD, REQUEST_PAYLOAD_TOO_LARGE},
        tests::{
            DEFAULT_BODY_LIMIT_BYTES, TestRouterBuilder, assert_empty_response,
            assert_html_response, request, sample_badges_cfg, sample_server_cfg,
            sample_site_settings, send,
        },
    },
    router::{CACHE_CONTROL_PRIVATE_NO_STORE, CACHE_CONTROL_PUBLIC_SHARED},
    services::badges::{CredentialInput, EmailIdentity, SsiBadgesManager, png},
    test_util::sample_png,
    types::badges::{
        BadgeSnapshot, BadgeSnapshotIssuer, BadgeStatusList, PublicBadgeSnapshot,
        PublicBadgeSnapshotIssuer, PublicUserBadge, UserBadge,
    },
};

use super::*;

#[test]
fn test_accepts_credential_requires_the_supported_media_type() {
    // Setup labeled Accept headers with the expected representation choice
    let cases = [
        ("supported", "text/html, application/vc+ld+json", true),
        ("ordinary html", "text/html", false),
        (
            "parameterized",
            "application/vc+ld+json; charset=utf-8",
            true,
        ),
        (
            "explicitly rejected",
            "application/vc+ld+json; q=0, application/vc+ld+json; q=invalid",
            false,
        ),
    ];

    // Check representation selection remains explicit
    for (case, accept, expected) in cases {
        let mut headers = HeaderMap::new();
        headers.insert(ACCEPT, HeaderValue::from_static(accept));
        assert_eq!(accepts_credential(&headers), expected, "{case}");
    }
}

#[tokio::test]
async fn test_credential_html_response_uses_public_snapshot_and_cache_contract() {
    // Setup a public award and site settings
    let award = sample_user_badge();
    let user_badge_id = award.user_badge_id;
    let mut db = MockDB::new();
    expect_award_page_reads(&mut db, award);
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(badges_server_config())
        .build()
        .await;

    // Request the browser representation
    let request = request("GET", &format!("/badges/credentials/{user_badge_id}"))
        .header(ACCEPT, "text/html")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the page and representation-sensitive cache headers
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(parts.headers.get("vary").unwrap(), CREDENTIAL_CACHE_VARY);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_PUBLIC_SHARED
    );

    // Check share metadata uses absolute public URLs
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    let url = format!("https://badges.example.test/badges/credentials/{user_badge_id}");
    let image = "https://badges.example.test/images/badges/test-badge.png";
    for tag in [
        "<title>Test Badge badge</title>".to_string(),
        format!(r#"<meta property="og:url" content="{url}">"#),
        format!(r#"<meta property="og:image" content="{image}">"#),
        format!(r#"<meta name="twitter:image" content="{image}">"#),
        r#"src="/images/badges/test-badge.png""#.to_string(),
    ] {
        assert!(body.contains(&tag), "missing {tag}");
    }
}

#[tokio::test]
async fn test_credential_json_ld_response_is_signed_and_shared_cached() {
    // Setup a public award and active signing configuration
    let award = sample_user_badge();
    let user_badge_id = award.user_badge_id;
    let mut db = MockDB::new();
    db.expect_get_public_user_badge()
        .times(1)
        .withf(move |id| *id == user_badge_id)
        .return_once(move |_| Ok(Some(award)));
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(badges_server_config())
        .build()
        .await;

    // Request the signed credential representation explicitly
    let request = request("GET", &format!("/badges/credentials/{user_badge_id}"))
        .header(ACCEPT, "application/vc+ld+json")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Check the signed JSON-LD and bounded shared-cache boundary
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        "application/vc+ld+json"
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_PUBLIC_SHARED
    );
    assert_eq!(parts.headers.get("vary").unwrap(), CREDENTIAL_CACHE_VARY);
    assert_eq!(
        body["id"],
        format!("https://badges.example.test/badges/credentials/{user_badge_id}")
    );
    assert_eq!(body["issuer"]["name"], "Test Group");
    assert_eq!(body["issuer"]["type"], json!(["Profile"]));
    assert_eq!(body["proof"].as_array().unwrap().len(), 1);
    assert_eq!(body["proof"][0]["cryptosuite"], "eddsa-rdfc-2022");
    assert!(!body.to_string().contains("identifier"));
}

#[tokio::test]
async fn test_credential_unknown_award_returns_not_found() {
    // Setup an unknown public award
    let user_badge_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_public_user_badge()
        .times(1)
        .withf(move |id| *id == user_badge_id)
        .return_once(|_| Ok(None));
    let router = TestRouterBuilder::new(db).build().await;

    // Request the missing credential
    let request = request("GET", &format!("/badges/credentials/{user_badge_id}"))
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check unknown opaque identifiers stay private
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_PRIVATE_NO_STORE
    );
}

#[tokio::test]
async fn test_issuer_key_returns_immutable_multikey_document() {
    // Setup a public router with one active signing method
    let group_id = Uuid::new_v4();
    let router = TestRouterBuilder::new(MockDB::new())
        .with_server_cfg(badges_server_config())
        .build()
        .await;

    // Resolve the published key from the issuer profile
    let profile_request = request("GET", &format!("/badges/issuers/{group_id}"))
        .body(Body::empty())
        .unwrap();
    let (_, profile_bytes) = send(router.clone(), profile_request).await;
    let profile: Value = serde_json::from_slice(&profile_bytes).unwrap();
    let key_multibase = profile["verificationMethod"][0]["publicKeyMultibase"]
        .as_str()
        .unwrap()
        .to_string();

    // Request the dereferenceable standalone key document
    let key_request = request(
        "GET",
        &format!("/badges/issuers/{group_id}/keys/{key_multibase}"),
    )
    .body(Body::empty())
    .unwrap();
    let (parts, bytes) = send(router, key_request).await;
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Check the immutable content-addressed Multikey document
    assert_eq!(parts.status, StatusCode::OK);
    let issuer_id = format!("https://badges.example.test/badges/issuers/{group_id}");
    assert_eq!(body["@context"], "https://w3id.org/security/multikey/v1");
    assert_eq!(body["id"], format!("{issuer_id}/keys/{key_multibase}"));
    assert_eq!(body["type"], "Multikey");
    assert_eq!(body["controller"], issuer_id);
    assert_eq!(body["publicKeyMultibase"], key_multibase);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        "public, max-age=31536000, immutable"
    );
}

#[tokio::test]
async fn test_issuer_key_unknown_multibase_returns_not_found() {
    // Setup a public router with one active signing method
    let group_id = Uuid::new_v4();
    let router = TestRouterBuilder::new(MockDB::new())
        .with_server_cfg(badges_server_config())
        .build()
        .await;

    // Request a key document outside the retained allowlist
    let request = request(
        "GET",
        &format!("/badges/issuers/{group_id}/keys/z6MkUnknown"),
    )
    .body(Body::empty())
    .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check unknown keys are not published
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_issuer_returns_stable_public_profile() {
    // Setup a public router with one active signing method
    let group_id = Uuid::new_v4();
    let router = TestRouterBuilder::new(MockDB::new())
        .with_server_cfg(badges_server_config())
        .build()
        .await;

    // Request the issuer profile
    let request = request("GET", &format!("/badges/issuers/{group_id}"))
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Check stable issuer identity and public caching
    assert_eq!(parts.status, StatusCode::OK);
    let issuer_id = format!("https://badges.example.test/badges/issuers/{group_id}");
    let method = &body["verificationMethod"][0];
    assert_eq!(
        body["@context"],
        json!([
            "https://www.w3.org/ns/cid/v1",
            "https://purl.imsglobal.org/spec/ob/v3p0/context-3.0.3.json"
        ])
    );
    assert_eq!(body["id"], issuer_id);
    assert_eq!(body["type"], json!(["Profile"]));
    assert_eq!(body["assertionMethod"][0], method["id"]);
    assert_eq!(body["verificationMethod"].as_array().unwrap().len(), 1);
    assert_eq!(method["controller"], issuer_id);
    assert_eq!(method["type"], "Multikey");
    assert_eq!(
        method["id"],
        format!(
            "{issuer_id}/keys/{}",
            method["publicKeyMultibase"].as_str().unwrap()
        )
    );
    assert!(method["publicKeyMultibase"].as_str().unwrap().starts_with("z6Mk"));
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_PUBLIC_SHARED
    );
}

#[tokio::test]
async fn test_status_list_returns_signed_current_state() {
    // Setup one current status list and active signing configuration
    let status = sample_badge_status_list();
    let status_list_id = status.badge_status_list_id;
    let mut db = MockDB::new();
    db.expect_get_badge_status_list()
        .times(1)
        .withf(move |id| *id == status_list_id)
        .return_once(move |_| Ok(Some(status)));
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(badges_server_config())
        .build()
        .await;

    // Request the signed status-list credential
    let request = request("GET", &format!("/badges/status-lists/{status_list_id}"))
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Check the signed status response and bounded public cache policy
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        "application/vc+ld+json"
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        STATUS_LIST_CACHE_CONTROL
    );
    assert_eq!(body["credentialSubject"]["statusPurpose"], "revocation");
    assert!(body["issuer"].get("type").is_none());
    assert_eq!(body["proof"].as_array().unwrap().len(), 1);
    assert_eq!(body["proof"][0]["cryptosuite"], "eddsa-rdfc-2022");
}

#[tokio::test]
async fn test_status_list_unknown_id_returns_not_found() {
    // Setup an unknown status list
    let status_list_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_badge_status_list()
        .times(1)
        .withf(move |id| *id == status_list_id)
        .return_once(|_| Ok(None));
    let router = TestRouterBuilder::new(db).build().await;

    // Request the missing status list
    let request = request("GET", &format!("/badges/status-lists/{status_list_id}"))
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check missing lists are not synthesized
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_user_profile_badges_returns_public_projection() {
    // Setup one discoverable public badge
    let award = sample_user_badge();
    let expected = vec![PublicUserBadge {
        snapshot: PublicBadgeSnapshot {
            image_file_name: award.snapshot.image_file_name,
            issuer: PublicBadgeSnapshotIssuer {
                community_name: award.snapshot.issuer.community_name,
                group_name: award.snapshot.issuer.group_name,
            },
            name: award.snapshot.name,
        },
        user_badge_id: award.user_badge_id,
    }];
    let output = expected.clone();
    let mut db = MockDB::new();
    db.expect_list_user_public_badges()
        .times(1)
        .withf(move |limit, offset, username| *limit == 50 && *offset == 0 && username == "ada")
        .return_once(move |_, _, _| Ok(output));
    let router = TestRouterBuilder::new(db).build().await;

    // Request the public profile projection
    let request = request("GET", "/users/ada/badges").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;
    let body: Vec<PublicUserBadge> = serde_json::from_slice(&bytes).unwrap();

    // Check only the bounded public DTO crosses the shared-cache boundary
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_PUBLIC_SHARED
    );
    assert_eq!(body, expected);
}

#[tokio::test]
async fn test_user_profile_badges_rejects_page_above_public_cap() {
    // Build a public router whose database must not be queried for invalid pagination
    let router = TestRouterBuilder::new(MockDB::new()).build().await;

    // Request a page larger than the fixed public response cap
    let request = request("GET", "/users/ada/badges?limit=51")
        .body(Body::empty())
        .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check validation rejects the request before any public-profile reads
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        String::from_utf8(bytes.to_vec()).unwrap(),
        "badge pagination is outside the supported range"
    );
}

#[tokio::test]
async fn test_verify_page_is_never_cached() {
    // Setup site settings for the verification form
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .return_once(|| Ok(sample_site_settings()));
    let router = TestRouterBuilder::new(db).build().await;

    // Request the local verification form
    let request = request("GET", "/badges/verify").body(Body::empty()).unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check sensitive verification output cannot be cached
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_NO_STORE
    );
}

#[tokio::test]
async fn test_verify_post_flags_stale_email_bound_award_as_superseded() {
    // Issue and bake one export credential bound to a superseded identity
    let mut award = sample_user_badge();
    award.identity_bound_at = Some(Utc.with_ymd_and_hms(2024, 3, 4, 5, 6, 7).unwrap());
    award.identity_hash =
        Some("1f5c1b4c4459c1197a51122a1e86154bbd1eec1c4bb9e34c7c9e4c4e5f3b2a10".to_string());
    award.identity_salt = Some("fedcba9876543210fedcba9876543210".to_string());
    let server_cfg = badges_server_config();
    let email_identity = EmailIdentity {
        hash: "fa4e696fed1caae3ce9bda21a14b5d7960f8ef36bf1566164dafb09f4c8ac324".to_string(),
        salt: "0123456789abcdef0123456789abcdef".to_string(),
    };
    let png = baked_png(&server_cfg, &award, Some(email_identity)).await;

    // Setup the rebound durable award and verification page settings
    let mut db = MockDB::new();
    expect_award_page_reads(&mut db, award);
    let router = TestRouterBuilder::new(db).with_server_cfg(server_cfg).build().await;

    // Submit the stale exported PNG as multipart form data
    let (parts, bytes) = send(router, png_verify_request(&png)).await;

    // Check the stale export still verifies but is flagged as superseded
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8_lossy(&bytes);
    assert!(body.contains("Authentic but superseded by a newer export"));
    assert!(!body.contains("Valid and active"));
}

#[tokio::test]
async fn test_verify_post_rejects_unreadable_multipart_body() {
    // Setup one unreadable body per multipart error class with its response
    let cases: Vec<(&str, Request<Body>, StatusCode, &str)> = vec![
        (
            "body over the request limit",
            png_verify_request(&vec![0; DEFAULT_BODY_LIMIT_BYTES + 1]),
            StatusCode::PAYLOAD_TOO_LARGE,
            REQUEST_PAYLOAD_TOO_LARGE,
        ),
        (
            "field without a closing boundary",
            verify_request(
                format!(
                    "--{VERIFY_BOUNDARY}\r\nContent-Disposition: form-data; name=\"credential\"\r\n\r\nincomplete"
                )
                .into_bytes(),
            ),
            StatusCode::BAD_REQUEST,
            INVALID_REQUEST_PAYLOAD,
        ),
        (
            "truncated field headers",
            verify_request(
                format!("--{VERIFY_BOUNDARY}\r\nContent-Disposition: form-data; name=\"credential\"")
                    .into_bytes(),
            ),
            StatusCode::BAD_REQUEST,
            INVALID_REQUEST_PAYLOAD,
        ),
    ];

    for (case, request, expected_status, expected_body) in cases {
        // Setup router without database reads, since verification never starts
        let router = TestRouterBuilder::new(MockDB::new()).build().await;

        // Submit the unreadable multipart body
        let (parts, bytes) = send(router, request).await;

        // Check the client error is answered with axum's status and a fixed body
        assert_eq!(parts.status, expected_status, "{case}");
        assert_eq!(String::from_utf8_lossy(&bytes), expected_body, "{case}");
    }
}

#[tokio::test]
async fn test_verify_post_returns_current_local_award() {
    // Setup one resolvable current award
    let award = sample_user_badge();
    let user_badge_id = award.user_badge_id;
    let mut db = MockDB::new();
    expect_award_page_reads(&mut db, award);
    let router = TestRouterBuilder::new(db)
        .with_server_cfg(badges_server_config())
        .build()
        .await;

    // Submit the opaque local award identifier as multipart form data
    let (parts, bytes) = send(router, credential_verify_request(user_badge_id)).await;

    // Check verification renders current public identity without caching
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_NO_STORE
    );
    let body = String::from_utf8_lossy(&bytes);
    assert!(body.contains("Valid and active"));
    assert!(body.contains("Ada"));
    assert!(body.contains("src=\"/images/badges/test-badge.png\""));
    assert!(body.contains("alt=\"Test Badge badge artwork\""));
    assert!(body.contains("datetime=\"2024-01-02T03:04:05+00:00\""));
    assert!(body.contains("January 2, 2024"));
}

#[tokio::test]
async fn test_verify_post_returns_uploaded_award() {
    // Issue and bake one portable credential using the router's signing key
    let award = sample_user_badge();
    let server_cfg = badges_server_config();
    let png = baked_png(&server_cfg, &award, None).await;

    // Setup the matching durable award and verification page settings
    let mut db = MockDB::new();
    expect_award_page_reads(&mut db, award);
    let router = TestRouterBuilder::new(db).with_server_cfg(server_cfg).build().await;

    // Submit the exported PNG as multipart form data
    let (parts, bytes) = send(router, png_verify_request(&png)).await;

    // Check portable verification renders the matched local artwork and award date
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_NO_STORE
    );
    let body = String::from_utf8_lossy(&bytes);
    assert!(body.contains("Valid and active"));
    assert!(body.contains("src=\"/images/badges/test-badge.png\""));
    assert!(body.contains("datetime=\"2024-01-02T03:04:05+00:00\""));
    assert!(body.contains("January 2, 2024"));
}

#[tokio::test]
async fn test_verify_post_returns_uploaded_email_bound_award_without_rendering_identity() {
    // Issue and bake one email-bound export credential matching the stored binding
    let identity_hash = "fa4e696fed1caae3ce9bda21a14b5d7960f8ef36bf1566164dafb09f4c8ac324";
    let identity_salt = "0123456789abcdef0123456789abcdef";
    let mut award = sample_user_badge();
    award.identity_bound_at = Some(Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap());
    award.identity_hash = Some(identity_hash.to_string());
    award.identity_salt = Some(identity_salt.to_string());
    let server_cfg = badges_server_config();
    let email_identity = EmailIdentity {
        hash: identity_hash.to_string(),
        salt: identity_salt.to_string(),
    };
    let png = baked_png(&server_cfg, &award, Some(email_identity)).await;

    // Setup the matching durable award and verification page settings
    let mut db = MockDB::new();
    expect_award_page_reads(&mut db, award);
    let router = TestRouterBuilder::new(db).with_server_cfg(server_cfg).build().await;

    // Submit the exported email-bound PNG as multipart form data
    let (parts, bytes) = send(router, png_verify_request(&png)).await;

    // Check the current email-bound export verifies without rendering its identity
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let body = String::from_utf8_lossy(&bytes);
    assert!(body.contains("Valid and active"));
    assert!(!body.contains("superseded"));
    assert!(!body.contains(identity_hash));
    assert!(!body.contains(identity_salt));
    assert!(!body.to_lowercase().contains("recipient@example.test"));
}

// Helpers.

/// Multipart boundary of the verification requests.
const VERIFY_BOUNDARY: &str = "BADGE-VERIFY-BOUNDARY";

/// Build a server configuration with one active deterministic key identifier.
fn badges_server_config() -> HttpServerConfig {
    HttpServerConfig {
        badges: Some(sample_badges_cfg()),
        ..sample_server_cfg("https://badges.example.test")
    }
}

/// Issues the award's export credential and bakes it into badge artwork.
async fn baked_png(
    server_cfg: &HttpServerConfig,
    award: &UserBadge,
    email_identity: Option<EmailIdentity>,
) -> Vec<u8> {
    let badges_manager =
        SsiBadgesManager::new(&server_cfg.base_url, server_cfg.badges.as_ref().unwrap());
    let credential = badges_manager
        .issue_credential(CredentialInput {
            award,
            created_at: Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap(),
            email_identity,
        })
        .await
        .unwrap();
    let credential = serde_json::to_vec(&credential).unwrap();

    png::bake(&sample_png(512, 512), &credential).unwrap()
}

/// Builds a verification request submitting an award identifier.
fn credential_verify_request(user_badge_id: Uuid) -> Request<Body> {
    verify_request(
        format!(
            "--{VERIFY_BOUNDARY}\r\nContent-Disposition: form-data; name=\"credential\"\r\n\r\n{user_badge_id}\r\n--{VERIFY_BOUNDARY}--\r\n"
        )
        .into_bytes(),
    )
}

/// Expects the award read and site settings read of the public award pages,
/// with the award lookup returning `award`.
fn expect_award_page_reads(db: &mut MockDB, award: UserBadge) {
    let user_badge_id = award.user_badge_id;
    db.expect_get_public_user_badge()
        .times(1)
        .withf(move |id| *id == user_badge_id)
        .return_once(move |_| Ok(Some(award)));
    db.expect_get_site_settings()
        .times(1)
        .return_once(|| Ok(sample_site_settings()));
}

/// Builds a verification request uploading baked badge artwork.
fn png_verify_request(png: &[u8]) -> Request<Body> {
    let mut body = format!(
        "--{VERIFY_BOUNDARY}\r\nContent-Disposition: form-data; name=\"png\"; filename=\"badge.png\"\r\nContent-Type: image/png\r\n\r\n"
    )
    .into_bytes();
    body.extend_from_slice(png);
    body.extend_from_slice(format!("\r\n--{VERIFY_BOUNDARY}--\r\n").as_bytes());

    verify_request(body)
}

/// Build one deterministic current status-list row.
fn sample_badge_status_list() -> BadgeStatusList {
    BadgeStatusList {
        badge_status_list_id: Uuid::new_v4(),
        group_id: Uuid::new_v4(),
        revoked_indexes: vec![1],
    }
}

/// Build one active public badge fixture.
fn sample_user_badge() -> UserBadge {
    let group_id = Uuid::new_v4();
    UserBadge {
        awarded_at: Utc.with_ymd_and_hms(2024, 1, 2, 3, 4, 5).unwrap(),
        badge_status_list_id: Uuid::new_v4(),
        display_order: 0,
        group_id,
        is_listed: true,
        snapshot: BadgeSnapshot {
            criteria: "Attend".to_string(),
            description: "Test badge description".to_string(),
            image_file_name: "test-badge.png".to_string(),
            issuer: BadgeSnapshotIssuer {
                community_id: Uuid::new_v4(),
                community_name: "Test Community".to_string(),
                group_id,
                group_name: "Test Group".to_string(),
            },
            name: "Test Badge".to_string(),
        },
        status_list_index: 1,
        user_badge_id: Uuid::new_v4(),

        badge_id: Some(Uuid::new_v4()),
        event_id: Some(Uuid::new_v4()),
        event_name: Some("Test Event".to_string()),
        identity_bound_at: None,
        identity_hash: None,
        identity_salt: None,
        recipient_name: Some("Ada".to_string()),
        recipient_username: Some("ada".to_string()),
        revocation_reason: None,
        revoked_at: None,
        revoked_by_user_id: None,
        user_id: Some(Uuid::new_v4()),
    }
}

/// Builds a multipart verification request with the encoded body.
fn verify_request(body: Vec<u8>) -> Request<Body> {
    request("POST", "/badges/verify")
        .header(
            CONTENT_TYPE,
            format!("multipart/form-data; boundary={VERIFY_BOUNDARY}"),
        )
        .body(Body::from(body))
        .unwrap()
}
