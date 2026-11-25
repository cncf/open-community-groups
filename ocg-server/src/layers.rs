//! Layer dependency rules for the backend, enforced at test time.
//!
//! `docs/backend.md` defines the dependency direction `router -> handlers ->
//! services -> db`, with `types` and `templates` as leaves. The test in this
//! module reads every Rust source file under the layered directories, collects
//! the `crate::` paths it references (both `use` trees and inline paths), and
//! fails on a forbidden edge that is not listed in an allowance. Allowances
//! exist only for edges that are still being migrated; an allowance that no
//! longer matches any edge also fails the test, so the lists shrink with each
//! migration and never grow silently. Additional tests verify that every
//! cached database read respects `PgExecutor::use_cache`, that every
//! non-singleton `#[cached]` attribute specifies `max_size`, and that every
//! database trait method backed by `fetch_json_*` has at least one ignored
//! `db_contracts_*` test under `db/contract_tests/`.

use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
};

/// Layers checked for forbidden edges, in dependency order.
const LAYERS: &[&str] = &[
    "handlers",
    "activity_tracker",
    "auth",
    "services",
    "db",
    "templates",
    "types",
];

/// Forbidden edges as `(source layer, target layer)`.
const FORBIDDEN_EDGES: &[(&str, &str)] = &[
    ("activity_tracker", "auth"),
    ("activity_tracker", "handlers"),
    ("activity_tracker", "templates"),
    ("auth", "activity_tracker"),
    ("auth", "handlers"),
    ("auth", "templates"),
    ("db", "activity_tracker"),
    ("db", "handlers"),
    ("db", "services"),
    ("db", "templates"),
    ("services", "activity_tracker"),
    ("services", "auth"),
    ("services", "handlers"),
    ("templates", "activity_tracker"),
    ("templates", "db"),
    ("templates", "handlers"),
    ("templates", "services"),
    ("types", "activity_tracker"),
    ("types", "db"),
    ("types", "handlers"),
    ("types", "services"),
    ("types", "templates"),
];

/// Forbidden edges that still exist, as `(source file, target layer)`. Each
/// entry is removed by the migration increment that fixes the file.
const LAYER_EDGE_ALLOWANCES: &[(&str, &str)] = &[];

/// `db`-owned operation types that handlers must not build. A handler that
/// needs one is orchestrating a workflow that belongs to a manager.
const DB_OPERATION_TYPES: &[&str] = &[
    "db::auth::EmailVerificationNotification",
    "db::dashboard::group::EventAdmissionAllocationResult",
    "db::dashboard::group::EventAttendeeCancellationStatus",
    "db::dashboard::group::EventAttendeeInvitationInput",
    "db::dashboard::group::EventCohostNotificationData",
    "db::dashboard::group::EventCohostRef",
    "db::dashboard::group::EventCohostResponse",
    "db::dashboard::group::EventCohostsSync",
    "db::event::AttendEventResult",
    "db::inbox::PostedInboxMessage",
    "db::inbox::StartInboxConversationConflict",
    "db::inbox::StartInboxConversationResult",
    "db::notifications::CommunityCustomNotificationEnqueue",
    "db::notifications::CustomNotificationScope",
    "db::notifications::CustomNotificationTracking",
    "db::payments::CompletePaymentJobRecoveryInput",
    "db::payments::PrepareEventCheckoutPurchaseInput",
    "db::payments::PrepareEventCheckoutPurchaseResult",
];

/// Handler files that still reference `db` operation types, as
/// `(source file, operation type)`. Empty: every workflow that built one has
/// moved behind a manager, and new handler code never adds an entry.
const HANDLER_OPERATION_TYPE_ALLOWANCES: &[(&str, &str)] = &[];

/// Provider traits, trait objects, constructors, and concrete adapters that
/// handlers must not reference directly. Handlers talk to managers instead.
const PROVIDER_TYPES: &[&str] = &[
    "services::images::DbImageStorage",
    "services::images::DynImageStorage",
    "services::images::ImageStorage",
    "services::images::MockImageStorage",
    "services::images::NewImage",
    "services::images::S3ImageStorage",
    "services::images::db::DbImageStorage",
    "services::images::s3::S3ImageStorage",
    "services::meetings::DynMeetingsProvider",
    "services::meetings::DynMeetingsProviders",
    "services::meetings::MeetingsProvider",
    "services::meetings::MockMeetingsProvider",
    "services::meetings::zoom::ZoomMeetingsProvider",
    "services::meetings::zoom::client::ZoomClient",
    "services::notifications::DynEmailSender",
    "services::notifications::EmailSender",
    "services::notifications::LettreEmailSender",
    "services::notifications::MockEmailSender",
    "services::payments::DynPaymentsProvider",
    "services::payments::MockPaymentsProvider",
    "services::payments::build_payments_provider",
];

/// Function, helper, and method call targets collected from a Rust function body.
struct BodyCalls {
    /// Bare function calls (`name(`), excluding resolved nested local functions.
    local_calls: BTreeSet<String>,
    /// Method and DB/executor UFCS calls (`.name(` or `DB*::name(`).
    method_calls: BTreeSet<String>,
    /// Non-DB path-qualified calls as `(qualifier, name)`.
    qualified_calls: BTreeSet<(Option<String>, String)>,
    /// Non-call identifier references (such as helpers passed by value) as `(qualifier, name)`.
    value_refs: BTreeSet<(Option<String>, String)>,
}

/// Parsed `#[cached]` attribute found in a Rust source file.
struct CachedAttribute {
    /// 1-based line number where the attribute begins.
    line: usize,
    /// Byte offset immediately after the closing `]` of the attribute.
    span_end: usize,
    /// Byte offset where the attribute begins (`#`).
    span_start: usize,

    /// Raw argument list inside `#[cached(...)]`, or `None` for bare `#[cached]`.
    args: Option<String>,
}

/// Classification of a `#[cached]` attribute under the `max_size` rule.
enum CachedAttributeKind {
    /// Specifies an explicit `max_size` bound.
    Bounded,
    /// Uses a constant singleton key independent of function arguments.
    Singleton,
    /// Keyed cache without a `max_size` bound.
    Unbounded,
}

/// Summary of `#[cached]` attributes scanned in a Rust source string.
struct CachedAttributeSummary {
    /// Count of attributes specifying `max_size`.
    bounded: usize,
    /// Count of constant-key singleton attributes without `max_size`.
    singleton: usize,
    /// 1-based line numbers of non-singleton attributes missing `max_size`.
    violations: Vec<usize>,
}

/// Summary of cached database reads scanned for `use_cache` guards.
struct CachedBypassSummary {
    /// Count of `#[cached]` attributes inspected outside `#[cfg(test)]`.
    checked: usize,
    /// 1-based line numbers of `#[cached]` reads missing a `use_cache` guard.
    violations: Vec<usize>,
}

/// Parsed function inside `db/contract_tests/` with its test classification
/// and reachable call targets.
struct ContractTestFunction {
    /// Reachable calls invoked by the function body.
    calls: BodyCalls,
    /// Whether the function is an ignored `db_contracts_*` test entry point.
    is_contract_test: bool,
    /// Function identifier name.
    name: String,
}

/// Summary of `fetch_json_*` DB trait methods checked against `db/contract_tests/`.
struct DbContractCoverageSummary {
    /// Count of ignored `db_contracts_*` tests discovered.
    contract_tests: usize,
    /// Discovered JSON-returning DB trait methods as `(relative_path, method, line)`.
    methods: Vec<(String, String, usize)>,
    /// Violations for missing tests, duplicate method names, or unattributed `fetch_json_*` calls.
    violations: Vec<String>,
}

/// Parsed Rust function item with its signature flags and body byte range.
struct FunctionBlock {
    /// Byte offset of the closing `}` of the function body.
    body_end: usize,
    /// Byte offset of the opening `{` of the function body.
    body_start: usize,
    /// Byte offset of the `fn` keyword.
    fn_start: usize,
    /// Whether the function parameter list takes a `self` receiver.
    has_self: bool,
    /// Whether the function parameter list declares a `use_cache` parameter.
    has_use_cache_param: bool,
    /// Function identifier name.
    name: String,
    /// Enclosing declaration scope of the function.
    scope: FunctionScope,
}

/// Enclosing declaration scope of a parsed top-level or `impl`-level function.
#[derive(Clone, Copy, Eq, PartialEq)]
enum FunctionScope {
    /// Method inside an `impl ... DB* for ...` block.
    DbTraitImpl,
    /// Free function at module scope.
    Free,
    /// Method inside an inherent or non-`DB*` trait `impl` block.
    OtherImpl,
}

/// Significant token immediately preceding an identifier while scanning bodies.
#[derive(Clone, Copy, Eq, PartialEq)]
enum PrevToken<'a> {
    /// Preceded by a single `.` member-access operator.
    Dot,
    /// Preceded by the `fn` keyword of a nested function declaration.
    FnKeyword,
    /// Preceded by the `let` keyword of a variable binding.
    LetKeyword,
    /// Preceded by any other token.
    Other,
    /// Preceded by a `::` path separator with its preceding qualifier segment.
    PathSep(Option<&'a str>),
}

/// A source file with the `crate::` paths it references.
struct SourceFile {
    /// Layer the file belongs to.
    layer: &'static str,
    /// Referenced `crate::` paths without the `crate::` prefix.
    paths: BTreeSet<String>,
    /// Path relative to `src/`, with `/` separators.
    relative_path: String,
}

/// Outer attribute markers relevant to contract test discovery.
#[derive(Clone, Copy, Eq, PartialEq)]
enum TestAttribute {
    /// `#[ignore]` or `#[ignore = "..."]`.
    Ignore,
    /// `#[test]` or `#[tokio::test(...)]`.
    Test,
}

#[test]
fn cached_attributes_check_accepts_bounded_and_singleton_caches() {
    // Exercise valid bounded, singleton, comment, and literal fixtures
    let cases: &[(&str, &str, usize, usize)] = &[
        (
            "comments and strings are ignored",
            r##"
                // #[cached(ttl_secs = 60, key = "Uuid", convert = "{ id }")]
                /* outer /* nested */ #[cached] */
                const DOC: &str = "#[cached(ttl_secs = 60, key = \"Uuid\", convert = \"{ id }\")]";
                const RAW: &str = r#"#[cached(ttl_secs = 60, key = "String", convert = "{ name }")]"#;
            "##,
            0,
            0,
        ),
        (
            "bounded keyed cached and concurrent_cached pass",
            r#"
                #[cached(
                    // Keep bounded
                    max_size = 1_000,
                    ttl_secs = 3600,
                    key = "(Uuid, Uuid)",
                    convert = "{ (group_id, event_id) }",
                    sync_writes = "by_key"
                )]
                async fn bounded() {}

                #[concurrent_cached(max_size = 64, key = "Uuid", convert = "{ id }")]
                fn concurrent_bounded() {}
            "#,
            2,
            0,
        ),
        (
            "singleton convert forms pass including trailing comments",
            r##"
                #[cached(
                    ttl_secs = 3600,
                    key = "String",
                    convert = r#"{ String::from("site_stats") }"# // singleton
                )]
                async fn singleton_raw_with_line_comment() {}

                #[cached(
                    ttl_secs = 3600,
                    key = "String",
                    convert = "{ String::from(\"site_stats\") }" /* singleton */,
                    sync_writes = "by_key"
                )]
                async fn singleton_escaped_with_block_comment() {}

                #[cached(ttl_secs = 60, key = "String", convert = r#"{ "site_stats".to_owned() }"#)]
                async fn singleton_to_owned() {}

                #[cached(ttl_secs = 60, key = "String", convert = r#"{ "site_stats".to_string() }"#)]
                async fn singleton_to_string() {}

                #[cached(ttl_secs = 60, key = "()", convert = { () })]
                async fn singleton_unit() {}
            "##,
            0,
            5,
        ),
    ];

    for (case, source, expected_bounded, expected_singleton) in cases {
        let summary = cached_attribute_summary(source);
        assert_eq!(summary.bounded, *expected_bounded, "{case}: bounded count");
        assert_eq!(
            summary.singleton, *expected_singleton,
            "{case}: singleton count"
        );
        assert!(
            summary.violations.is_empty(),
            "{case}: unexpected violations {:?}",
            summary.violations
        );
    }

    // Check unterminated raw strings return None without panicking
    assert_eq!(decode_rust_string_literal(r#"r#""#), None);
}

#[test]
fn cached_attributes_check_flags_unbounded_keyed_caches() {
    // Exercise unbounded attribute forms and literal-adjacent edge cases
    let cases: &[(&str, &str, &[usize])] = &[
        (
            "char literals and lifetimes do not desynchronize scanning",
            concat!(
                "fn helper<'a>(_: &'static str, c: char, b: u8) -> bool {\n",
                "    let _ = ['—','\"'];\n",
                "    let _ = '🦀';\n",
                "    let _ = b'\\'';\n",
                "    matches!(c,'\\''|'\"') && b == b'\"'\n",
                "}\n",
                "#[cached(ttl_secs = 60, key = \"Uuid\", convert = \"{ id }\")]\n",
                "fn after_literals(id: u64) -> u64 { id }\n",
            ),
            &[7],
        ),
        (
            "bare, path-qualified, concurrent, and cfg_attr unbounded caches fail",
            concat!(
                "#[cached]\n",
                "fn bare(id: u64) -> u64 { id }\n",
                "#[cached::cached(ttl_secs = 60, key = \"String\", convert = r#\"{ String::from(name) }\"#)]\n",
                "fn qualified(name: &str) {}\n",
                "#[::cached::cached(ttl_secs = 60, key = \"Uuid\", convert = \"{ id }\")]\n",
                "fn global_qualified(id: u64) {}\n",
                "#[concurrent_cached(ttl_secs = 60, key = \"Uuid\", convert = \"{ id }\")]\n",
                "fn concurrent_unbounded(id: u64) {}\n",
                "#[cfg_attr(not(test), inline, cached(ttl_secs = 60, key = \"Uuid\", convert = \"{ id }\"))]\n",
                "fn cfg_wrapped(id: u64) {}\n",
                "#[cfg_attr(unix, cfg_attr(not(test), cached(ttl_secs = 60, key = \"Uuid\", convert = \"{ id }\")))]\n",
                "fn nested_cfg_wrapped(id: u64) {}\n",
            ),
            &[1, 3, 5, 7, 9, 11],
        ),
        (
            "dynamic expressions mentioning max_size or concatenating literals fail",
            concat!(
                "#[cached(ttl_secs = 60, key = \"String\", convert = r#\"{ format!(\"max_size = {id}\") }\"#)]\n",
                "fn fake_max_size(id: u64) {}\n",
                "#[cached(ttl_secs = 60, key = \"String\", convert = r#\"{ String::from(\"prefix\") + name }\"#)]\n",
                "fn concatenated(name: &str) {}\n",
            ),
            &[1, 3],
        ),
    ];

    for (case, source, expected_violations) in cases {
        let summary = cached_attribute_summary(source);
        assert_eq!(summary.bounded, 0, "{case}: bounded count");
        assert_eq!(summary.singleton, 0, "{case}: singleton count");
        assert_eq!(
            summary.violations, *expected_violations,
            "{case}: violating lines"
        );
    }
}

#[test]
fn cached_bypass_check_accepts_guarded_db_caches() {
    // Setup local, helper-backed, turbofish, and test-only cached fixtures
    let source = r#"
        impl<T: PgExecutor> DBSample for T {
            async fn local_cached(&self) -> Result<()> {
                async fn fetch(_db: &PgClient<'_>) -> Result<()> {
                    Ok(())
                }

                #[cached(ttl_secs = 60, key = "()", convert = "{ () }")]
                async fn inner(db: &PgClient<'_>) -> Result<()> {
                    fetch(db).await
                }

                if !self.use_cache() {
                    let db = self.client().await?;
                    return fetch(&db).await;
                }

                if let Some(value) = cache_probe(&INNER, &()).await {
                    return Ok(value);
                }

                let db = self.client().await?;
                inner(&db).await
            }

            async fn helper_backed(&self, name: &str) -> Result<()> {
                resolve_name(name, self.use_cache()).await
            }

            async fn helper_backed_turbofish(&self, name: &str) -> Result<()> {
                resolve_name::<()>(name, self.use_cache()).await
            }
        }

        #[cached(max_size = 16, ttl_secs = 60, key = "String", convert = "{ String::from(name) }")]
        async fn lookup_name(name: &str) -> Result<()> {
            let _ = name;
            Ok(())
        }

        async fn resolve_name<T>(name: &str, use_cache: bool) -> Result<()> {
            if !use_cache {
                return Ok(());
            }
            if let Some(value) = cache_probe(&LOOKUP_NAME, name).await {
                return Ok(value);
            }
            lookup_name(name).await
        }

        #[cfg(test)]
        mod tests {
            #[cached(max_size = 16, ttl_secs = 60, key = "()", convert = "{ () }")]
            async fn test_only_cache() -> Result<()> {
                Ok(())
            }
        }
    "#;

    // Run the bypass scanner
    let summary = cached_bypass_summary(source);

    // Check both production caches pass and the test-only cache is ignored
    assert_eq!(summary.checked, 2);
    assert!(
        summary.violations.is_empty(),
        "unexpected violations: {:?}",
        summary.violations
    );
}

#[test]
fn cached_bypass_check_flags_nested_guards_and_returns() {
    // Exercise nested guards and non-top-level returns inside bypass branches
    let cases: &[(&str, &str, &[usize])] = &[
        (
            "nested bypass guard inside an outer if fails",
            concat!(
                "impl<T: PgExecutor> DBSample for T {\n",
                "    async fn nested_guard(&self, flag: bool) -> Result<()> {\n",
                "        #[cached(ttl_secs = 60, key = \"()\", convert = \"{ () }\")]\n",
                "        async fn inner() -> Result<()> { Ok(()) }\n",
                "        if flag { if !self.use_cache() { return Ok(()); } }\n",
                "        inner().await\n",
                "    }\n",
                "}\n",
            ),
            &[3],
        ),
        (
            "conditional or closure return inside bypass branch fails",
            concat!(
                "impl<T: PgExecutor> DBSample for T {\n",
                "    async fn conditional_return_guard(&self, flag: bool) -> Result<()> {\n",
                "        #[cached(ttl_secs = 60, key = \"()\", convert = \"{ () }\")]\n",
                "        async fn inner() -> Result<()> { Ok(()) }\n",
                "        if !self.use_cache() { if flag { return Ok(()); } }\n",
                "        inner().await\n",
                "    }\n",
                "    async fn closure_return_guard(&self) -> Result<()> {\n",
                "        #[cached(ttl_secs = 60, key = \"()\", convert = \"{ () }\")]\n",
                "        async fn inner() -> Result<()> { Ok(()) }\n",
                "        if !self.use_cache() { let _ = || return Ok::<(), ()>(()); }\n",
                "        inner().await\n",
                "    }\n",
                "}\n",
            ),
            &[3, 9],
        ),
    ];

    // Check every fixture reports the exact violating cache lines
    for (case, source, expected_violations) in cases {
        let summary = cached_bypass_summary(source);
        assert_eq!(
            summary.checked,
            expected_violations.len(),
            "{case}: checked count"
        );
        assert_eq!(
            summary.violations, *expected_violations,
            "{case}: violating lines"
        );
    }
}

#[test]
fn cached_bypass_check_flags_unguarded_helper_caches() {
    // Exercise unguarded helper-chain, turbofish, and cfg(test) field fixtures
    let cases: &[(&str, &str, &[usize])] = &[
        (
            "module-level helper called with literal true next to unrelated self.use_cache() fails",
            concat!(
                "impl<T: PgExecutor> DBSample for T {\n",
                "    async fn unguarded_caller(&self, name: &str) -> Result<()> {\n",
                "        let _ = self.use_cache();\n",
                "        resolve_name(name, true).await\n",
                "    }\n",
                "}\n",
                "#[cached(max_size = 16, ttl_secs = 60, key = \"String\", convert = \"{ String::from(name) }\")]\n",
                "async fn lookup_name(name: &str) -> Result<()> { Ok(()) }\n",
                "async fn resolve_name(name: &str, use_cache: bool) -> Result<()> {\n",
                "    if !use_cache { return Ok(()); }\n",
                "    lookup_name(name).await\n",
                "}\n",
            ),
            &[7],
        ),
        (
            "module-level helper discarding use_cache without early return fails",
            concat!(
                "impl<T: PgExecutor> DBSample for T {\n",
                "    async fn caller(&self, name: &str) -> Result<()> {\n",
                "        resolve_name(name, self.use_cache()).await\n",
                "    }\n",
                "}\n",
                "#[cached(max_size = 16, ttl_secs = 60, key = \"String\", convert = \"{ String::from(name) }\")]\n",
                "async fn lookup_name(name: &str) -> Result<()> { Ok(()) }\n",
                "async fn resolve_name(name: &str, use_cache: bool) -> Result<()> {\n",
                "    let _ = use_cache;\n",
                "    lookup_name(name).await\n",
                "}\n",
            ),
            &[6],
        ),
        (
            "unguarded turbofish call alongside a guarded call fails",
            concat!(
                "impl<T: PgExecutor> DBSample for T {\n",
                "    async fn guarded_caller(&self, name: &str) -> Result<()> {\n",
                "        resolve_name(name, self.use_cache()).await\n",
                "    }\n",
                "    async fn unguarded_turbofish(&self, name: &str) -> Result<()> {\n",
                "        resolve_name::<()>(name, true).await\n",
                "    }\n",
                "}\n",
                "#[cached(max_size = 16, ttl_secs = 60, key = \"String\", convert = \"{ String::from(name) }\")]\n",
                "async fn lookup_name(name: &str) -> Result<()> { Ok(()) }\n",
                "async fn resolve_name<T>(name: &str, use_cache: bool) -> Result<()> {\n",
                "    if !use_cache { return Ok(()); }\n",
                "    lookup_name(name).await\n",
                "}\n",
            ),
            &[9],
        ),
        (
            "cfg(test) struct field does not mask a following unguarded production impl",
            concat!(
                "struct State {\n",
                "    #[cfg(test)]\n",
                "    map: HashMap<String, usize>,\n",
                "    #[cfg(test)]\n",
                "    probe: bool\n",
                "}\n",
                "impl<T: PgExecutor> DBSample for T {\n",
                "    async fn unguarded(&self) -> Result<()> {\n",
                "        #[cached(ttl_secs = 60, key = \"()\", convert = \"{ () }\")]\n",
                "        async fn inner() -> Result<()> { Ok(()) }\n",
                "        inner().await\n",
                "    }\n",
                "}\n",
            ),
            &[9],
        ),
    ];

    // Check every fixture reports the exact violating cache lines
    for (case, source, expected_violations) in cases {
        let summary = cached_bypass_summary(source);
        assert_eq!(
            summary.checked,
            expected_violations.len(),
            "{case}: checked count"
        );
        assert_eq!(
            summary.violations, *expected_violations,
            "{case}: violating lines"
        );
    }
}

#[test]
fn cached_bypass_check_flags_unguarded_local_caches() {
    // Exercise unguarded, late-guard, discarded, and fallthrough local cache fixtures
    let cases: &[(&str, &str, &[usize])] = &[
        (
            "local cached method without use_cache fails",
            concat!(
                "impl<T: PgExecutor> DBSample for T {\n",
                "    async fn missing_guard(&self) -> Result<()> {\n",
                "        #[cached(ttl_secs = 60, key = \"()\", convert = \"{ () }\")]\n",
                "        async fn inner() -> Result<()> { Ok(()) }\n",
                "        inner().await\n",
                "    }\n",
                "}\n",
            ),
            &[3],
        ),
        (
            "use_cache only in comments, strings, fetch, or inner fails",
            concat!(
                "impl<T: PgExecutor> DBSample for T {\n",
                "    async fn fake_guard(&self) -> Result<()> {\n",
                "        // if !self.use_cache() { return Ok(()); }\n",
                "        let _ = \"if !self.use_cache() { return Ok(()); }\";\n",
                "        async fn fetch(&self) -> Result<()> {\n",
                "            if !self.use_cache() { return Ok(()); }\n",
                "            Ok(())\n",
                "        }\n",
                "        #[cached(ttl_secs = 60, key = \"()\", convert = \"{ () }\")]\n",
                "        async fn inner(&self) -> Result<()> {\n",
                "            if !self.use_cache() { return Ok(()); }\n",
                "            Ok(())\n",
                "        }\n",
                "        inner(self).await\n",
                "    }\n",
                "}\n",
            ),
            &[9],
        ),
        (
            "discarded self.use_cache() result fails",
            concat!(
                "impl<T: PgExecutor> DBSample for T {\n",
                "    async fn discarded_guard(&self) -> Result<()> {\n",
                "        #[cached(ttl_secs = 60, key = \"()\", convert = \"{ () }\")]\n",
                "        async fn inner() -> Result<()> { Ok(()) }\n",
                "        let _ = self.use_cache();\n",
                "        inner().await\n",
                "    }\n",
                "}\n",
            ),
            &[3],
        ),
        (
            "bypass placed after cache_probe fails",
            concat!(
                "impl<T: PgExecutor> DBSample for T {\n",
                "    async fn late_guard(&self) -> Result<()> {\n",
                "        #[cached(ttl_secs = 60, key = \"()\", convert = \"{ () }\")]\n",
                "        async fn inner() -> Result<()> { Ok(()) }\n",
                "        if let Some(v) = cache_probe(&INNER, &()).await { return Ok(v); }\n",
                "        if !self.use_cache() { return Ok(()); }\n",
                "        inner().await\n",
                "    }\n",
                "}\n",
            ),
            &[3],
        ),
        (
            "bypass branch that falls through or calls cached inner fails",
            concat!(
                "impl<T: PgExecutor> DBSample for T {\n",
                "    async fn fallthrough_guard(&self) -> Result<()> {\n",
                "        #[cached(ttl_secs = 60, key = \"()\", convert = \"{ () }\")]\n",
                "        async fn inner() -> Result<()> { Ok(()) }\n",
                "        if !self.use_cache() { let _ = (); }\n",
                "        inner().await\n",
                "    }\n",
                "    async fn calling_inner_in_guard(&self) -> Result<()> {\n",
                "        #[cached(ttl_secs = 60, key = \"()\", convert = \"{ () }\")]\n",
                "        async fn inner() -> Result<()> { Ok(()) }\n",
                "        if !self.use_cache() { return inner().await; }\n",
                "        inner().await\n",
                "    }\n",
                "}\n",
            ),
            &[3, 9],
        ),
    ];

    // Check every fixture reports the exact violating cache lines
    for (case, source, expected_violations) in cases {
        let summary = cached_bypass_summary(source);
        assert_eq!(
            summary.checked,
            expected_violations.len(),
            "{case}: checked count"
        );
        assert_eq!(
            summary.violations, *expected_violations,
            "{case}: violating lines"
        );
    }
}

#[test]
fn cached_db_reads_respect_use_cache() {
    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");

    // Check every production #[cached] database read guards on PgExecutor::use_cache
    let mut total_checked = 0;
    let mut violations = Vec::new();
    for (relative_path, source) in collect_production_db_files(&src_dir) {
        let summary = cached_bypass_summary(&source);
        total_checked += summary.checked;
        for line in summary.violations {
            violations.push(format!(
                "{relative_path}:{line} uses `#[cached]` in `db` without guarding on `use_cache()`"
            ));
        }
    }

    // Check cached database reads were discovered so a broken scan cannot pass
    assert!(
        total_checked > 0,
        "expected production `#[cached]` database reads under {}",
        src_dir.display()
    );
    assert!(
        violations.is_empty(),
        "cached database reads missing `use_cache()` bypass:\n{}",
        violations.join("\n")
    );
}

#[test]
fn crate_paths_flattens_use_trees_and_inline_paths() {
    let source = r"
        use crate::{
            db::{DynDB, pool::Pool as DbPool},
            services::notifications,
            types::{self, event::EventSummary},
        };
        use std::collections::BTreeSet;
        // use crate::templates::Commented;

        fn render(_: crate::handlers::HandlerError) {}
    ";

    assert_eq!(
        crate_paths(source),
        BTreeSet::from(
            [
                "db::DynDB",
                "db::pool::Pool",
                "handlers::HandlerError",
                "services::notifications",
                "types",
                "types::event::EventSummary",
            ]
            .map(String::from)
        )
    );
}

#[test]
fn fetch_json_contract_check_accepts_covered_methods() {
    // Setup DB sources covering direct, cached, turbofish, same-file, and cross-file helpers
    let db_main_source = r#"
#[async_trait]
impl<T> crate::db::DBSample for T where T: PgExecutor + Send + Sync {
    async fn direct_one(&self) -> Result<Foo> {
        self.fetch_json_one("select direct_one()", &[]).await
    }
    async fn direct_opt(&self) -> Result<Option<Foo>> {
        self.fetch_json_opt::<Foo>("select direct_opt()", &[]).await
    }
    async fn cached_one(&self) -> Result<Foo> {
        async fn fetch(db: &PgClient<'_>) -> Result<Foo> {
            db.fetch_json_one("select cached_one()", &[]).await
        }
        let db = self.client().await?;
        fetch(&db).await
    }
    async fn helper_backed(&self) -> Result<Foo> { load_helper_backed(self).await }
    async fn cross_file_backed(&self) -> Result<Foo> { queries::load_cross_file(self).await }
    async fn scalar_only(&self) -> Result<String> {
        // self.fetch_json_one("commented", &[])
        let _ = "self.fetch_json_one(\"literal\", &[])";
        let _ = String::from("ok");
        self.fetch_scalar_one("select 'ok'", &[]).await
    }
}
impl<T: Fn() -> ()> DBClient<T> where T: for<'a> Fn(&'a str) {
    async fn inherent_method(&self) -> Result<()> { Ok(()) }
}
impl From<Foo> for Bar {
    fn from(_: Foo) -> Self { Bar }
}
async fn load_helper_backed<T: PgExecutor>(db: &T) -> Result<Foo> {
    db.fetch_json_one("select helper_backed()", &[]).await
}
#[cfg(test)]
mod tests {
    impl<T> DBSampleTestOnly for T {
        async fn test_only_json(&self) -> Result<Foo> {
            self.fetch_json_one("select test_only_json()", &[]).await
        }
    }
}
"#;
    let db_queries_source = r#"
        pub(super) async fn load_cross_file<T: PgExecutor>(db: &T) -> Result<Foo> { db.fetch_json_one("select 1", &[]).await }
    "#;

    // Setup contract tests covering methods directly, via UFCS, inline mod, and helpers.rs
    let helpers_source = r"
        pub(super) async fn load_shared_helper(db: &PgDB) -> Result<Foo> { db.helper_backed().await }
    ";
    let contract_source = r#"
        #[tokio::test]
        #[ignore = "requires the contract test database"]
        async fn db_contracts_direct_and_ufcs() -> Result<()> {
            let db = contract_tests_db()?;
            let _ = db.direct_one().await?;
            let _ = DBSample::direct_opt(&db).await?;
            let _ = load_cached(&db).await?;
            let _ = helpers::load_shared_helper(&db).await?;
            Ok(())
        }
        mod nested {
            #[tokio::test]
            #[ignore]
            async fn db_contracts_inline_mod() -> Result<()> {
                async fn run_nested(db: &PgDB) -> Result<Foo> { db.cross_file_backed().await }
                let _ = run_nested(&db).await?;
                Ok(())
            }
        }
        async fn load_cached(db: &PgDB) -> Result<Foo> { db.cached_one().await }
    "#;

    // Run the contract coverage summary over the fixtures
    let summary = db_contract_coverage_summary(
        &[
            ("db/queries.rs", db_queries_source),
            ("db/sample.rs", db_main_source),
        ],
        &[
            ("db/contract_tests/helpers.rs", helpers_source),
            ("db/contract_tests/sample.rs", contract_source),
        ],
    );

    // Check exact discovered methods with line numbers, test count, and zero violations
    assert_eq!(
        summary.methods,
        vec![
            ("db/sample.rs".to_string(), "direct_one".to_string(), 4),
            ("db/sample.rs".to_string(), "direct_opt".to_string(), 7),
            ("db/sample.rs".to_string(), "cached_one".to_string(), 10),
            ("db/sample.rs".to_string(), "helper_backed".to_string(), 17),
            (
                "db/sample.rs".to_string(),
                "cross_file_backed".to_string(),
                18
            ),
        ]
    );
    assert_eq!(summary.contract_tests, 2);
    assert!(
        summary.violations.is_empty(),
        "unexpected violations: {:?}",
        summary.violations
    );
}

#[test]
fn fetch_json_contract_check_flags_impersonated_and_leaked_calls() {
    type SourceFiles<'a> = &'a [(&'a str, &'a str)];

    // Exercise qualifier impersonation and cross-file private helper isolation
    let cases: &[(&str, &str, SourceFiles<'_>, &[&str])] = &[
        (
            "non-DB path-qualified fixture call does not impersonate a DB method",
            r#"
                impl<T> DBSample for T {
                    async fn get_group_summary(&self) -> Result<Foo> {
                        self.fetch_json_one("select get_group_summary()", &[]).await
                    }
                }
            "#,
            &[(
                "db/contract_tests/sample.rs",
                r"
                    #[tokio::test]
                    #[ignore]
                    async fn db_contracts_fixture_call() -> Result<()> {
                        let _ = fixture::get_group_summary();
                        Ok(())
                    }
                ",
            )],
            &["get_group_summary"],
        ),
        (
            "private helper in another non-helpers file does not leak coverage",
            r#"
                impl<T> DBSample for T {
                    async fn leaked_method(&self) -> Result<Foo> {
                        self.fetch_json_one("select leaked_method()", &[]).await
                    }
                }
            "#,
            &[
                (
                    "db/contract_tests/alpha.rs",
                    r"
                        #[tokio::test]
                        #[ignore]
                        async fn db_contracts_alpha() -> Result<()> {
                            let _ = shared_name(&db).await?;
                            Ok(())
                        }

                        async fn shared_name(db: &PgDB) -> Result<()> {
                            let _ = db.something_else().await?;
                            Ok(())
                        }
                    ",
                ),
                (
                    "db/contract_tests/beta.rs",
                    r"
                        async fn shared_name(db: &PgDB) -> Result<Foo> {
                            db.leaked_method().await
                        }
                    ",
                ),
            ],
            &["leaked_method"],
        ),
    ];

    // Check every fixture reports the exact missing methods
    for (case, db_source, contract_files, expected_missing) in cases {
        let summary = db_contract_coverage_summary(&[("db/sample.rs", db_source)], contract_files);
        let mut reported: Vec<&str> = summary
            .violations
            .iter()
            .filter_map(|line| line.split('`').nth(1))
            .collect();
        reported.sort_unstable();
        assert_eq!(
            reported, *expected_missing,
            "{case}: {:?}",
            summary.violations
        );
    }
}

#[test]
fn fetch_json_contract_check_flags_invalid_tests_and_dead_helpers() {
    // Setup DB methods targeted only by invalid or unreachable test constructs
    let db_source = r#"
        impl<T> DBSample for T {
            async fn cfg_disabled_only(&self) -> Result<Foo> {
                self.fetch_json_one("select cfg_disabled_only()", &[]).await
            }
            async fn dead_helper_only(&self) -> Result<Foo> {
                self.fetch_json_one("select dead_helper_only()", &[]).await
            }
            async fn unignored_only(&self) -> Result<Foo> {
                self.fetch_json_one("select unignored_only()", &[]).await
            }
            async fn unused_local_only(&self) -> Result<Foo> {
                self.fetch_json_one("select unused_local_only()", &[]).await
            }
            async fn wrong_name_only(&self) -> Result<Foo> {
                self.fetch_json_one("select wrong_name_only()", &[]).await
            }
        }
    "#;
    let contract_source = r"
        #[cfg(any())]
        #[tokio::test]
        #[ignore]
        async fn db_contracts_cfg_disabled() -> Result<()> {
            let _ = db.cfg_disabled_only().await?;
            Ok(())
        }

        #[tokio::test]
        async fn db_contracts_unignored() -> Result<()> {
            let _ = db.unignored_only().await?;
            Ok(())
        }

        #[tokio::test]
        #[ignore]
        async fn db_contracts_unused_local() -> Result<()> {
            async fn never_called(db: &PgDB) -> Result<Foo> {
                db.unused_local_only().await
            }
            Ok(())
        }

        #[tokio::test]
        #[ignore]
        async fn test_wrong_prefix() -> Result<()> {
            let _ = db.wrong_name_only().await?;
            Ok(())
        }

        async fn unused_helper(db: &PgDB) -> Result<Foo> {
            db.dead_helper_only().await
        }
    ";

    // Run the coverage summary
    let summary = db_contract_coverage_summary(
        &[("db/sample.rs", db_source)],
        &[("db/contract_tests/sample.rs", contract_source)],
    );

    // Check none of the invalid tests or dead helpers satisfy coverage
    let mut reported: Vec<&str> = summary
        .violations
        .iter()
        .filter_map(|line| line.split('`').nth(1))
        .collect();
    reported.sort_unstable();
    assert_eq!(
        reported,
        vec![
            "cfg_disabled_only",
            "dead_helper_only",
            "unignored_only",
            "unused_local_only",
            "wrong_name_only",
        ],
        "violations: {:?}",
        summary.violations
    );
}

#[test]
fn fetch_json_contract_check_flags_missing_and_unattributed_calls() {
    // Exercise missing tests, non-code mentions, fail-closed unattributed calls, and duplicate names
    let cases: &[(&str, &str, &str, &[&str])] = &[
        (
            "raw SQL strings and comments do not satisfy coverage",
            r#"
                impl<T> DBSample for T {
                    async fn comment_only(&self) -> Result<Foo> {
                        self.fetch_json_opt("select comment_only()", &[]).await
                    }
                    async fn raw_sql_only(&self) -> Result<Foo> {
                        self.fetch_json_one("select raw_sql_only()", &[]).await
                    }
                }
            "#,
            r#"
                #[tokio::test]
                #[ignore]
                async fn db_contracts_raw_sql_only() -> Result<()> {
                    // db.comment_only().await?;
                    client.query_one("select raw_sql_only()", &[]).await?;
                    Ok(())
                }
            "#,
            &["`comment_only`", "`raw_sql_only`"],
        ),
        (
            "unattributed fetch_json_* calls in trait defaults and non-DB impls fail closed without poisoning scalar methods",
            r#"
                trait DBDefault {
                    async fn default_json(&self) -> Result<Foo> {
                        self.fetch_json_one("select default_json()", &[]).await
                    }
                }
                impl<T> DBSample for T {
                    async fn scalar_with_from(&self) -> Result<String> {
                        let _ = String::from("ok");
                        self.fetch_scalar_one("select 'ok'", &[]).await
                    }
                }
                impl From<Foo> for Bar {
                    fn from(value: Foo) -> Self {
                        let _ = value.fetch_json_one();
                        Bar
                    }
                }
            "#,
            r"
                #[tokio::test]
                #[ignore]
                async fn db_contracts_other() -> Result<()> {
                    let _ = db.other().await?;
                    Ok(())
                }
            ",
            &["calls `fetch_json_*` outside an attributed `DB*` trait method"],
        ),
        (
            "duplicate fetch_json_* method names across DB traits fail",
            r#"
                impl<T> DBFirst for T {
                    async fn shared_read(&self) -> Result<Foo> {
                        self.fetch_json_one("select shared_read()", &[]).await
                    }
                }
                impl<T> DBSecond for T {
                    async fn shared_read(&self) -> Result<Bar> {
                        self.fetch_json_one("select shared_read()", &[]).await
                    }
                }
            "#,
            r"
                #[tokio::test]
                #[ignore]
                async fn db_contracts_shared_read() -> Result<()> {
                    let _ = db.shared_read().await?;
                    Ok(())
                }
            ",
            &["duplicate DB trait method name `shared_read`"],
        ),
    ];

    // Check every fixture triggers the expected violation substrings without false positives
    for (case, db_source, contract_source, expected_substrings) in cases {
        let summary = db_contract_coverage_summary(
            &[("db/sample.rs", db_source)],
            &[("db/contract_tests/sample.rs", contract_source)],
        );
        for expected in *expected_substrings {
            assert!(
                summary.violations.iter().any(|v| v.contains(expected)),
                "{case}: expected violation containing {expected}, got {:?}",
                summary.violations
            );
        }
        assert!(
            !summary.violations.iter().any(|v| v.contains("scalar_with_from")),
            "{case}: scalar method should not be poisoned: {:?}",
            summary.violations
        );
    }
}

#[test]
fn fetch_json_contract_check_handles_qualifiers_and_collisions() {
    // Check generic type args do not act as DB qualifiers, while `<T as DB>::` and helpers/mod.rs do
    let db_main = r#"
        impl<T> DBFirst for T {
            async fn new(&self) -> Result<Foo> {
                let _ = Foo::<PgClient>::fetch_json_x();
                self.fetch_json_one("select new()", &[]).await
            }
            async fn ufcs_qualified(&self) -> Result<Foo> {
                self.fetch_json_one("select ufcs()", &[]).await
            }
            async fn from_shared_helper(&self) -> Result<Foo> {
                self.fetch_json_one("select shared()", &[]).await
            }
            async fn from_callback_ref(&self) -> Result<Foo> {
                self.fetch_json_one("select callback()", &[]).await
            }
            async fn cached_scalar(&self) -> Result<Vec<String>> {
                async fn fetch(db: &PgClient<'_>) -> Result<Vec<String>> {
                    db.fetch_scalar_one("select 1", &[]).await
                }
                let db = self.client().await?;
                fetch(&db).await
            }
            async fn colliding(&self) -> Result<Foo> {
                self.fetch_json_one("select colliding()", &[]).await
            }
        }
        impl<T> DBSecond for T {
            async fn colliding(&self) -> Result<i64> {
                self.fetch_scalar_one("select 1", &[]).await
            }
        }
    "#;
    let db_other = r#"
        async fn fetch(db: &PgClient<'_>) -> Result<Foo> {
            db.fetch_json_one("select unattributed()", &[]).await
        }
    "#;
    let helpers_mod = r"
        pub(super) async fn load_group(db: &PgDB) -> Result<Foo> {
            db.from_shared_helper().await
        }
    ";
    let contract_source = r"
        #[tokio::test]
        #[ignore]
        async fn db_contracts_precision() -> Result<()> {
            let _ = Arc::<PgDB>::new(db);
            let _ = helpers::load_group(&db).await?;
            let _ = run_race(invoke_callback).await?;
            let _ = db.colliding().await?;
            return <PgDB as crate::db::DBFirst>::ufcs_qualified(&db).await;
        }
        async fn load_group(_db: &PgDB) -> Result<()> { Ok(()) }
        async fn invoke_callback(db: &PgDB) -> Result<Foo> { db.from_callback_ref().await }
    ";

    // Run the coverage summary across both DB files and helpers/mod.rs
    let summary = db_contract_coverage_summary(
        &[("db/main.rs", db_main), ("db/other.rs", db_other)],
        &[
            ("db/contract_tests/helpers/mod.rs", helpers_mod),
            ("db/contract_tests/sample.rs", contract_source),
        ],
    );

    // Check only the three real violations fire (missing `new`, unattributed `db/other.rs`, and JSON/scalar collision)
    assert_eq!(
        summary.violations.len(),
        3,
        "violations: {:?}",
        summary.violations
    );
    assert!(
        summary.violations.iter().any(|v| v.contains("DB method `new`")),
        "expected missing contract test for `new`, got {:?}",
        summary.violations
    );
    assert!(
        summary
            .violations
            .iter()
            .any(|v| v.contains("db/other.rs:") && v.contains("outside an attributed")),
        "expected unattributed fetch_json_* in db/other.rs, got {:?}",
        summary.violations
    );
    assert!(
        summary
            .violations
            .iter()
            .any(|v| v.contains("duplicate DB trait method name `colliding`")),
        "expected JSON/scalar collision on `colliding`, got {:?}",
        summary.violations
    );
}

#[test]
fn fetch_json_contract_check_parses_impl_headers_and_modules() {
    // Check `is_db_trait_impl_header` handles inherent, HRTB, and path-qualified impl headers
    let header_cases = [
        (
            "generic bound with arrow",
            "impl<T: Fn() -> ()> DBSample for T",
            true,
        ),
        (
            "path-qualified DB trait with where clause",
            "impl<T> crate::db::DBSample for T where T: PgExecutor",
            true,
        ),
        ("inherent DB-prefixed type", "impl DBClient", false),
        (
            "inherent DB-prefixed type with HRTB for in where clause",
            "impl<T> DBClient<T> where T: for<'a> Fn(&'a str)",
            false,
        ),
    ];
    for (case, header, expected) in header_cases {
        assert_eq!(is_db_trait_impl_header(header), expected, "{case}");
    }

    // Check declared module discovery ignores disabled, inline, and commented `mod` items
    let root_source = r"
        // mod commented_out;
        #[cfg(any())]
        mod disabled;
        pub(crate) mod helpers;
        mod inbox;
        mod inline_only {}
    ";
    assert_eq!(
        declared_contract_module_names(root_source),
        BTreeSet::from(["helpers", "inbox"].map(String::from))
    );
}

#[test]
fn fetch_json_db_methods_have_contract_tests() {
    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");

    // Collect production DB files and compiled contract test modules
    let db_sources = collect_production_db_files(&src_dir);
    let contract_sources = collect_contract_test_files(&src_dir);
    let db_refs: Vec<(&str, &str)> = db_sources
        .iter()
        .map(|(path, source)| (path.as_str(), source.as_str()))
        .collect();
    let contract_refs: Vec<(&str, &str)> = contract_sources
        .iter()
        .map(|(path, source)| (path.as_str(), source.as_str()))
        .collect();

    // Check every production fetch_json_* DB trait method has at least one contract test
    let summary = db_contract_coverage_summary(&db_refs, &contract_refs);
    assert!(
        !summary.methods.is_empty(),
        "expected JSON-returning `fetch_json_*` DB methods under {}",
        src_dir.display()
    );
    assert!(
        summary.contract_tests > 0,
        "expected ignored `db_contracts_*` tests under {}",
        src_dir.join("db/contract_tests").display()
    );
    assert!(
        summary.violations.is_empty(),
        "JSON-returning DB contract-test violations:\n{}",
        summary.violations.join("\n")
    );
}

#[test]
fn handler_provider_check_rejects_image_storage_in_handlers() {
    // Exercise provider imports and manager imports in handler sources
    let cases: &[(&str, &str, &[&str])] = &[
        (
            "use import of DynImageStorage fails",
            "use crate::services::images::DynImageStorage;",
            &[
                "handlers/sample.rs references provider type `crate::services::images::DynImageStorage`",
            ],
        ),
        (
            "inline DynImageStorage and storage provider types fail",
            r"
                use crate::services::images::{ImageStorage, MockImageStorage, NewImage};
                fn serve(_: crate::services::images::DynImageStorage) {}
            ",
            &[
                "handlers/sample.rs references provider type `crate::services::images::DynImageStorage`",
                "handlers/sample.rs references provider type `crate::services::images::ImageStorage`",
                "handlers/sample.rs references provider type `crate::services::images::MockImageStorage`",
                "handlers/sample.rs references provider type `crate::services::images::NewImage`",
            ],
        ),
        (
            "associated item calls and other provider types fail",
            r"
                fn wire() {
                    let _ = crate::services::images::DbImageStorage::new;
                    let _ = crate::services::meetings::zoom::ZoomMeetingsProvider::new;
                    let _ = crate::services::payments::build_payments_provider;
                }
            ",
            &[
                "handlers/sample.rs references provider type `crate::services::images::DbImageStorage`",
                "handlers/sample.rs references provider type `crate::services::meetings::zoom::ZoomMeetingsProvider`",
                "handlers/sample.rs references provider type `crate::services::payments::build_payments_provider`",
            ],
        ),
        (
            "module-qualified and aliased provider references fail",
            r"
                use crate::services;
                use crate::services::images;
                use crate::services::images as img;
                use crate::services::meetings::zoom;
                use images::MockImageStorage;

                fn bad(
                    _: images::DynImageStorage,
                    _: services::notifications::DynEmailSender,
                ) {
                    let _ = img::DbImageStorage::new;
                    let _ = zoom::ZoomMeetingsProvider::new;
                }
            ",
            &[
                "handlers/sample.rs references provider type `crate::services::images::DbImageStorage`",
                "handlers/sample.rs references provider type `crate::services::images::DynImageStorage`",
                "handlers/sample.rs references provider type `crate::services::images::MockImageStorage`",
                "handlers/sample.rs references provider type `crate::services::meetings::zoom::ZoomMeetingsProvider`",
                "handlers/sample.rs references provider type `crate::services::notifications::DynEmailSender`",
            ],
        ),
        (
            "module-qualified manager references and non-provider imports pass",
            r"
                use crate::services::images::{self, DynImagesManager, MockImagesManager};
                fn ok(_: images::UploadImageInput, _: DynImagesManager, _: MockImagesManager) {}
            ",
            &[],
        ),
        (
            "DynImagesManager and MockImagesManager pass",
            "use crate::services::images::{DynImagesManager, MockImagesManager, UploadImageInput};",
            &[],
        ),
    ];

    // Check every fixture matches the expected provider-type violations
    for (case, source, expected) in cases {
        let paths = crate_paths(source);
        let violations = handler_provider_violations("handlers/sample.rs", &paths);
        let expected: Vec<String> = expected.iter().map(|entry| (*entry).to_string()).collect();
        assert_eq!(violations, expected, "{case}");
    }
}

#[test]
fn keyed_cached_reads_specify_max_size() {
    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");

    // Collect every Rust source file under src/
    let mut entries = Vec::new();
    walk_rust_files(&src_dir, &mut entries);
    entries.sort();

    // Check every non-singleton #[cached] attribute specifies max_size
    let mut total_bounded = 0;
    let mut total_singleton = 0;
    let mut violations = Vec::new();
    for entry in entries {
        let relative_path = entry
            .strip_prefix(&src_dir)
            .expect("entry should be under src")
            .to_string_lossy()
            .replace('\\', "/");
        if relative_path == "layers.rs" {
            continue;
        }
        let source = fs::read_to_string(&entry).expect("source file should be readable");
        let summary = cached_attribute_summary(&source);
        total_bounded += summary.bounded;
        total_singleton += summary.singleton;
        for line in summary.violations {
            violations.push(format!(
                "{relative_path}:{line} uses a non-singleton `#[cached]` without `max_size`"
            ));
        }
    }

    // Check both bounded and singleton caches were discovered so a broken scan cannot pass
    assert!(
        total_bounded > 0 && total_singleton > 0,
        "expected both bounded and singleton `#[cached]` attributes under {}",
        src_dir.display()
    );
    assert!(
        violations.is_empty(),
        "unbounded keyed `#[cached]` attributes found:\n{}",
        violations.join("\n")
    );
}

#[test]
fn layer_dependencies_follow_backend_rules() {
    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let files = collect_source_files(&src_dir);
    let mut violations = Vec::new();

    // Check every expected layer directory and root module contributed source files
    for layer in LAYERS {
        let layer_dir = format!("{layer}/");
        let layer_root = format!("{layer}.rs");
        let has_dir = src_dir.join(layer).is_dir();
        let has_root = src_dir.join(&layer_root).is_file();

        assert!(
            has_dir || has_root,
            "neither `{layer_dir}` nor `{layer_root}` exists under `{}`",
            src_dir.display()
        );
        if has_dir {
            assert!(
                files.iter().any(|file| file.relative_path.starts_with(&layer_dir)),
                "no source files found under `{layer_dir}`"
            );
        }
        if has_root {
            assert!(
                files.iter().any(|file| file.relative_path == layer_root),
                "root source file `{layer_root}` was not collected"
            );
        }
    }

    // Check layer edges against the forbidden list and its allowances
    let mut used_layer_allowances = BTreeSet::new();
    for file in &files {
        violations.extend(layer_edge_violations(
            file.layer,
            &file.relative_path,
            &file.paths,
            &mut used_layer_allowances,
        ));
    }
    for allowance in LAYER_EDGE_ALLOWANCES {
        if !used_layer_allowances.contains(allowance) {
            violations.push(format!(
                "stale allowance: {} no longer depends on `crate::{}`",
                allowance.0, allowance.1
            ));
        }
    }

    // Check handler references to db operation types against the inventory
    let mut used_operation_allowances = BTreeSet::new();
    for file in files.iter().filter(|file| file.layer == "handlers") {
        for operation_type in DB_OPERATION_TYPES {
            if !file.paths.contains(*operation_type) {
                continue;
            }
            let allowance = (file.relative_path.as_str(), *operation_type);
            if HANDLER_OPERATION_TYPE_ALLOWANCES.contains(&allowance) {
                used_operation_allowances.insert(allowance);
            } else {
                violations.push(format!(
                    "{} references db operation type `crate::{operation_type}`",
                    file.relative_path
                ));
            }
        }
    }
    for allowance in HANDLER_OPERATION_TYPE_ALLOWANCES {
        if !used_operation_allowances.contains(allowance) {
            violations.push(format!(
                "stale allowance: {} no longer references `crate::{}`",
                allowance.0, allowance.1
            ));
        }
    }

    // Check handlers do not reference storage or external provider types directly
    for file in files.iter().filter(|file| file.layer == "handlers") {
        violations.extend(handler_provider_violations(
            &file.relative_path,
            &file.paths,
        ));
    }

    assert!(
        violations.is_empty(),
        "layer dependency violations:\n{}",
        violations.join("\n")
    );
}

#[test]
fn layer_edge_check_enforces_auth_and_activity_tracker_rules() {
    // Exercise allowed and forbidden dependencies for auth and activity_tracker
    let cases: &[(&str, &str, &str, &str, &[&str])] = &[
        (
            "activity_tracker may depend on services, db, and types",
            "activity_tracker",
            "activity_tracker.rs",
            "use crate::{db::activity_tracker::DynDBActivityTracker, services::workers::BackgroundTasks, types::utm::UtmParams};",
            &[],
        ),
        (
            "activity_tracker cannot depend on auth, handlers, or templates",
            "activity_tracker",
            "activity_tracker.rs",
            "use crate::{auth::User, handlers::error::HandlerError, templates::PageId};",
            &[
                "activity_tracker.rs (activity_tracker) depends on `crate::auth`",
                "activity_tracker.rs (activity_tracker) depends on `crate::handlers`",
                "activity_tracker.rs (activity_tracker) depends on `crate::templates`",
            ],
        ),
        (
            "auth may depend on services, db, and types",
            "auth",
            "auth.rs",
            "use crate::{db::DynDB, services::blocking::BlockingExecutor, types::user::UserProvider};",
            &[],
        ),
        (
            "auth cannot depend on activity_tracker, handlers, or templates",
            "auth",
            "auth.rs",
            "use crate::{activity_tracker::Activity, handlers::error::HandlerError, templates::PageId};",
            &[
                "auth.rs (auth) depends on `crate::activity_tracker`",
                "auth.rs (auth) depends on `crate::handlers`",
                "auth.rs (auth) depends on `crate::templates`",
            ],
        ),
        (
            "services cannot depend on activity_tracker or auth",
            "services",
            "services/sample.rs",
            "use crate::{activity_tracker::Activity, auth::User};",
            &[
                "services/sample.rs (services) depends on `crate::activity_tracker`",
                "services/sample.rs (services) depends on `crate::auth`",
            ],
        ),
        (
            "db cannot depend on activity_tracker",
            "db",
            "db/sample.rs",
            "use crate::activity_tracker::Activity;",
            &["db/sample.rs (db) depends on `crate::activity_tracker`"],
        ),
        (
            "templates cannot depend on activity_tracker",
            "templates",
            "templates/sample.rs",
            "use crate::activity_tracker::Activity;",
            &["templates/sample.rs (templates) depends on `crate::activity_tracker`"],
        ),
        (
            "types cannot depend on activity_tracker",
            "types",
            "types/sample.rs",
            "use crate::activity_tracker::Activity;",
            &["types/sample.rs (types) depends on `crate::activity_tracker`"],
        ),
    ];

    for (case, layer, relative_path, source, expected) in cases {
        let paths = crate_paths(source);
        let mut used_allowances = BTreeSet::new();
        let violations = layer_edge_violations(layer, relative_path, &paths, &mut used_allowances);
        let expected: Vec<String> = expected.iter().map(|entry| (*entry).to_string()).collect();
        assert_eq!(violations, expected, "{case}");
    }
}

/// Summarizes `#[cached]` attributes in `source` by classification and collects
/// the 1-based line numbers of non-singleton attributes missing `max_size`.
fn cached_attribute_summary(source: &str) -> CachedAttributeSummary {
    let mut summary = CachedAttributeSummary {
        bounded: 0,
        singleton: 0,
        violations: Vec::new(),
    };
    for attr in extract_cached_attributes(source) {
        match classify_cached_attribute(attr.args.as_deref()) {
            CachedAttributeKind::Bounded => summary.bounded += 1,
            CachedAttributeKind::Singleton => summary.singleton += 1,
            CachedAttributeKind::Unbounded => summary.violations.push(attr.line),
        }
    }
    summary
}

/// Checks every non-test `#[cached]` attribute in `source` for a `use_cache`
/// bypass guard and returns the count inspected and violating line numbers.
fn cached_bypass_summary(source: &str) -> CachedBypassSummary {
    // Strip test-only items and parse production attributes and function blocks
    let stripped = strip_cfg_test_items(source);
    let attributes = extract_cached_attributes(&stripped);
    let functions = extract_functions(&stripped);
    let mut summary = CachedBypassSummary {
        checked: attributes.len(),
        violations: Vec::new(),
    };

    // Verify each cached attribute has an early bypass before any cache access
    for attr in &attributes {
        let is_guarded = if let Some(enclosing) = functions
            .iter()
            .find(|func| func.body_start < attr.span_start && attr.span_start < func.body_end)
        {
            // Mask nested functions (such as `fetch` and `inner`) in the enclosing method
            let Some(annotated) = parse_annotated_function(&stripped, attr.span_end) else {
                summary.violations.push(attr.line);
                continue;
            };
            let enclosing_body = &stripped[enclosing.body_start + 1..enclosing.body_end];
            let masked_body = mask_nested_functions(enclosing_body);
            let first_cache_access = earliest_call_offset(&masked_body, &annotated.name);
            enclosing.has_self
                && has_early_bypass_guard(&masked_body, true, &annotated.name, first_cache_access)
        } else if let Some(annotated) = parse_annotated_function(&stripped, attr.span_end) {
            // Verify every caller chain to a module-level cached helper checks `use_cache`
            let mut visited = BTreeSet::new();
            visited.insert(annotated.name.clone());
            helper_callers_guard_use_cache(
                &stripped,
                &functions,
                &annotated.name,
                true,
                &mut visited,
            )
        } else {
            // Reject attributes that do not annotate a recognizable function
            false
        };

        // Record the attribute line when no valid bypass guard was found
        if !is_guarded {
            summary.violations.push(attr.line);
        }
    }

    summary
}

/// Classifies a `#[cached]` attribute as bounded (`max_size`), singleton
/// (constant `convert` expression), or unbounded.
fn classify_cached_attribute(args: Option<&str>) -> CachedAttributeKind {
    let Some(args) = args else {
        return CachedAttributeKind::Unbounded;
    };

    // Inspect top-level key/value options for `max_size` and `convert`
    let mut convert_value = None;
    let mut has_max_size = false;
    for item in split_top_level_args(args) {
        let Some((key, value)) = split_top_level_key_value(&item) else {
            continue;
        };
        if key == "max_size" && !value.is_empty() {
            has_max_size = true;
        } else if key == "convert" {
            convert_value = Some(value);
        }
    }

    // Prefer bounded over singleton when both are present
    if has_max_size {
        CachedAttributeKind::Bounded
    } else if convert_value.is_some_and(|value| is_singleton_convert_expr(&value)) {
        CachedAttributeKind::Singleton
    } else {
        CachedAttributeKind::Unbounded
    }
}

/// Classifies an outer attribute body as a Rust/Tokio test or `#[ignore]` marker.
fn classify_test_attribute(inner: &str) -> Option<TestAttribute> {
    let (last_segment, _) = parse_attribute_last_segment(inner)?;
    match last_segment {
        "ignore" => Some(TestAttribute::Ignore),
        "test" => Some(TestAttribute::Test),
        _ => None,
    }
}

/// Collects method/DB-UFCS calls, helper calls, and value references directly
/// in `body`, ignoring comments, string/char literals, and `fn <name>` headers
/// (callers mask nested function bodies first when only reachable nested calls
/// should count).
fn collect_body_calls(body: &str) -> BodyCalls {
    let mut calls = BodyCalls {
        local_calls: BTreeSet::new(),
        method_calls: BTreeSet::new(),
        qualified_calls: BTreeSet::new(),
        value_refs: BTreeSet::new(),
    };

    // Classify every call and identifier reference by its preceding token
    scan_body_identifiers(body, |_, prev, ident, is_call| {
        if is_call {
            match prev {
                PrevToken::Dot => {
                    calls.method_calls.insert(ident.to_string());
                }
                PrevToken::PathSep(qualifier) => {
                    if qualifier.is_some_and(is_db_ufcs_qualifier) {
                        calls.method_calls.insert(ident.to_string());
                    } else {
                        calls
                            .qualified_calls
                            .insert((qualifier.map(String::from), ident.to_string()));
                    }
                }
                PrevToken::Other => {
                    calls.local_calls.insert(ident.to_string());
                }
                PrevToken::FnKeyword | PrevToken::LetKeyword => {}
            }
        } else {
            match prev {
                PrevToken::Other => {
                    calls.value_refs.insert((None, ident.to_string()));
                }
                PrevToken::PathSep(qualifier) => {
                    calls
                        .value_refs
                        .insert((qualifier.map(String::from), ident.to_string()));
                }
                PrevToken::Dot | PrevToken::FnKeyword | PrevToken::LetKeyword => {}
            }
        }
    });

    calls
}

/// Parses an attribute body (including `cfg_attr` wrappers) and appends any
/// matching `cached` or `concurrent_cached` attributes to `out`.
fn collect_cached_attributes(
    inner: &str,
    line: usize,
    span_start: usize,
    span_end: usize,
    out: &mut Vec<CachedAttribute>,
) {
    let bytes = inner.as_bytes();
    let Some((last_segment, index)) = parse_attribute_last_segment(inner) else {
        return;
    };

    // Unwrap `cfg_attr(predicate, attr1, ...)` and inspect every nested attribute
    if last_segment == "cfg_attr" {
        if bytes.get(index) != Some(&b'(') {
            return;
        }
        let Some(close) = find_matching_delimiter(inner, index, b'(', b')') else {
            return;
        };
        let args = &inner[index + 1..close];
        for nested in split_top_level_args(args).into_iter().skip(1) {
            collect_cached_attributes(&nested, line, span_start, span_end, out);
        }
        return;
    }

    // Ignore attributes that do not target `cached` or `concurrent_cached`
    if !matches!(last_segment, "cached" | "concurrent_cached") {
        return;
    }

    // Record bare `#[cached]` or extract the parenthesized argument list
    if index == bytes.len() {
        out.push(CachedAttribute {
            line,
            span_end,
            span_start,
            args: None,
        });
        return;
    }
    if bytes.get(index) != Some(&b'(') {
        return;
    }
    let Some(close) = find_matching_delimiter(inner, index, b'(', b')') else {
        return;
    };
    let trailing = skip_ws_and_comments(inner, close + 1);
    if trailing != bytes.len() {
        return;
    }
    out.push(CachedAttribute {
        line,
        span_end,
        span_start,
        args: Some(inner[index + 1..close].to_string()),
    });
}

/// Collects every compiled contract test module reachable from
/// `src/db/contract_tests.rs` through unconditional `mod <name>;` declarations.
fn collect_contract_test_files(src_dir: &Path) -> Vec<(String, String)> {
    let root_path = src_dir.join("db/contract_tests.rs");
    let root_source =
        fs::read_to_string(&root_path).expect("db/contract_tests.rs should be readable");
    let mut files = vec![("db/contract_tests.rs".to_string(), root_source.clone())];
    collect_contract_test_files_in_dir(
        src_dir,
        &src_dir.join("db/contract_tests"),
        &root_source,
        &mut files,
    );
    files.sort_by(|a, b| a.0.cmp(&b.0));
    files
}

/// Recursively resolves `mod <name>;` children declared in `parent_source`
/// under `mod_dir` and appends their `(relative_path, source)` pairs to `out`.
fn collect_contract_test_files_in_dir(
    src_dir: &Path,
    mod_dir: &Path,
    parent_source: &str,
    out: &mut Vec<(String, String)>,
) {
    for module_name in declared_contract_module_names(parent_source) {
        let file_path = mod_dir.join(format!("{module_name}.rs"));
        let nested_mod_path = mod_dir.join(&module_name).join("mod.rs");
        let (resolved_path, child_dir) = if file_path.is_file() {
            (file_path, mod_dir.join(&module_name))
        } else if nested_mod_path.is_file() {
            (nested_mod_path, mod_dir.join(&module_name))
        } else {
            continue;
        };

        let relative_path = resolved_path
            .strip_prefix(src_dir)
            .expect("contract test file should be under src")
            .to_string_lossy()
            .replace('\\', "/");
        let source =
            fs::read_to_string(&resolved_path).expect("contract test file should be readable");
        collect_contract_test_files_in_dir(src_dir, &child_dir, &source, out);
        out.push((relative_path, source));
    }
}

/// Collects every production database source file (`db.rs` and `db/**/*.rs`,
/// excluding `db/contract_tests*` and `db/mock.rs`) as `(relative_path, source)`.
fn collect_production_db_files(src_dir: &Path) -> Vec<(String, String)> {
    let mut entries = Vec::new();
    walk_rust_files(&src_dir.join("db"), &mut entries);
    entries.push(src_dir.join("db.rs"));
    entries.sort();

    // Filter out test and mock files and read each production source file
    let mut files = Vec::new();
    for entry in entries.into_iter().filter(|entry| entry.is_file()) {
        let relative_path = entry
            .strip_prefix(src_dir)
            .expect("entry should be under src")
            .to_string_lossy()
            .replace('\\', "/");
        if relative_path == "db/contract_tests.rs"
            || relative_path.starts_with("db/contract_tests/")
            || relative_path == "db/mock.rs"
        {
            continue;
        }
        let source = fs::read_to_string(&entry).expect("source file should be readable");
        files.push((relative_path, source));
    }
    files
}

/// Collects calls reachable from `body`, following nested local `fn` bodies
/// only when they are invoked from the enclosing body or another reachable local `fn`.
fn collect_reachable_body_calls(body: &str) -> BodyCalls {
    // Collect direct calls from the body with nested local functions masked out
    let masked = mask_nested_functions(body);
    let mut reachable = collect_body_calls(&masked);

    // Collect nested local functions directly declared in `body`
    let bytes = body.as_bytes();
    let mut nested_fns: Vec<(String, BodyCalls)> = Vec::new();
    let mut index = 0;
    while index < bytes.len() {
        if let Some(next) = skip_non_code(body, index) {
            index = next;
            continue;
        }
        if bytes[index].is_ascii_alphabetic() || bytes[index] == b'_' {
            let start = index;
            while index < bytes.len()
                && (bytes[index].is_ascii_alphanumeric() || bytes[index] == b'_')
            {
                index += 1;
            }
            if &body[start..index] == "fn"
                && let Some(nested) = parse_function_at(body, start)
            {
                let nested_body = &body[nested.body_start + 1..nested.body_end];
                nested_fns.push((nested.name, collect_reachable_body_calls(nested_body)));
                index = nested.body_end + 1;
                continue;
            }
            continue;
        }
        index += body[index..].chars().next().map_or(1, char::len_utf8);
    }

    // Visit nested local functions only when invoked or referenced by reachable code
    let mut visited = vec![false; nested_fns.len()];
    loop {
        let mut changed = false;
        for (idx, (name, calls)) in nested_fns.iter().enumerate() {
            let is_referenced = reachable.local_calls.contains(name)
                || reachable.value_refs.contains(&(None, name.clone()));
            if !visited[idx] && is_referenced {
                visited[idx] = true;
                reachable.local_calls.extend(calls.local_calls.iter().cloned());
                reachable.method_calls.extend(calls.method_calls.iter().cloned());
                reachable
                    .qualified_calls
                    .extend(calls.qualified_calls.iter().cloned());
                reachable.value_refs.extend(calls.value_refs.iter().cloned());
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }

    // Remove nested local function names so they cannot match module-level helpers
    for (name, _) in &nested_fns {
        reachable.local_calls.remove(name);
        reachable.value_refs.remove(&(None, name.clone()));
    }

    reachable
}

/// Collects every Rust source file under the layered directories with the
/// `crate::` paths it references.
fn collect_source_files(src_dir: &Path) -> Vec<SourceFile> {
    let mut files = Vec::new();
    for layer in LAYERS {
        let mut entries = Vec::new();
        walk_rust_files(&src_dir.join(layer), &mut entries);
        if let Some(root_file) = Some(src_dir.join(format!("{layer}.rs"))).filter(|p| p.is_file()) {
            entries.push(root_file);
        }
        for entry in entries {
            let source = fs::read_to_string(&entry).expect("source file should be readable");
            let relative_path = entry
                .strip_prefix(src_dir)
                .expect("entry should be under src")
                .to_string_lossy()
                .replace('\\', "/");
            files.push(SourceFile {
                layer,
                paths: crate_paths(&source),
                relative_path,
            });
        }
    }
    files
}

/// Returns the count of ignored `db_contracts_*` tests and the set of DB
/// method names invoked by those tests (directly or through reachable helpers).
fn contract_tested_methods(contract_files: &[(&str, &str)]) -> (usize, BTreeSet<String>) {
    // Parse functions for every contract test file and locate shared helpers modules
    let mut parsed_files: Vec<Vec<ContractTestFunction>> = Vec::with_capacity(contract_files.len());
    let mut helpers_file_indices = Vec::new();
    for (file_idx, (path, source)) in contract_files.iter().enumerate() {
        if *path == "db/contract_tests/helpers.rs" || *path == "db/contract_tests/helpers/mod.rs" {
            helpers_file_indices.push(file_idx);
        }
        parsed_files.push(extract_contract_test_functions(source));
    }

    // Seed the worklist with every ignored `db_contracts_*` test function
    let mut contract_test_count = 0usize;
    let mut visited: BTreeSet<(usize, usize)> = BTreeSet::new();
    let mut worklist: Vec<(usize, usize)> = Vec::new();
    for (file_idx, functions) in parsed_files.iter().enumerate() {
        for (fn_idx, func) in functions.iter().enumerate() {
            if func.is_contract_test {
                contract_test_count += 1;
                if visited.insert((file_idx, fn_idx)) {
                    worklist.push((file_idx, fn_idx));
                }
            }
        }
    }

    // Walk reachable helpers respecting qualifiers (`helpers::`, `self::`, or bare)
    let mut covered = BTreeSet::new();
    while let Some((file_idx, fn_idx)) = worklist.pop() {
        let func = &parsed_files[file_idx][fn_idx];
        covered.extend(func.calls.method_calls.iter().cloned());

        let bare_refs = func.calls.local_calls.iter().map(|name| (None, name.as_str()));
        let qualified_and_value_refs = func
            .calls
            .qualified_calls
            .iter()
            .chain(func.calls.value_refs.iter())
            .map(|(qualifier, name)| (qualifier.as_deref(), name.as_str()));

        for (qualifier, callee) in bare_refs.chain(qualified_and_value_refs) {
            match qualifier {
                Some("helpers") => {
                    // Resolve `helpers::*` directly in the shared helpers module
                    for &shared_idx in &helpers_file_indices {
                        for (cand_idx, cand) in parsed_files[shared_idx].iter().enumerate() {
                            if cand.name == callee && visited.insert((shared_idx, cand_idx)) {
                                worklist.push((shared_idx, cand_idx));
                            }
                        }
                    }
                }
                Some("self") => {
                    // Resolve `self::*` strictly in the same file
                    for (cand_idx, cand) in parsed_files[file_idx].iter().enumerate() {
                        if cand.name == callee && visited.insert((file_idx, cand_idx)) {
                            worklist.push((file_idx, cand_idx));
                        }
                    }
                }
                None => {
                    // Resolve bare references in the same file first, then fall back to helpers
                    let mut matched_same_file = false;
                    for (cand_idx, cand) in parsed_files[file_idx].iter().enumerate() {
                        if cand.name == callee {
                            matched_same_file = true;
                            if visited.insert((file_idx, cand_idx)) {
                                worklist.push((file_idx, cand_idx));
                            }
                        }
                    }
                    if !matched_same_file {
                        for &shared_idx in &helpers_file_indices {
                            if shared_idx == file_idx {
                                continue;
                            }
                            for (cand_idx, cand) in parsed_files[shared_idx].iter().enumerate() {
                                if cand.name == callee && visited.insert((shared_idx, cand_idx)) {
                                    worklist.push((shared_idx, cand_idx));
                                }
                            }
                        }
                    }
                }
                Some(_) => {}
            }
        }
    }

    (contract_test_count, covered)
}

/// Counts newline characters in `slice`.
fn count_newlines(slice: &str) -> usize {
    slice.matches('\n').count()
}

/// Extracts every `crate::` path referenced by the source: flattened `use`
/// trees, inline `crate::` paths, and module-qualified paths resolved through
/// local `use crate::...` bindings. Comments and string literals are ignored.
fn crate_paths(source: &str) -> BTreeSet<String> {
    let mut paths = BTreeSet::new();
    let mut bindings: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    let code = strip_non_code(source);
    let tokens = tokenize(&code);

    // Collect `use crate::...` imports, local module bindings, and inline `crate::...` paths
    let mut index = 0;
    while index < tokens.len() {
        if tokens[index] == "use" && tokens.get(index + 1) == Some(&"crate") {
            // Flatten the use tree that starts after `crate::`
            index = parse_use_tree(&tokens, index + 3, &[], &mut paths, &mut bindings);
            continue;
        }
        if tokens[index] == "use"
            && let Some(&head) = tokens.get(index + 1)
            && tokens.get(index + 2) == Some(&"::")
            && let Some(prefixes) = bindings.get(head).cloned()
        {
            // Expand follow-up `use <imported_mod>::...` statements
            let mut next_index = index + 1;
            for prefix in prefixes {
                let prefix_segments: Vec<&str> = prefix.split("::").collect();
                next_index = parse_use_tree(
                    &tokens,
                    index + 3,
                    &prefix_segments,
                    &mut paths,
                    &mut bindings,
                );
            }
            index = next_index;
            continue;
        }
        if tokens[index] == "crate" && tokens.get(index + 1) == Some(&"::") {
            // Collect an inline path such as `crate::db::Type`
            let mut segments = Vec::new();
            let mut cursor = index + 2;
            while let Some(segment) = tokens.get(cursor) {
                if !is_identifier(segment) {
                    break;
                }
                segments.push(*segment);
                if tokens.get(cursor + 1) == Some(&"::") {
                    cursor += 2;
                } else {
                    break;
                }
            }
            if !segments.is_empty() {
                paths.insert(segments.join("::"));
            }
            index = cursor;
            continue;
        }
        index += 1;
    }

    // Resolve inline `<binding>::...` paths against recorded `use crate::...` bindings
    if !bindings.is_empty() {
        let mut index = 0;
        let mut in_use = false;
        while index < tokens.len() {
            if tokens[index] == "use" {
                in_use = true;
                index += 1;
                continue;
            }
            if in_use {
                if tokens[index] == ";" {
                    in_use = false;
                }
                index += 1;
                continue;
            }
            let preceded_by_sep = index > 0 && tokens[index - 1] == "::";
            if !preceded_by_sep
                && is_identifier(tokens[index])
                && tokens.get(index + 1) == Some(&"::")
                && let Some(prefixes) = bindings.get(tokens[index])
            {
                let mut rest = Vec::new();
                let mut cursor = index + 2;
                while let Some(segment) = tokens.get(cursor) {
                    if !is_identifier(segment) {
                        break;
                    }
                    rest.push(*segment);
                    if tokens.get(cursor + 1) == Some(&"::") {
                        cursor += 2;
                    } else {
                        break;
                    }
                }
                if !rest.is_empty() {
                    let suffix = rest.join("::");
                    for prefix in prefixes {
                        paths.insert(format!("{prefix}::{suffix}"));
                    }
                }
                index = cursor;
                continue;
            }
            index += 1;
        }
    }

    paths
}

/// Checks every production `fetch_json_*` DB trait method across `db_files`
/// against ignored `db_contracts_*` tests in `contract_files`, failing closed
/// on missing coverage, duplicate method names, or unattributed `fetch_json_*`
/// call sites.
fn db_contract_coverage_summary(
    db_files: &[(&str, &str)],
    contract_files: &[(&str, &str)],
) -> DbContractCoverageSummary {
    // Strip `#[cfg(test)]` items and parse functions and reachable calls per DB file
    let mut stripped_sources = Vec::with_capacity(db_files.len());
    let mut parsed_files = Vec::with_capacity(db_files.len());
    let mut direct_fetch_json = Vec::with_capacity(db_files.len());
    for (_, source) in db_files {
        let stripped = strip_cfg_test_items(source);
        let functions = extract_functions(&stripped);
        let mut file_fns = Vec::with_capacity(functions.len());
        let mut file_direct = Vec::with_capacity(functions.len());
        for func in functions {
            let body = &stripped[func.body_start + 1..func.body_end];
            let calls = collect_reachable_body_calls(body);
            let is_direct = calls.method_calls.iter().any(|name| name.starts_with("fetch_json_"));
            file_direct.push(is_direct);
            file_fns.push((func, calls));
        }
        direct_fetch_json.push(file_direct);
        parsed_files.push(file_fns);
        stripped_sources.push(stripped);
    }

    // Propagate `fetch_json_*` usage through free helpers and collect DB trait methods
    let mut uses_fetch_json = direct_fetch_json.clone();
    propagate_free_helper_usage(&parsed_files, &mut uses_fetch_json);
    let mut attributed: Vec<Vec<bool>> =
        parsed_files.iter().map(|fns| vec![false; fns.len()]).collect();
    let mut worklist = Vec::new();
    let mut methods = Vec::new();
    let mut all_db_method_locations: BTreeMap<String, Vec<(String, usize)>> = BTreeMap::new();
    let mut json_method_names: BTreeSet<String> = BTreeSet::new();
    for (file_idx, (path, _)) in db_files.iter().enumerate() {
        for (fn_idx, (func, _)) in parsed_files[file_idx].iter().enumerate() {
            if func.scope != FunctionScope::DbTraitImpl || !func.has_self {
                continue;
            }
            let line = 1 + count_newlines(&stripped_sources[file_idx][..func.fn_start]);
            all_db_method_locations
                .entry(func.name.clone())
                .or_default()
                .push(((*path).to_string(), line));
            if uses_fetch_json[file_idx][fn_idx] {
                attributed[file_idx][fn_idx] = true;
                worklist.push((file_idx, fn_idx));
                methods.push(((*path).to_string(), func.name.clone(), line));
                json_method_names.insert(func.name.clone());
            }
        }
    }
    while let Some((file_idx, fn_idx)) = worklist.pop() {
        for (target_file, target_fn) in
            resolve_free_helper_targets(&parsed_files, file_idx, &parsed_files[file_idx][fn_idx].1)
        {
            if !attributed[target_file][target_fn] {
                attributed[target_file][target_fn] = true;
                worklist.push((target_file, target_fn));
            }
        }
    }

    // Fail closed on unattributed `fetch_json_*` call sites and DB trait method name collisions
    let mut violations = Vec::new();
    for (file_idx, (path, _)) in db_files.iter().enumerate() {
        let stripped = &stripped_sources[file_idx];
        for offset in find_fetch_json_call_offsets(stripped) {
            let enclosing = parsed_files[file_idx]
                .iter()
                .enumerate()
                .find(|(_, (f, _))| f.body_start < offset && offset < f.body_end);
            let is_attributed = enclosing.is_some_and(|(fn_idx, _)| {
                attributed[file_idx][fn_idx] && direct_fetch_json[file_idx][fn_idx]
            });
            if !is_attributed {
                let line = 1 + count_newlines(&stripped[..offset]);
                violations.push(format!(
                    "{path}:{line} calls `fetch_json_*` outside an attributed `DB*` trait method"
                ));
            }
        }
    }
    for (method, locations) in &all_db_method_locations {
        if locations.len() > 1 && json_method_names.contains(method) {
            let rendered: Vec<_> = locations.iter().map(|(p, l)| format!("{p}:{l}")).collect();
            violations.push(format!(
                "duplicate DB trait method name `{method}` collides at {}",
                rendered.join(", ")
            ));
        }
    }

    // Verify every discovered JSON-returning DB method has a matching contract test
    let (contract_tests, covered_methods) = contract_tested_methods(contract_files);
    for (path, method, line) in &methods {
        if !covered_methods.contains(method) {
            violations.push(format!(
                "{path}:{line} defines JSON-returning DB method `{method}` without an ignored `db_contracts_*` test under `db/contract_tests/`"
            ));
        }
    }

    DbContractCoverageSummary {
        contract_tests,
        methods,
        violations,
    }
}

/// Extracts unconditional external `mod <name>;` module names declared at the
/// top level of `source`, ignoring comments, inline modules, and non-test `#[cfg]` items.
fn declared_contract_module_names(source: &str) -> BTreeSet<String> {
    let stripped = strip_cfg_items_where(source, is_non_test_cfg_attribute);
    let bytes = stripped.as_bytes();
    let mut names = BTreeSet::new();
    let mut index = 0;

    // Scan top-level items for `mod <ident>;` declarations
    while index < bytes.len() {
        if let Some(next) = skip_non_code(&stripped, index) {
            index = next;
            continue;
        }
        if bytes[index] == b'{' {
            index = find_matching_delimiter(&stripped, index, b'{', b'}')
                .map_or(bytes.len(), |close| close + 1);
            continue;
        }
        if bytes[index].is_ascii_alphabetic() || bytes[index] == b'_' {
            let start = index;
            while index < bytes.len()
                && (bytes[index].is_ascii_alphanumeric() || bytes[index] == b'_')
            {
                index += 1;
            }
            if &stripped[start..index] == "mod" {
                let name_start = skip_ws_and_comments(&stripped, index);
                let mut name_end = name_start;
                while name_end < bytes.len()
                    && (bytes[name_end].is_ascii_alphanumeric() || bytes[name_end] == b'_')
                {
                    name_end += 1;
                }
                let after = skip_ws_and_comments(&stripped, name_end);
                if name_end > name_start && bytes.get(after) == Some(&b';') {
                    names.insert(stripped[name_start..name_end].to_string());
                    index = after + 1;
                    continue;
                }
            }
            continue;
        }
        index += stripped[index..].chars().next().map_or(1, char::len_utf8);
    }

    names
}

/// Decodes a single Rust string literal (normal or raw) that spans the entire
/// trimmed input.
fn decode_rust_string_literal(input: &str) -> Option<String> {
    let trimmed = input.trim();
    let bytes = trimmed.as_bytes();

    // Decode a raw string literal such as r"..." or r#"..."#
    if let Some((prefix_len, hashes)) = raw_string_prefix(bytes, 0) {
        let end = find_raw_string_end(bytes, 0, prefix_len, hashes)?;
        if end == bytes.len() {
            let content_end = end - 1 - hashes;
            return Some(trimmed[prefix_len..content_end].to_string());
        }
        return None;
    }

    // Decode a standard double-quoted string literal
    if bytes.first() != Some(&b'"') {
        return None;
    }
    let mut out = String::new();
    let mut chars = trimmed[1..].chars();
    while let Some(ch) = chars.next() {
        match ch {
            '"' => {
                return chars.as_str().is_empty().then_some(out);
            }
            '\\' => {
                let escaped = chars.next()?;
                match escaped {
                    '"' => out.push('"'),
                    '\\' => out.push('\\'),
                    'n' => out.push('\n'),
                    'r' => out.push('\r'),
                    't' => out.push('\t'),
                    other => {
                        out.push('\\');
                        out.push(other);
                    }
                }
            }
            other => out.push(other),
        }
    }
    None
}

/// Returns the earliest byte offset in `code` where either `cache_probe` or
/// `target` is invoked.
fn earliest_call_offset(code: &str, target: &str) -> Option<usize> {
    let probe_pos = find_function_calls(code, "cache_probe")
        .into_iter()
        .map(|(offset, _)| offset)
        .min();
    let target_pos = find_function_calls(code, target)
        .into_iter()
        .map(|(offset, _)| offset)
        .min();

    match (probe_pos, target_pos) {
        (Some(a), Some(b)) => Some(a.min(b)),
        (a, b) => a.or(b),
    }
}

/// Extracts every `#[cached]` or `#[concurrent_cached]` outer attribute from
/// `source`, ignoring occurrences inside comments and literals.
fn extract_cached_attributes(source: &str) -> Vec<CachedAttribute> {
    let mut attributes = Vec::new();
    let bytes = source.as_bytes();
    let mut index = 0;
    let mut line = 1usize;

    while index < bytes.len() {
        // Skip comments and string or char literals so they never match attributes
        if let Some(next) = skip_non_code(source, index) {
            line += count_newlines(&source[index..next]);
            index = next;
            continue;
        }

        if bytes[index] == b'#' {
            let attr_line = line;
            let attr_start = index;
            let mut cursor = skip_ws_and_comments(source, index + 1);
            if bytes.get(cursor) == Some(&b'[') {
                // Find the matching closing bracket of the outer attribute
                let content_start = cursor + 1;
                if let Some(content_end) = find_matching_delimiter(source, cursor, b'[', b']') {
                    let inner = &source[content_start..content_end];
                    cursor = content_end + 1;
                    collect_cached_attributes(
                        inner,
                        attr_line,
                        attr_start,
                        cursor,
                        &mut attributes,
                    );
                    line += count_newlines(&source[index..cursor]);
                    index = cursor;
                    continue;
                }
            }
        }

        if bytes[index] == b'\n' {
            line += 1;
        }
        index += source[index..].chars().next().map_or(1, char::len_utf8);
    }

    attributes
}

/// Extracts top-level and inline-`mod` functions from a contract test file
/// together with their test attributes and reachable body call sets.
fn extract_contract_test_functions(source: &str) -> Vec<ContractTestFunction> {
    let stripped = strip_cfg_items_where(source, is_non_test_cfg_attribute);
    let test_attrs = extract_test_attributes(&stripped);
    let functions = extract_functions(&stripped);

    // Pair each function with its discovered test markers and reachable calls
    functions
        .into_iter()
        .map(|func| {
            let (has_test, has_ignore) =
                test_attrs.get(&func.fn_start).copied().unwrap_or((false, false));
            let body = &stripped[func.body_start + 1..func.body_end];
            let calls = collect_reachable_body_calls(body);
            let is_contract_test = has_test && has_ignore && func.name.starts_with("db_contracts_");
            ContractTestFunction {
                calls,
                is_contract_test,
                name: func.name,
            }
        })
        .collect()
}

/// Extracts top-level and `impl`-level function definitions with bodies from
/// `source`, ignoring comments, literals, and nested local functions.
fn extract_functions(source: &str) -> Vec<FunctionBlock> {
    let mut functions = Vec::new();
    extract_functions_in_range(source, 0, source.len(), FunctionScope::Free, &mut functions);
    functions
}

/// Scans `source[start..end]` for function definitions, descending into `impl`
/// and inline `mod` blocks.
fn extract_functions_in_range(
    source: &str,
    start: usize,
    end: usize,
    scope: FunctionScope,
    out: &mut Vec<FunctionBlock>,
) {
    let bytes = source.as_bytes();
    let mut index = start;

    while index < end {
        if let Some(next) = skip_non_code(source, index) {
            index = next.min(end);
            continue;
        }

        // Read identifier tokens to match `fn`, `impl`, or inline `mod`
        if bytes[index].is_ascii_alphabetic() || bytes[index] == b'_' {
            let ident_start = index;
            while index < end && (bytes[index].is_ascii_alphanumeric() || bytes[index] == b'_') {
                index += 1;
            }
            let ident = &source[ident_start..index];
            match ident {
                "fn" => {
                    if let Some(mut func) = parse_function_at(source, ident_start)
                        && func.body_end < end
                    {
                        let next_index = func.body_end + 1;
                        func.scope = scope;
                        out.push(func);
                        index = next_index;
                        continue;
                    }
                }
                "impl" | "mod" => {
                    // Advance to the block opening `{` or declaration terminator `;`
                    let mut cursor = index;
                    let mut paren_depth = 0usize;
                    let mut bracket_depth = 0usize;
                    while cursor < end {
                        if let Some(next) = skip_non_code(source, cursor) {
                            cursor = next.min(end);
                            continue;
                        }
                        match bytes[cursor] {
                            b'(' => paren_depth += 1,
                            b')' => paren_depth = paren_depth.saturating_sub(1),
                            b'[' => bracket_depth += 1,
                            b']' => bracket_depth = bracket_depth.saturating_sub(1),
                            b';' if paren_depth == 0 && bracket_depth == 0 => {
                                index = cursor + 1;
                                break;
                            }
                            b'{' if paren_depth == 0 && bracket_depth == 0 => {
                                if let Some(close) =
                                    find_matching_delimiter(source, cursor, b'{', b'}')
                                    && close < end
                                {
                                    let child_scope = if ident == "mod" {
                                        FunctionScope::Free
                                    } else if is_db_trait_impl_header(&source[ident_start..cursor])
                                    {
                                        FunctionScope::DbTraitImpl
                                    } else {
                                        FunctionScope::OtherImpl
                                    };
                                    extract_functions_in_range(
                                        source,
                                        cursor + 1,
                                        close,
                                        child_scope,
                                        out,
                                    );
                                    index = close + 1;
                                } else {
                                    index = end;
                                }
                                break;
                            }
                            _ => {}
                        }
                        cursor += source[cursor..].chars().next().map_or(1, char::len_utf8);
                    }
                    continue;
                }
                _ => {}
            }
            continue;
        }

        // Skip brace-delimited non-function blocks such as structs, enums, or traits
        if bytes[index] == b'{' {
            if let Some(close) = find_matching_delimiter(source, index, b'{', b'}')
                && close < end
            {
                index = close + 1;
                continue;
            }
            break;
        }

        index += source[index..].chars().next().map_or(1, char::len_utf8);
    }
}

/// Extracts the final path segment of the trait (or type) from the interior of
/// a qualified path `<Type as Trait>::` or `<Type>::`.
fn extract_qualified_path_trait(inner: &str) -> Option<&str> {
    let bytes = inner.as_bytes();
    let mut index = 0;
    let mut angle_depth = 0usize;
    let mut paren_depth = 0usize;
    let mut bracket_depth = 0usize;
    let mut target_start = 0usize;

    // Locate a top-level `as` keyword to isolate the trait portion of `<Type as Trait>`
    while index < bytes.len() {
        if let Some(next) = skip_non_code(inner, index) {
            index = next;
            continue;
        }
        if angle_depth == 0
            && paren_depth == 0
            && bracket_depth == 0
            && (bytes[index].is_ascii_alphabetic() || bytes[index] == b'_')
        {
            let start = index;
            while index < bytes.len()
                && (bytes[index].is_ascii_alphanumeric() || bytes[index] == b'_')
            {
                index += 1;
            }
            if &inner[start..index] == "as" {
                target_start = index;
                break;
            }
            continue;
        }
        match bytes[index] {
            b'(' => paren_depth += 1,
            b')' => paren_depth = paren_depth.saturating_sub(1),
            b'[' => bracket_depth += 1,
            b']' => bracket_depth = bracket_depth.saturating_sub(1),
            b'<' if paren_depth == 0 && bracket_depth == 0 => angle_depth += 1,
            b'>' if paren_depth == 0
                && bracket_depth == 0
                && !matches!(bytes.get(index.wrapping_sub(1)), Some(b'-' | b'=')) =>
            {
                angle_depth = angle_depth.saturating_sub(1);
            }
            _ => {}
        }
        index += inner[index..].chars().next().map_or(1, char::len_utf8);
    }

    // Take the final identifier segment before any generic arguments
    let tail = trim_ws_and_comments(&inner[target_start..]);
    let head = tail.split('<').next().unwrap_or("");
    head.rsplit("::")
        .map(trim_ws_and_comments)
        .find(|segment| !segment.is_empty() && is_identifier(segment))
}

/// Maps each annotated function's `fn_start` offset to `(has_test, has_ignore)`
/// markers found on its outer attributes.
fn extract_test_attributes(source: &str) -> BTreeMap<usize, (bool, bool)> {
    let bytes = source.as_bytes();
    let mut markers: BTreeMap<usize, (bool, bool)> = BTreeMap::new();
    let mut index = 0;

    // Scan outer attributes and attach `test` / `ignore` markers to their target function
    while index < bytes.len() {
        if let Some(next) = skip_non_code(source, index) {
            index = next;
            continue;
        }
        if bytes[index] == b'#' {
            let open = skip_ws_and_comments(source, index + 1);
            if bytes.get(open) == Some(&b'[')
                && let Some(close) = find_matching_delimiter(source, open, b'[', b']')
            {
                if let Some(marker) = classify_test_attribute(&source[open + 1..close])
                    && let Some(func) = parse_annotated_function(source, close + 1)
                {
                    let entry = markers.entry(func.fn_start).or_insert((false, false));
                    match marker {
                        TestAttribute::Test => entry.0 = true,
                        TestAttribute::Ignore => entry.1 = true,
                    }
                }
                index = close + 1;
                continue;
            }
        }
        index += source[index..].chars().next().map_or(1, char::len_utf8);
    }

    markers
}

/// Returns the byte offset immediately after the item, field, or variant
/// annotated by a `#[cfg(test)]` attribute ending at `after_attr`.
fn find_cfg_test_item_end(source: &str, after_attr: usize) -> usize {
    let bytes = source.as_bytes();

    // Skip sibling outer attributes attached to the same syntax node
    let mut cursor = skip_ws_and_comments(source, after_attr);
    while bytes.get(cursor) == Some(&b'#') {
        let attr_open = skip_ws_and_comments(source, cursor + 1);
        if bytes.get(attr_open) == Some(&b'[')
            && let Some(attr_close) = find_matching_delimiter(source, attr_open, b'[', b']')
        {
            cursor = skip_ws_and_comments(source, attr_close + 1);
        } else {
            break;
        }
    }

    // Scan to the end of the gated item (`;` / `{ ... }`) or field/variant (`,` / before `}`)
    let mut paren_depth = 0usize;
    let mut bracket_depth = 0usize;
    let mut angle_depth = 0usize;
    let mut in_expr = false;
    let mut in_where = false;
    while cursor < bytes.len() {
        if let Some(next) = skip_non_code(source, cursor) {
            cursor = next;
            continue;
        }
        if paren_depth == 0
            && bracket_depth == 0
            && angle_depth == 0
            && (bytes[cursor].is_ascii_alphabetic() || bytes[cursor] == b'_')
        {
            let ident_start = cursor;
            while cursor < bytes.len()
                && (bytes[cursor].is_ascii_alphanumeric() || bytes[cursor] == b'_')
            {
                cursor += 1;
            }
            if &source[ident_start..cursor] == "where" {
                in_where = true;
            }
            continue;
        }
        match bytes[cursor] {
            b'(' => paren_depth += 1,
            b')' => paren_depth = paren_depth.saturating_sub(1),
            b'[' => bracket_depth += 1,
            b']' => bracket_depth = bracket_depth.saturating_sub(1),
            b'=' if !in_expr
                && paren_depth == 0
                && bracket_depth == 0
                && !matches!(
                    bytes.get(cursor.wrapping_sub(1)),
                    Some(b'=' | b'!' | b'<' | b'>')
                )
                && !matches!(bytes.get(cursor + 1), Some(b'=' | b'>')) =>
            {
                in_expr = true;
                angle_depth = 0;
            }
            b'<' if !in_expr
                && paren_depth == 0
                && bracket_depth == 0
                && bytes.get(cursor + 1) != Some(&b'<') =>
            {
                angle_depth += 1;
            }
            b'>' if !in_expr
                && paren_depth == 0
                && bracket_depth == 0
                && !matches!(bytes.get(cursor.wrapping_sub(1)), Some(b'-' | b'=')) =>
            {
                angle_depth = angle_depth.saturating_sub(1);
            }
            b';' if paren_depth == 0 && bracket_depth == 0 && angle_depth == 0 => {
                return cursor + 1;
            }
            b',' if !in_where && paren_depth == 0 && bracket_depth == 0 && angle_depth == 0 => {
                return cursor + 1;
            }
            b'}' if paren_depth == 0 && bracket_depth == 0 && angle_depth == 0 => {
                return cursor;
            }
            b'{' if paren_depth == 0 && bracket_depth == 0 && angle_depth == 0 => {
                return find_matching_delimiter(source, cursor, b'{', b'}')
                    .map_or(bytes.len(), |end| end + 1);
            }
            _ => {}
        }
        cursor += source[cursor..].chars().next().map_or(1, char::len_utf8);
    }

    bytes.len()
}

/// Finds the byte offset of every `fetch_json_*` method or DB-UFCS call in
/// `source`, ignoring comments, string/char literals, and `fn` headers.
fn find_fetch_json_call_offsets(source: &str) -> Vec<usize> {
    let mut offsets = Vec::new();

    // Collect offsets of method or DB-UFCS invocations targeting `fetch_json_*`
    scan_body_identifiers(source, |offset, prev, ident, is_call| {
        if !is_call {
            return;
        }
        let is_method_or_ufcs = matches!(prev, PrevToken::Dot)
            || matches!(prev, PrevToken::PathSep(Some(q)) if is_db_ufcs_qualifier(q));
        if is_method_or_ufcs && ident.starts_with("fetch_json_") {
            offsets.push(offset);
        }
    });

    offsets
}

/// Finds every call to `name(...)` or `name::<...>(...)` in `code` outside
/// comments and literals, returning each call's byte offset and raw argument text.
fn find_function_calls(code: &str, name: &str) -> Vec<(usize, String)> {
    let bytes = code.as_bytes();
    let mut calls = Vec::new();
    let mut index = 0;

    // Scan code tokens for `name` followed by optional turbofish and `(`
    while index < bytes.len() {
        if let Some(next) = skip_non_code(code, index) {
            index = next;
            continue;
        }
        if bytes[index].is_ascii_alphabetic() || bytes[index] == b'_' {
            let start = index;
            while index < bytes.len()
                && (bytes[index].is_ascii_alphanumeric() || bytes[index] == b'_')
            {
                index += 1;
            }
            if &code[start..index] == name {
                let mut cursor = skip_ws_and_comments(code, index);
                if let Some(after_turbofish) = skip_turbofish(code, cursor) {
                    cursor = skip_ws_and_comments(code, after_turbofish);
                }
                if bytes.get(cursor) == Some(&b'(')
                    && let Some(close) = find_matching_delimiter(code, cursor, b'(', b')')
                {
                    calls.push((start, code[cursor + 1..close].to_string()));
                }
            }
            continue;
        }
        index += code[index..].chars().next().map_or(1, char::len_utf8);
    }

    calls
}

/// Finds the byte index of the closing delimiter matching the opening delimiter
/// at `open_index`, skipping nested delimiters, comments, and literals.
fn find_matching_delimiter(source: &str, open_index: usize, open: u8, close: u8) -> Option<usize> {
    let bytes = source.as_bytes();
    let mut depth = 0usize;
    let mut index = open_index;
    while index < bytes.len() {
        if let Some(next) = skip_non_code(source, index) {
            index = next;
            continue;
        }
        if bytes[index] == open {
            depth += 1;
        } else if bytes[index] == close {
            depth -= 1;
            if depth == 0 {
                return Some(index);
            }
        }
        index += source[index..].chars().next().map_or(1, char::len_utf8);
    }
    None
}

/// Finds the byte index immediately after a raw string literal starting at
/// `index`, returning `None` if the literal is unterminated.
fn find_raw_string_end(
    bytes: &[u8],
    index: usize,
    prefix_len: usize,
    hashes: usize,
) -> Option<usize> {
    let mut cursor = index + prefix_len;
    while cursor < bytes.len() {
        if bytes[cursor] == b'"' {
            let mut matched = 0;
            while matched < hashes && bytes.get(cursor + 1 + matched) == Some(&b'#') {
                matched += 1;
            }
            if matched == hashes {
                return Some(cursor + 1 + hashes);
            }
        }
        cursor += 1;
    }
    None
}

/// Returns provider-type violations for a handler file's referenced `crate::` paths.
fn handler_provider_violations(relative_path: &str, paths: &BTreeSet<String>) -> Vec<String> {
    let mut violations = Vec::new();
    for provider_type in PROVIDER_TYPES {
        let prefix = format!("{provider_type}::");
        if paths
            .iter()
            .any(|path| path == *provider_type || path.starts_with(&prefix))
        {
            violations.push(format!(
                "{relative_path} references provider type `crate::{provider_type}`"
            ));
        }
    }
    violations
}

/// Returns whether `code` contains a top-level early-returning
/// `if !self.use_cache()` (or `if !use_cache`) guard before `before_offset`
/// whose branch does not invoke `cache_probe` or `forbidden_target`.
fn has_early_bypass_guard(
    code: &str,
    require_self_call: bool,
    forbidden_target: &str,
    before_offset: Option<usize>,
) -> bool {
    let bytes = code.as_bytes();
    let limit = before_offset.unwrap_or(bytes.len());
    let mut brace_depth = 0usize;
    let mut index = 0;

    // Scan depth-0 statements for `if !self.use_cache() { ... }` or `if !use_cache { ... }`
    while index < limit {
        if let Some(next) = skip_non_code(code, index) {
            index = next;
            continue;
        }
        if bytes[index] == b'{' {
            brace_depth += 1;
            index += 1;
            continue;
        }
        if bytes[index] == b'}' {
            brace_depth = brace_depth.saturating_sub(1);
            index += 1;
            continue;
        }
        if brace_depth == 0 && (bytes[index].is_ascii_alphabetic() || bytes[index] == b'_') {
            let ident_start = index;
            while index < bytes.len()
                && (bytes[index].is_ascii_alphanumeric() || bytes[index] == b'_')
            {
                index += 1;
            }
            if &code[ident_start..index] != "if" {
                continue;
            }

            // Match the negated condition and opening brace of the guard block
            let bang = skip_ws_and_comments(code, index);
            if bytes.get(bang) != Some(&b'!') {
                continue;
            }
            let cond_start = skip_ws_and_comments(code, bang + 1);
            let mut cursor = cond_start;
            while cursor < bytes.len() {
                if let Some(next) = skip_non_code(code, cursor) {
                    cursor = next;
                    continue;
                }
                if bytes[cursor] == b'{' {
                    break;
                }
                cursor += code[cursor..].chars().next().map_or(1, char::len_utf8);
            }
            if bytes.get(cursor) != Some(&b'{') {
                continue;
            }
            let cond = trim_ws_and_comments(&code[cond_start..cursor]);
            let cond_matches = if require_self_call {
                is_self_use_cache_expr(cond)
            } else {
                cond == "use_cache"
            };
            if !cond_matches {
                continue;
            }

            // Verify the bypass branch has a top-level return without touching the cache
            let Some(block_end) = find_matching_delimiter(code, cursor, b'{', b'}') else {
                continue;
            };
            let branch_body = &code[cursor + 1..block_end];
            if has_top_level_return(branch_body)
                && find_function_calls(branch_body, "cache_probe").is_empty()
                && find_function_calls(branch_body, forbidden_target).is_empty()
            {
                return true;
            }
            continue;
        }
        index += code[index..].chars().next().map_or(1, char::len_utf8);
    }

    false
}

/// Returns whether `code` references identifier `ident` outside comments and literals.
fn has_identifier(code: &str, ident: &str) -> bool {
    let cleaned = strip_non_code(code);
    tokenize(&cleaned).into_iter().any(|token| token == ident)
}

/// Returns whether `body` contains a top-level `return` statement (not nested
/// inside an inner block, expression, or closure).
fn has_top_level_return(body: &str) -> bool {
    let bytes = body.as_bytes();
    let mut brace_depth = 0usize;
    let mut paren_depth = 0usize;
    let mut bracket_depth = 0usize;
    let mut at_stmt_start = true;
    let mut index = 0;

    // Scan depth-0 statement heads for `return`
    while index < bytes.len() {
        if let Some(next) = skip_non_code(body, index) {
            index = next;
            continue;
        }
        if bytes[index].is_ascii_whitespace() {
            index += 1;
            continue;
        }
        if brace_depth == 0
            && paren_depth == 0
            && bracket_depth == 0
            && (bytes[index].is_ascii_alphabetic() || bytes[index] == b'_')
        {
            let start = index;
            while index < bytes.len()
                && (bytes[index].is_ascii_alphanumeric() || bytes[index] == b'_')
            {
                index += 1;
            }
            if at_stmt_start && &body[start..index] == "return" {
                return true;
            }
            at_stmt_start = false;
            continue;
        }
        match bytes[index] {
            b'{' => {
                brace_depth += 1;
                at_stmt_start = false;
            }
            b'}' => {
                brace_depth = brace_depth.saturating_sub(1);
                if brace_depth == 0 && paren_depth == 0 && bracket_depth == 0 {
                    at_stmt_start = true;
                }
            }
            b'(' => {
                paren_depth += 1;
                at_stmt_start = false;
            }
            b')' => paren_depth = paren_depth.saturating_sub(1),
            b'[' => {
                bracket_depth += 1;
                at_stmt_start = false;
            }
            b']' => bracket_depth = bracket_depth.saturating_sub(1),
            b';' if brace_depth == 0 && paren_depth == 0 && bracket_depth == 0 => {
                at_stmt_start = true;
            }
            _ => {
                if brace_depth == 0 && paren_depth == 0 && bracket_depth == 0 {
                    at_stmt_start = false;
                }
            }
        }
        index += body[index..].chars().next().map_or(1, char::len_utf8);
    }

    false
}

/// Verifies every call chain within the file to a module-level cached helper
/// guards cache access with `use_cache` and originates from methods passing
/// or guarding on `self.use_cache()`.
fn helper_callers_guard_use_cache(
    source: &str,
    functions: &[FunctionBlock],
    target: &str,
    is_cached_target: bool,
    visited: &mut BTreeSet<String>,
) -> bool {
    // Collect every function in the file that calls `target`
    let mut callers = Vec::new();
    for func in functions {
        if func.name == target {
            continue;
        }
        let body = mask_nested_functions(&source[func.body_start + 1..func.body_end]);
        let calls = find_function_calls(&body, target);
        if !calls.is_empty() {
            callers.push((func, body, calls));
        }
    }

    // Reject unreachable module-level cached helpers
    if callers.is_empty() {
        return false;
    }

    // Check every caller either guards before calling or forwards the executor's flag
    for (caller, body, calls) in callers {
        let first_call = earliest_call_offset(&body, target);
        if caller.has_self {
            // Check `&self` callers guard early or pass `self.use_cache()` into a guarded helper
            let guarded_directly = has_early_bypass_guard(&body, true, target, first_call);
            let forwards_flag = !is_cached_target
                && calls.iter().all(|(_, args)| {
                    split_top_level_args(args)
                        .iter()
                        .any(|arg| is_self_use_cache_expr(arg))
                });
            if !guarded_directly && !forwards_flag {
                return false;
            }
        } else {
            // Check non-`self` helpers accept `use_cache`, guard or forward it, and have guarded callers
            if !caller.has_use_cache_param {
                return false;
            }
            let guarded_directly = has_early_bypass_guard(&body, false, target, first_call);
            let forwards_flag = !is_cached_target
                && calls.iter().all(|(_, args)| {
                    split_top_level_args(args)
                        .iter()
                        .any(|arg| trim_ws_and_comments(arg) == "use_cache")
                });
            if !guarded_directly && !forwards_flag {
                return false;
            }
            if visited.insert(caller.name.clone())
                && !helper_callers_guard_use_cache(source, functions, &caller.name, false, visited)
            {
                return false;
            }
        }
    }

    true
}

/// Returns whether the inner text of an outer attribute is `cfg(test)`.
fn is_cfg_test_attribute(inner: &str) -> bool {
    let trimmed = trim_ws_and_comments(inner);
    let Some(rest) = trimmed.strip_prefix("cfg") else {
        return false;
    };
    let rest = trim_ws_and_comments(rest);
    let Some(arg) = rest.strip_prefix('(').and_then(|s| s.strip_suffix(')')) else {
        return false;
    };
    trim_ws_and_comments(arg) == "test"
}

/// Returns whether an `impl` header implements a `DB*` trait (for example
/// `impl<T> DBSite for T where ...`).
fn is_db_trait_impl_header(header: &str) -> bool {
    let bytes = header.as_bytes();
    let mut index = skip_ws_and_comments(header, 0);

    // Skip the leading `impl` keyword
    let start = index;
    while index < bytes.len() && (bytes[index].is_ascii_alphanumeric() || bytes[index] == b'_') {
        index += 1;
    }
    if &header[start..index] != "impl" {
        return false;
    }
    index = skip_ws_and_comments(header, index);

    // Skip optional generic parameter list `impl<...>`
    if bytes.get(index) == Some(&b'<') {
        let Some(after_generics) = skip_angle_brackets(header, index) else {
            return false;
        };
        index = skip_ws_and_comments(header, after_generics);
    }

    // Scan until the top-level `for` keyword (stopping at `where` on inherent impls)
    let trait_start = index;
    let mut angle_depth = 0usize;
    let mut paren_depth = 0usize;
    let mut bracket_depth = 0usize;
    let mut trait_end = None;
    while index < bytes.len() {
        if let Some(next) = skip_non_code(header, index) {
            index = next;
            continue;
        }
        if angle_depth == 0
            && paren_depth == 0
            && bracket_depth == 0
            && (bytes[index].is_ascii_alphabetic() || bytes[index] == b'_')
        {
            let ident_start = index;
            while index < bytes.len()
                && (bytes[index].is_ascii_alphanumeric() || bytes[index] == b'_')
            {
                index += 1;
            }
            match &header[ident_start..index] {
                "for" => {
                    trait_end = Some(ident_start);
                    break;
                }
                "where" => return false,
                _ => continue,
            }
        }
        match bytes[index] {
            b'(' => paren_depth += 1,
            b')' => paren_depth = paren_depth.saturating_sub(1),
            b'[' => bracket_depth += 1,
            b']' => bracket_depth = bracket_depth.saturating_sub(1),
            b'<' if paren_depth == 0 && bracket_depth == 0 => angle_depth += 1,
            b'>' if paren_depth == 0
                && bracket_depth == 0
                && !matches!(bytes.get(index.wrapping_sub(1)), Some(b'-' | b'=')) =>
            {
                angle_depth = angle_depth.saturating_sub(1);
            }
            _ => {}
        }
        index += header[index..].chars().next().map_or(1, char::len_utf8);
    }

    // Check the final path segment of the trait starts with `DB`
    let Some(trait_end) = trait_end else {
        return false;
    };
    let trait_path = strip_non_code(&header[trait_start..trait_end]);
    let trait_head = trait_path.split('<').next().unwrap_or("");
    trait_head
        .rsplit("::")
        .map(str::trim)
        .find(|segment| !segment.is_empty())
        .is_some_and(|segment| segment.starts_with("DB"))
}

/// Returns whether a UFCS qualifier segment (`Qualifier::method(...)`) names a
/// database trait or PostgreSQL executor type.
fn is_db_ufcs_qualifier(qualifier: &str) -> bool {
    qualifier.starts_with("DB")
        || matches!(
            qualifier,
            "PgClient" | "PgDB" | "PgExecutor" | "PgUnitOfWork"
        )
}

/// Returns whether the token is an identifier.
fn is_identifier(token: &str) -> bool {
    token
        .chars()
        .next()
        .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
}

/// Returns whether the inner text of an outer attribute is `cfg(...)` for a
/// predicate other than `test`.
fn is_non_test_cfg_attribute(inner: &str) -> bool {
    let Some((last_segment, next)) = parse_attribute_last_segment(inner) else {
        return false;
    };
    last_segment == "cfg"
        && inner.as_bytes().get(next) == Some(&b'(')
        && !is_cfg_test_attribute(inner)
}

/// Returns whether `ident` is a Rust keyword that cannot name a helper or type qualifier.
fn is_rust_keyword(ident: &str) -> bool {
    matches!(
        ident,
        "as" | "async"
            | "await"
            | "break"
            | "const"
            | "continue"
            | "else"
            | "enum"
            | "extern"
            | "false"
            | "fn"
            | "for"
            | "if"
            | "impl"
            | "in"
            | "let"
            | "loop"
            | "match"
            | "mod"
            | "move"
            | "mut"
            | "pub"
            | "ref"
            | "return"
            | "static"
            | "struct"
            | "trait"
            | "true"
            | "type"
            | "unsafe"
            | "use"
            | "where"
            | "while"
    )
}

/// Returns whether `expr` is strictly `self.use_cache()` ignoring whitespace
/// and comments.
fn is_self_use_cache_expr(expr: &str) -> bool {
    let cleaned = strip_non_code(expr);
    let compact: String = cleaned.chars().filter(|c| !c.is_ascii_whitespace()).collect();
    compact == "self.use_cache()"
}

/// Returns whether a `convert` attribute expression evaluates to a constant
/// singleton key independent of function arguments.
fn is_singleton_convert_expr(raw_value: &str) -> bool {
    // Decode the convert string literal and strip outer braces when present
    let decoded =
        decode_rust_string_literal(raw_value).unwrap_or_else(|| raw_value.trim().to_string());
    let mut expr = decoded.trim();
    if let Some(inner) = expr.strip_prefix('{').and_then(|s| s.strip_suffix('}')) {
        expr = inner.trim();
    }

    // Accept unit keys, bare string literals, and constant owned strings
    if expr == "()" || decode_rust_string_literal(expr).is_some() {
        return true;
    }
    if let Some(arg) = expr.strip_prefix("String::from(").and_then(|s| s.strip_suffix(')')) {
        return decode_rust_string_literal(arg).is_some();
    }
    for suffix in [".to_owned()", ".to_string()"] {
        if let Some(receiver) = expr.strip_suffix(suffix) {
            return decode_rust_string_literal(receiver).is_some();
        }
    }

    false
}

/// Checks a single source file's referenced `crate::` paths against the
/// forbidden layer-edge matrix.
fn layer_edge_violations<'a>(
    layer: &str,
    relative_path: &'a str,
    paths: &'a BTreeSet<String>,
    used_allowances: &mut BTreeSet<(&'a str, &'a str)>,
) -> Vec<String> {
    let mut violations = Vec::new();
    let targets: BTreeSet<&str> = paths
        .iter()
        .filter_map(|path| path.split("::").next())
        .filter(|target| LAYERS.contains(target))
        .collect();

    for target in targets {
        if !FORBIDDEN_EDGES.contains(&(layer, target)) {
            continue;
        }
        let allowance = (relative_path, target);
        if LAYER_EDGE_ALLOWANCES.contains(&allowance) {
            used_allowances.insert(allowance);
        } else {
            violations.push(format!(
                "{relative_path} ({layer}) depends on `crate::{target}`"
            ));
        }
    }

    violations
}

/// Replaces every nested `fn ... { ... }` definition inside `body` with spaces
/// while preserving byte length and newlines so caller offsets stay aligned.
fn mask_nested_functions(body: &str) -> String {
    let bytes = body.as_bytes();
    let mut out = String::with_capacity(body.len());
    let mut index = 0;

    // Mask nested function definitions so inner or sibling helpers cannot satisfy caller guards
    while index < bytes.len() {
        if let Some(next) = skip_non_code(body, index) {
            out.push_str(&body[index..next]);
            index = next;
            continue;
        }
        if bytes[index].is_ascii_alphabetic() || bytes[index] == b'_' {
            let ident_start = index;
            while index < bytes.len()
                && (bytes[index].is_ascii_alphanumeric() || bytes[index] == b'_')
            {
                index += 1;
            }
            if &body[ident_start..index] == "fn"
                && let Some(nested) = parse_function_at(body, ident_start)
            {
                let end = nested.body_end + 1;
                for ch in body[ident_start..end].chars() {
                    out.push(if ch == '\n' { '\n' } else { ' ' });
                }
                index = end;
                continue;
            }
            out.push_str(&body[ident_start..index]);
            continue;
        }
        let ch = body[index..].chars().next().expect("valid utf-8 boundary");
        out.push(ch);
        index += ch.len_utf8();
    }

    out
}

/// Parses the function annotated by an attribute ending at `after_attr`.
fn parse_annotated_function(source: &str, after_attr: usize) -> Option<FunctionBlock> {
    let bytes = source.as_bytes();
    let mut index = after_attr;

    while index < bytes.len() {
        index = skip_ws_and_comments(source, index);
        if index >= bytes.len() {
            return None;
        }

        // Skip sibling attributes on the same function
        if bytes[index] == b'#' {
            let open = skip_ws_and_comments(source, index + 1);
            if bytes.get(open) == Some(&b'[')
                && let Some(close) = find_matching_delimiter(source, open, b'[', b']')
            {
                index = close + 1;
                continue;
            }
            return None;
        }

        // Read modifiers (`pub(...)`, `async`, `const`, `unsafe`) until `fn`
        if bytes[index].is_ascii_alphabetic() || bytes[index] == b'_' {
            let ident_start = index;
            while index < bytes.len()
                && (bytes[index].is_ascii_alphanumeric() || bytes[index] == b'_')
            {
                index += 1;
            }
            let ident = &source[ident_start..index];
            match ident {
                "fn" => return parse_function_at(source, ident_start),
                "pub" => {
                    let next = skip_ws_and_comments(source, index);
                    if bytes.get(next) == Some(&b'(')
                        && let Some(close) = find_matching_delimiter(source, next, b'(', b')')
                    {
                        index = close + 1;
                    }
                }
                "async" | "const" | "unsafe" => {}
                _ => return None,
            }
            continue;
        }

        return None;
    }

    None
}

/// Parses an attribute path at the start of `inner` (allowing a leading `::`)
/// and returns its final segment along with the byte offset after trailing
/// whitespace and comments.
fn parse_attribute_last_segment(inner: &str) -> Option<(&str, usize)> {
    let bytes = inner.as_bytes();
    let mut index = skip_ws_and_comments(inner, 0);

    // Allow a leading global path separator such as `::tokio::test`
    if bytes.get(index) == Some(&b':') && bytes.get(index + 1) == Some(&b':') {
        index = skip_ws_and_comments(inner, index + 2);
    }

    // Read `::`-separated segments and return the final one
    loop {
        let start = index;
        while index < bytes.len() && (bytes[index].is_ascii_alphanumeric() || bytes[index] == b'_')
        {
            index += 1;
        }
        if index == start {
            return None;
        }
        let segment = &inner[start..index];
        let next = skip_ws_and_comments(inner, index);
        if bytes.get(next) == Some(&b':') && bytes.get(next + 1) == Some(&b':') {
            index = skip_ws_and_comments(inner, next + 2);
        } else {
            return Some((segment, next));
        }
    }
}

/// Parses a function definition starting at its `fn` keyword byte offset.
fn parse_function_at(source: &str, fn_start: usize) -> Option<FunctionBlock> {
    let bytes = source.as_bytes();
    let name_start = skip_ws_and_comments(source, fn_start + 2);
    let mut name_end = name_start;
    while name_end < bytes.len()
        && (bytes[name_end].is_ascii_alphanumeric() || bytes[name_end] == b'_')
    {
        name_end += 1;
    }
    if name_end == name_start {
        return None;
    }
    let name = source[name_start..name_end].to_string();

    // Advance past optional generic parameters to the opening `(` of parameters
    let mut cursor = name_end;
    let mut lparen = None;
    while cursor < bytes.len() {
        if let Some(next) = skip_non_code(source, cursor) {
            cursor = next;
            continue;
        }
        match bytes[cursor] {
            b'(' => {
                lparen = Some(cursor);
                break;
            }
            b';' | b'{' => return None,
            _ => cursor += source[cursor..].chars().next().map_or(1, char::len_utf8),
        }
    }
    let lparen = lparen?;
    let rparen = find_matching_delimiter(source, lparen, b'(', b')')?;
    let params = &source[lparen + 1..rparen];
    let has_self = has_identifier(params, "self");
    let has_use_cache_param = has_identifier(params, "use_cache");

    // Advance past return type and optional `where` clause to `{` or `;`
    cursor = rparen + 1;
    let mut paren_depth = 0usize;
    let mut bracket_depth = 0usize;
    while cursor < bytes.len() {
        if let Some(next) = skip_non_code(source, cursor) {
            cursor = next;
            continue;
        }
        match bytes[cursor] {
            b'(' => paren_depth += 1,
            b')' => paren_depth = paren_depth.saturating_sub(1),
            b'[' => bracket_depth += 1,
            b']' => bracket_depth = bracket_depth.saturating_sub(1),
            b';' if paren_depth == 0 && bracket_depth == 0 => return None,
            b'{' if paren_depth == 0 && bracket_depth == 0 => {
                let body_end = find_matching_delimiter(source, cursor, b'{', b'}')?;
                return Some(FunctionBlock {
                    body_end,
                    body_start: cursor,
                    fn_start,
                    has_self,
                    has_use_cache_param,
                    name,
                    scope: FunctionScope::Free,
                });
            }
            _ => {}
        }
        cursor += source[cursor..].chars().next().map_or(1, char::len_utf8);
    }

    None
}

/// Parses a use tree starting at `index`, appending each flattened path
/// (prefixed by `prefix`) to `paths` and recording local bindings in
/// `bindings`, and returns the index after the tree.
fn parse_use_tree(
    tokens: &[&str],
    mut index: usize,
    prefix: &[&str],
    paths: &mut BTreeSet<String>,
    bindings: &mut BTreeMap<String, BTreeSet<String>>,
) -> usize {
    let mut segments: Vec<&str> = prefix.to_vec();
    let mut alias: Option<&str> = None;
    while let Some(token) = tokens.get(index) {
        match *token {
            "{" => {
                // Recurse into each branch of the group
                index += 1;
                loop {
                    match tokens.get(index) {
                        Some(&"}") | None => {
                            index += 1;
                            break;
                        }
                        Some(&",") => index += 1,
                        Some(_) => {
                            index = parse_use_tree(tokens, index, &segments, paths, bindings);
                        }
                    }
                }
                return index;
            }
            "::" => index += 1,
            "as" => {
                alias = tokens.get(index + 1).copied();
                index += 2;
            }
            "," | "}" | ";" => break,
            segment => {
                if segment != "self" {
                    segments.push(segment);
                }
                index += 1;
            }
        }
    }
    if !segments.is_empty() {
        let full_path = segments.join("::");
        let local_name = alias.or_else(|| segments.last().copied());
        if let Some(name) = local_name
            && name != "_"
            && is_identifier(name)
        {
            bindings
                .entry(name.to_string())
                .or_default()
                .insert(full_path.clone());
        }
        paths.insert(full_path);
    }
    index
}

/// Propagates `uses_fetch_json` flags across DB files through `FunctionScope::Free`
/// helper calls until fixed point.
fn propagate_free_helper_usage(
    parsed_files: &[Vec<(FunctionBlock, BodyCalls)>],
    uses_fetch_json: &mut [Vec<bool>],
) {
    loop {
        let mut changed = false;
        for file_idx in 0..parsed_files.len() {
            for fn_idx in 0..parsed_files[file_idx].len() {
                if uses_fetch_json[file_idx][fn_idx] {
                    continue;
                }
                let calls_json_helper = resolve_free_helper_targets(
                    parsed_files,
                    file_idx,
                    &parsed_files[file_idx][fn_idx].1,
                )
                .into_iter()
                .any(|(target_file, target_fn)| uses_fetch_json[target_file][target_fn]);
                if calls_json_helper {
                    uses_fetch_json[file_idx][fn_idx] = true;
                    changed = true;
                }
            }
        }
        if !changed {
            break;
        }
    }
}

/// Returns `(prefix_len, hash_count)` if `bytes[index..]` starts a Rust raw
/// string literal (`r"..."`, `r#"..."#`, `br#"..."#`, `cr#"..."#`).
fn raw_string_prefix(bytes: &[u8], index: usize) -> Option<(usize, usize)> {
    // Reject `r` when immediately preceded by an identifier character
    if index > 0 && (bytes[index - 1].is_ascii_alphanumeric() || bytes[index - 1] == b'_') {
        return None;
    }

    // Match optional `b`/`c` prefix followed by `r`
    let mut cursor = index;
    if matches!(bytes.get(cursor), Some(b'b' | b'c')) && bytes.get(cursor + 1) == Some(&b'r') {
        cursor += 2;
    } else if bytes.get(cursor) == Some(&b'r') {
        cursor += 1;
    } else {
        return None;
    }

    // Count hash delimiters and verify the opening double quote
    let hash_start = cursor;
    while bytes.get(cursor) == Some(&b'#') {
        cursor += 1;
    }
    if bytes.get(cursor) != Some(&b'"') {
        return None;
    }
    Some((cursor + 1 - index, cursor - hash_start))
}

/// Resolves calls in `calls` to matching `FunctionScope::Free` helper indices:
/// bare calls and `self::` calls match only same-file helpers, while non-`self`
/// path-qualified calls may match free helpers in sibling DB files.
fn resolve_free_helper_targets(
    parsed_files: &[Vec<(FunctionBlock, BodyCalls)>],
    caller_file_idx: usize,
    calls: &BodyCalls,
) -> Vec<(usize, usize)> {
    let mut targets = Vec::new();

    // Resolve bare local calls strictly against same-file free helpers
    for callee in &calls.local_calls {
        for (fn_idx, (f, _)) in parsed_files[caller_file_idx].iter().enumerate() {
            if f.scope == FunctionScope::Free && f.name == *callee {
                targets.push((caller_file_idx, fn_idx));
            }
        }
    }

    // Resolve path-qualified calls: `self::` in the same file, other qualifiers across DB files
    for (qualifier, callee) in &calls.qualified_calls {
        if qualifier.as_deref() == Some("self") {
            for (fn_idx, (f, _)) in parsed_files[caller_file_idx].iter().enumerate() {
                if f.scope == FunctionScope::Free && f.name == *callee {
                    targets.push((caller_file_idx, fn_idx));
                }
            }
        } else {
            for (other_file, other_fns) in parsed_files.iter().enumerate() {
                for (fn_idx, (f, _)) in other_fns.iter().enumerate() {
                    if f.scope == FunctionScope::Free && f.name == *callee {
                        targets.push((other_file, fn_idx));
                    }
                }
            }
        }
    }

    targets
}

/// Scans `code` outside comments and literals, invoking `on_ident` for every
/// non-keyword identifier together with its byte offset, preceding token, name,
/// and whether it is invoked with `(` or `::<...>(`.
fn scan_body_identifiers<'a>(
    code: &'a str,
    mut on_ident: impl FnMut(usize, PrevToken<'a>, &'a str, bool),
) {
    let bytes = code.as_bytes();
    let mut index = 0;
    let mut last_ident: Option<&'a str> = None;
    let mut prev = PrevToken::Other;

    // Walk code tokens and report every call and identifier reference
    while index < bytes.len() {
        if let Some(next) = skip_non_code(code, index) {
            index = next;
            continue;
        }
        if bytes[index].is_ascii_whitespace() {
            index += 1;
            continue;
        }

        // Track member-access `.` while ignoring `..` range operators
        if bytes[index] == b'.' {
            if bytes.get(index + 1) == Some(&b'.') {
                prev = PrevToken::Other;
                last_ident = None;
                index += 2;
            } else {
                prev = PrevToken::Dot;
                last_ident = None;
                index += 1;
            }
            continue;
        }

        // Track `::` together with its preceding qualifier segment
        if bytes[index] == b':' && bytes.get(index + 1) == Some(&b':') {
            prev = PrevToken::PathSep(last_ident);
            last_ident = None;
            index += 2;
            continue;
        }

        // Handle `<Type as Trait>::` qualified paths and `::<...>` turbofish without leaking inner type args
        if bytes[index] == b'<'
            && let Some(after_angle) = skip_angle_brackets(code, index)
        {
            match prev {
                PrevToken::PathSep(outer) => {
                    prev = PrevToken::Other;
                    last_ident = outer;
                    index = after_angle;
                    continue;
                }
                PrevToken::Other if last_ident.is_none() => {
                    let next = skip_ws_and_comments(code, after_angle);
                    if bytes.get(next) == Some(&b':') && bytes.get(next + 1) == Some(&b':') {
                        last_ident =
                            extract_qualified_path_trait(&code[index + 1..after_angle - 1]);
                        prev = PrevToken::Other;
                        index = after_angle;
                        continue;
                    }
                }
                _ => {}
            }
        }

        // Read identifier tokens and classify calls vs value references
        if bytes[index].is_ascii_alphabetic() || bytes[index] == b'_' {
            let start = index;
            while index < bytes.len()
                && (bytes[index].is_ascii_alphanumeric() || bytes[index] == b'_')
            {
                index += 1;
            }
            let ident = &code[start..index];
            let is_keyword = is_rust_keyword(ident);
            if !is_keyword {
                let mut cursor = skip_ws_and_comments(code, index);
                if let Some(after_turbofish) = skip_turbofish(code, cursor) {
                    cursor = skip_ws_and_comments(code, after_turbofish);
                }
                let is_call = bytes.get(cursor) == Some(&b'(');
                on_ident(start, prev, ident, is_call);
            }
            prev = match ident {
                "fn" => PrevToken::FnKeyword,
                "let" => PrevToken::LetKeyword,
                _ => PrevToken::Other,
            };
            last_ident = (!is_keyword).then_some(ident);
            continue;
        }

        prev = PrevToken::Other;
        last_ident = None;
        index += code[index..].chars().next().map_or(1, char::len_utf8);
    }
}

/// Skips a balanced `<...>` generic argument or parameter list starting at
/// `open_index`, respecting nested delimiters, comments, literals, and `->`/`=>`.
fn skip_angle_brackets(source: &str, open_index: usize) -> Option<usize> {
    let bytes = source.as_bytes();
    if bytes.get(open_index) != Some(&b'<') {
        return None;
    }

    // Balance nested `<...>`, `(...)`, and `[...]` until the matching `>`
    let mut cursor = open_index + 1;
    let mut angle_depth = 1usize;
    let mut paren_depth = 0usize;
    let mut bracket_depth = 0usize;
    while cursor < bytes.len() {
        if let Some(next) = skip_non_code(source, cursor) {
            cursor = next;
            continue;
        }
        match bytes[cursor] {
            b'(' => paren_depth += 1,
            b')' => paren_depth = paren_depth.saturating_sub(1),
            b'[' => bracket_depth += 1,
            b']' => bracket_depth = bracket_depth.saturating_sub(1),
            b'<' if paren_depth == 0 && bracket_depth == 0 => angle_depth += 1,
            b'>' if paren_depth == 0
                && bracket_depth == 0
                && !matches!(bytes.get(cursor.wrapping_sub(1)), Some(b'-' | b'=')) =>
            {
                angle_depth -= 1;
                if angle_depth == 0 {
                    return Some(cursor + 1);
                }
            }
            _ => {}
        }
        cursor += source[cursor..].chars().next().map_or(1, char::len_utf8);
    }

    None
}

/// Skips a single comment, string literal, or char literal starting at `index`.
fn skip_non_code(source: &str, index: usize) -> Option<usize> {
    let bytes = source.as_bytes();

    // Skip line comments
    if bytes.get(index) == Some(&b'/') && bytes.get(index + 1) == Some(&b'/') {
        let mut cursor = index + 2;
        while cursor < bytes.len() && bytes[cursor] != b'\n' {
            cursor += 1;
        }
        return Some(cursor);
    }

    // Skip nested block comments
    if bytes.get(index) == Some(&b'/') && bytes.get(index + 1) == Some(&b'*') {
        let mut depth = 1usize;
        let mut cursor = index + 2;
        while cursor + 1 < bytes.len() && depth > 0 {
            if bytes[cursor] == b'/' && bytes[cursor + 1] == b'*' {
                depth += 1;
                cursor += 2;
            } else if bytes[cursor] == b'*' && bytes[cursor + 1] == b'/' {
                depth -= 1;
                cursor += 2;
            } else {
                cursor += 1;
            }
        }
        return Some(if depth == 0 { cursor } else { bytes.len() });
    }

    // Skip raw string literals
    if let Some((prefix_len, hashes)) = raw_string_prefix(bytes, index) {
        return Some(find_raw_string_end(bytes, index, prefix_len, hashes).unwrap_or(bytes.len()));
    }

    // Skip double-quoted string literals
    if bytes.get(index) == Some(&b'"') {
        let mut cursor = index + 1;
        while cursor < bytes.len() {
            if bytes[cursor] == b'\\' {
                cursor = (cursor + 2).min(bytes.len());
            } else if bytes[cursor] == b'"' {
                return Some(cursor + 1);
            } else {
                cursor += 1;
            }
        }
        return Some(bytes.len());
    }

    // Skip char and byte-char literals without confusing lifetimes such as `'static`
    let char_start = if bytes.get(index) == Some(&b'b')
        && bytes.get(index + 1) == Some(&b'\'')
        && (index == 0 || !(bytes[index - 1].is_ascii_alphanumeric() || bytes[index - 1] == b'_'))
    {
        Some(index + 1)
    } else if bytes.get(index) == Some(&b'\'') {
        Some(index)
    } else {
        None
    };
    if let Some(quote_pos) = char_start {
        if bytes.get(quote_pos + 1) == Some(&b'\\') {
            // Advance past the escaped byte so `'\''` does not stop early
            let mut cursor = quote_pos + 3;
            while cursor < bytes.len() && bytes[cursor] != b'\n' {
                if bytes[cursor] == b'\'' {
                    return Some(cursor + 1);
                }
                cursor += 1;
            }
        } else if let Some(ch) = source[quote_pos + 1..].chars().next()
            && ch != '\''
            && ch != '\n'
            && bytes.get(quote_pos + 1 + ch.len_utf8()) == Some(&b'\'')
        {
            return Some(quote_pos + 2 + ch.len_utf8());
        }
    }

    None
}

/// Skips a Rust turbofish generic argument list (`::<...>`) starting at `index`
/// and returns the byte offset immediately after the closing `>`.
fn skip_turbofish(source: &str, index: usize) -> Option<usize> {
    let bytes = source.as_bytes();
    if bytes.get(index) != Some(&b':') || bytes.get(index + 1) != Some(&b':') {
        return None;
    }
    let open = skip_ws_and_comments(source, index + 2);
    skip_angle_brackets(source, open)
}

/// Advances past ASCII whitespace and Rust comments starting at `index`.
fn skip_ws_and_comments(source: &str, mut index: usize) -> usize {
    let bytes = source.as_bytes();
    while index < bytes.len() {
        if bytes[index].is_ascii_whitespace() {
            index += 1;
        } else if bytes.get(index) == Some(&b'/')
            && matches!(bytes.get(index + 1), Some(b'/' | b'*'))
            && let Some(next) = skip_non_code(source, index)
        {
            index = next;
        } else {
            break;
        }
    }
    index
}

/// Splits an attribute argument list on top-level commas, respecting nested
/// delimiters, comments, and literals.
fn split_top_level_args(args: &str) -> Vec<String> {
    let bytes = args.as_bytes();
    let mut items = Vec::new();
    let mut depth = 0usize;
    let mut index = 0;
    let mut start = 0;

    // Split only at comma delimiters outside nested groups and literals
    while index < bytes.len() {
        if let Some(next) = skip_non_code(args, index) {
            index = next;
            continue;
        }
        match bytes[index] {
            b'(' | b'[' | b'{' => depth += 1,
            b')' | b']' | b'}' => depth = depth.saturating_sub(1),
            b',' if depth == 0 => {
                items.push(args[start..index].to_string());
                start = index + 1;
            }
            _ => {}
        }
        index += args[index..].chars().next().map_or(1, char::len_utf8);
    }

    // Emit the trailing segment after the final comma
    if start < bytes.len() {
        items.push(args[start..].to_string());
    }
    items
}

/// Splits a single `key = value` attribute item on its top-level `=`, stripping
/// surrounding comments and whitespace from both sides.
fn split_top_level_key_value(item: &str) -> Option<(String, String)> {
    let bytes = item.as_bytes();

    // Read the option key identifier
    let key_start = skip_ws_and_comments(item, 0);
    let mut key_end = key_start;
    while key_end < bytes.len()
        && (bytes[key_end].is_ascii_alphanumeric() || bytes[key_end] == b'_')
    {
        key_end += 1;
    }
    if key_end == key_start {
        return None;
    }

    // Match the `=` separator and trim comments/whitespace around the value
    let eq_pos = skip_ws_and_comments(item, key_end);
    if bytes.get(eq_pos) != Some(&b'=') {
        return None;
    }
    let value = trim_ws_and_comments(&item[eq_pos + 1..]);
    Some((item[key_start..key_end].to_string(), value.to_string()))
}

/// Masks every item, field, or variant annotated with an outer attribute
/// matching `predicate` with spaces while preserving newlines so line numbers
/// remain accurate.
fn strip_cfg_items_where(source: &str, mut predicate: impl FnMut(&str) -> bool) -> String {
    let bytes = source.as_bytes();
    let mut out = String::with_capacity(source.len());
    let mut index = 0;

    // Walk source code, masking any item, field, or variant whose attribute matches
    while index < bytes.len() {
        if let Some(next) = skip_non_code(source, index) {
            out.push_str(&source[index..next]);
            index = next;
            continue;
        }

        if bytes[index] == b'#' {
            let open = skip_ws_and_comments(source, index + 1);
            if bytes.get(open) == Some(&b'[')
                && let Some(close) = find_matching_delimiter(source, open, b'[', b']')
                && predicate(&source[open + 1..close])
            {
                let end = find_cfg_test_item_end(source, close + 1);

                // Preserve line numbers by keeping newlines intact
                for ch in source[index..end].chars() {
                    out.push(if ch == '\n' { '\n' } else { ' ' });
                }
                index = end;
                continue;
            }
        }

        let ch = source[index..].chars().next().expect("valid utf-8 boundary");
        out.push(ch);
        index += ch.len_utf8();
    }

    out
}

/// Masks every `#[cfg(test)]`-annotated item, field, or variant in `source`
/// with spaces while preserving newlines so reported line numbers remain accurate.
fn strip_cfg_test_items(source: &str) -> String {
    strip_cfg_items_where(source, is_cfg_test_attribute)
}

/// Returns `source` with comments and string or char literals replaced by spaces.
fn strip_non_code(source: &str) -> String {
    let bytes = source.as_bytes();
    let mut out = String::with_capacity(source.len());
    let mut index = 0;

    while index < bytes.len() {
        if let Some(next) = skip_non_code(source, index) {
            out.push(' ');
            index = next;
            continue;
        }
        let ch = source[index..].chars().next().expect("valid utf-8 boundary");
        out.push(ch);
        index += ch.len_utf8();
    }

    out
}

/// Splits source code into identifier, `::`, and punctuation tokens.
fn tokenize(code: &str) -> Vec<&str> {
    let mut tokens = Vec::new();
    let bytes = code.as_bytes();
    let mut index = 0;
    while index < bytes.len() {
        let c = bytes[index];
        if c.is_ascii_alphanumeric() || c == b'_' {
            let start = index;
            while index < bytes.len()
                && (bytes[index].is_ascii_alphanumeric() || bytes[index] == b'_')
            {
                index += 1;
            }
            tokens.push(&code[start..index]);
        } else if c == b':' && bytes.get(index + 1) == Some(&b':') {
            tokens.push("::");
            index += 2;
        } else if matches!(c, b'{' | b'}' | b',' | b';') {
            tokens.push(&code[index..=index]);
            index += 1;
        } else {
            index += 1;
        }
    }
    tokens
}

/// Trims leading and trailing ASCII whitespace and Rust comments from `source`.
fn trim_ws_and_comments(source: &str) -> &str {
    // Advance past leading whitespace and comments
    let start = skip_ws_and_comments(source, 0);
    let bytes = source.as_bytes();
    let mut index = start;
    let mut last_code_end = start;

    // Track the end of the last non-whitespace, non-comment span
    while index < bytes.len() {
        if bytes[index].is_ascii_whitespace() {
            index += 1;
        } else if bytes.get(index) == Some(&b'/')
            && matches!(bytes.get(index + 1), Some(b'/' | b'*'))
            && let Some(next) = skip_non_code(source, index)
        {
            index = next;
        } else if let Some(next) = skip_non_code(source, index) {
            index = next;
            last_code_end = next;
        } else {
            index += source[index..].chars().next().map_or(1, char::len_utf8);
            last_code_end = index;
        }
    }

    &source[start..last_code_end]
}

/// Recursively collects `.rs` files under `dir`.
fn walk_rust_files(dir: &Path, files: &mut Vec<PathBuf>) {
    if !dir.exists() {
        return;
    }
    let entries = fs::read_dir(dir)
        .unwrap_or_else(|err| panic!("failed to read directory `{}`: {err}", dir.display()));
    for entry in entries {
        let entry = entry.unwrap_or_else(|err| {
            panic!(
                "failed to read directory entry under `{}`: {err}",
                dir.display()
            )
        });
        let path = entry.path();
        if path.is_dir() {
            walk_rust_files(&path, files);
        } else if path.extension().is_some_and(|ext| ext == "rs") {
            files.push(path);
        }
    }
}
