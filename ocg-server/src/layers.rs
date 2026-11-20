//! Layer dependency rules for the backend, enforced at test time.
//!
//! `docs/backend.md` defines the dependency direction `router -> handlers ->
//! services -> db`, with `types` and `templates` as leaves. The test in this
//! module reads every Rust source file under the layered directories, collects
//! the `crate::` paths it references (both `use` trees and inline paths), and
//! fails on a forbidden edge that is not listed in an allowance. Allowances
//! exist only for edges that are still being migrated; an allowance that no
//! longer matches any edge also fails the test, so the lists shrink with each
//! migration and never grow silently. Additional tests keep cached aggregates
//! over mutable data out of `services`, where transactions are opened, and
//! verify that every non-singleton `#[cached]` attribute specifies `max_size`.

use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
};

/// Layers checked for forbidden edges, in dependency order.
const LAYERS: &[&str] = &["handlers", "services", "db", "templates", "types"];

/// Forbidden edges as `(source layer, target layer)`.
const FORBIDDEN_EDGES: &[(&str, &str)] = &[
    ("db", "handlers"),
    ("db", "services"),
    ("db", "templates"),
    ("services", "handlers"),
    ("templates", "db"),
    ("templates", "handlers"),
    ("templates", "services"),
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

/// Cached aggregates over mutable data. Inside a transaction that changed the
/// underlying rows they could hide its writes or cache uncommitted counts.
/// Keeping them out of `services`, where transactions are opened, is a
/// conservative proxy for that rule; see "Cached reads and transactions" in
/// `docs/backend.md`.
const MUTABLE_AGGREGATE_CACHED_READS: &[&str] = &[
    "get_community_site_stats",
    "get_community_stats",
    "get_event_analytics",
    "get_group_stats",
    "get_site_home_stats",
    "get_site_stats",
];

/// Parsed `#[cached]` attribute found in a Rust source file.
struct CachedAttribute {
    /// 1-based line number where the attribute begins.
    line: usize,

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

/// A source file with the `crate::` paths it references.
struct SourceFile {
    /// Layer the file belongs to.
    layer: &'static str,
    /// Referenced `crate::` paths without the `crate::` prefix.
    paths: BTreeSet<String>,
    /// Path relative to `src/`, with `/` separators.
    relative_path: String,
}

#[test]
fn cached_aggregate_reads_stay_outside_services() {
    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");

    // Collect every service source file
    let mut entries = Vec::new();
    walk_rust_files(&src_dir.join("services"), &mut entries);
    entries.push(src_dir.join("services.rs"));
    assert!(
        entries.len() > 1,
        "service source files should be found under {}",
        src_dir.display()
    );

    // Check service code for calls to cached aggregates over mutable data
    let mut violations = Vec::new();
    for entry in entries.iter().filter(|entry| entry.is_file()) {
        let source = fs::read_to_string(entry).expect("source file should be readable");
        let code = strip_line_comments(&source);
        let identifiers: BTreeSet<&str> = tokenize(&code).into_iter().collect();
        for method in MUTABLE_AGGREGATE_CACHED_READS {
            if identifiers.contains(method) {
                violations.push(format!(
                    "{} references cached aggregate read `{method}`",
                    entry.strip_prefix(&src_dir).unwrap_or(entry).display()
                ));
            }
        }
    }

    assert!(
        violations.is_empty(),
        "cached aggregate reads must stay outside services:\n{}",
        violations.join("\n")
    );
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

    // Check every layer directory contributed source files, so an empty walk cannot pass
    for layer in LAYERS {
        let layer_dir = format!("{layer}/");
        assert!(
            files.iter().any(|file| file.relative_path.starts_with(&layer_dir)),
            "no source files found under `{layer_dir}`"
        );
    }

    // Check layer edges against the forbidden list and its allowances
    let mut used_layer_allowances = BTreeSet::new();
    for file in &files {
        let targets: BTreeSet<&str> = file
            .paths
            .iter()
            .filter_map(|path| path.split("::").next())
            .filter(|target| LAYERS.contains(target))
            .collect();
        for target in targets {
            if !FORBIDDEN_EDGES.contains(&(file.layer, target)) {
                continue;
            }
            let allowance = (file.relative_path.as_str(), target);
            if LAYER_EDGE_ALLOWANCES.contains(&allowance) {
                used_layer_allowances.insert(allowance);
            } else {
                violations.push(format!(
                    "{} ({}) depends on `crate::{target}`",
                    file.relative_path, file.layer
                ));
            }
        }
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

    assert!(
        violations.is_empty(),
        "layer dependency violations:\n{}",
        violations.join("\n")
    );
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

/// Parses an attribute body (including `cfg_attr` wrappers) and appends any
/// matching `cached` or `concurrent_cached` attributes to `out`.
fn collect_cached_attributes(inner: &str, line: usize, out: &mut Vec<CachedAttribute>) {
    let bytes = inner.as_bytes();
    let mut index = skip_ws_and_comments(inner, 0);

    // Allow a leading global path separator such as `::cached::cached`
    if bytes.get(index) == Some(&b':') && bytes.get(index + 1) == Some(&b':') {
        index = skip_ws_and_comments(inner, index + 2);
    }

    // Read the attribute path and keep the final segment
    let last_segment;
    loop {
        let start = index;
        while index < bytes.len() && (bytes[index].is_ascii_alphanumeric() || bytes[index] == b'_')
        {
            index += 1;
        }
        if index == start {
            return;
        }
        let segment = &inner[start..index];
        let next = skip_ws_and_comments(inner, index);
        if bytes.get(next) == Some(&b':') && bytes.get(next + 1) == Some(&b':') {
            index = skip_ws_and_comments(inner, next + 2);
        } else {
            last_segment = segment;
            index = next;
            break;
        }
    }

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
            collect_cached_attributes(&nested, line, out);
        }
        return;
    }

    // Ignore attributes that do not target `cached` or `concurrent_cached`
    if !matches!(last_segment, "cached" | "concurrent_cached") {
        return;
    }

    // Record bare `#[cached]` or extract the parenthesized argument list
    if index == bytes.len() {
        out.push(CachedAttribute { line, args: None });
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
        args: Some(inner[index + 1..close].to_string()),
    });
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

/// Counts newline characters in `slice`.
fn count_newlines(slice: &str) -> usize {
    slice.matches('\n').count()
}

/// Extracts every `crate::` path referenced by the source: flattened `use`
/// trees plus inline paths. Line comments are ignored.
fn crate_paths(source: &str) -> BTreeSet<String> {
    let mut paths = BTreeSet::new();
    let code = strip_line_comments(source);
    let tokens = tokenize(&code);

    let mut index = 0;
    while index < tokens.len() {
        if tokens[index] == "use" && tokens.get(index + 1) == Some(&"crate") {
            // Flatten the use tree that starts after `crate::`
            index = parse_use_tree(&tokens, index + 3, &[], &mut paths);
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
    paths
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
            let mut cursor = skip_ws_and_comments(source, index + 1);
            if bytes.get(cursor) == Some(&b'[') {
                // Find the matching closing bracket of the outer attribute
                let content_start = cursor + 1;
                if let Some(content_end) = find_matching_delimiter(source, cursor, b'[', b']') {
                    let inner = &source[content_start..content_end];
                    collect_cached_attributes(inner, attr_line, &mut attributes);
                    cursor = content_end + 1;
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

/// Returns whether the token is an identifier.
fn is_identifier(token: &str) -> bool {
    token
        .chars()
        .next()
        .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
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

/// Parses a use tree starting at `index`, appending each flattened path
/// (prefixed by `prefix`) to `paths`, and returns the index after the tree.
fn parse_use_tree(
    tokens: &[&str],
    mut index: usize,
    prefix: &[&str],
    paths: &mut BTreeSet<String>,
) -> usize {
    let mut segments: Vec<&str> = prefix.to_vec();
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
                        Some(_) => index = parse_use_tree(tokens, index, &segments, paths),
                    }
                }
                return index;
            }
            "::" => index += 1,
            "as" => index += 2,
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
        paths.insert(segments.join("::"));
    }
    index
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

/// Returns the source with line comments removed, so documentation can mention
/// paths and identifiers freely.
fn strip_line_comments(source: &str) -> String {
    source
        .lines()
        .map(|line| match line.find("//") {
            Some(index) => &line[..index],
            None => line,
        })
        .fold(String::new(), |mut acc, line| {
            acc.push_str(line);
            acc.push('\n');
            acc
        })
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
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            walk_rust_files(&path, files);
        } else if path.extension().is_some_and(|ext| ext == "rs") {
            files.push(path);
        }
    }
}
