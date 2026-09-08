//! Layer dependency rules for the backend, enforced at test time.
//!
//! `docs/backend.md` defines the dependency direction `router -> handlers ->
//! services -> db`, with `types` and `templates` as leaves. The test in this
//! module reads every Rust source file under the layered directories, collects
//! the `crate::` paths it references (both `use` trees and inline paths), and
//! fails on a forbidden edge that is not listed in an allowance. Allowances
//! exist only for edges that are still being migrated; an allowance that no
//! longer matches any edge also fails the test, so the lists shrink with each
//! migration and never grow silently.

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
    "db::event::AttendEventResult",
    "db::notifications::CustomNotificationTracking",
    "db::payments::CompletePaymentJobRecoveryInput",
    "db::payments::PrepareEventCheckoutPurchaseInput",
    "db::payments::PrepareEventCheckoutPurchaseResult",
];

/// Handler files that still reference `db` operation types, as
/// `(source file, operation type)`. Each entry is removed when the workflow
/// moves behind a manager.
const HANDLER_OPERATION_TYPE_ALLOWANCES: &[(&str, &str)] = &[
    (
        "handlers/auth.rs",
        "db::auth::EmailVerificationNotification",
    ),
    (
        "handlers/dashboard/group/attendees.rs",
        "db::dashboard::group::EventAdmissionAllocationResult",
    ),
    (
        "handlers/dashboard/group/attendees.rs",
        "db::dashboard::group::EventAttendeeCancellationStatus",
    ),
    (
        "handlers/dashboard/group/attendees.rs",
        "db::dashboard::group::EventAttendeeInvitationInput",
    ),
    (
        "handlers/dashboard/group/attendees.rs",
        "db::notifications::CustomNotificationTracking",
    ),
    (
        "handlers/dashboard/group/attendees/tests.rs",
        "db::dashboard::group::EventAdmissionAllocationResult",
    ),
    (
        "handlers/dashboard/group/attendees/tests.rs",
        "db::dashboard::group::EventAttendeeCancellationStatus",
    ),
    (
        "handlers/dashboard/group/members.rs",
        "db::notifications::CustomNotificationTracking",
    ),
    (
        "handlers/dashboard/group/refunds.rs",
        "db::payments::CompletePaymentJobRecoveryInput",
    ),
    ("handlers/event.rs", "db::event::AttendEventResult"),
    (
        "handlers/event.rs",
        "db::payments::PrepareEventCheckoutPurchaseInput",
    ),
    (
        "handlers/event.rs",
        "db::payments::PrepareEventCheckoutPurchaseResult",
    ),
    ("handlers/event/tests.rs", "db::event::AttendEventResult"),
    (
        "handlers/event/tests.rs",
        "db::payments::PrepareEventCheckoutPurchaseResult",
    ),
];

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
fn layer_dependencies_follow_backend_rules() {
    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let files = collect_source_files(&src_dir);
    let mut violations = Vec::new();

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

/// Extracts every `crate::` path referenced by the source: flattened `use`
/// trees plus inline paths. Line comments are ignored so documentation can
/// mention paths freely.
fn crate_paths(source: &str) -> BTreeSet<String> {
    let mut paths = BTreeSet::new();
    let code: String = source
        .lines()
        .map(|line| match line.find("//") {
            Some(index) => &line[..index],
            None => line,
        })
        .fold(String::new(), |mut acc, line| {
            acc.push_str(line);
            acc.push('\n');
            acc
        });
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

/// Returns whether the token is an identifier.
fn is_identifier(token: &str) -> bool {
    token
        .chars()
        .next()
        .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
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
