use std::{
    collections::BTreeMap,
    env,
    ffi::OsStr,
    fs::{self, File},
    path::{Path, PathBuf},
    process::Command,
    time::SystemTime,
};

use anyhow::{Result, bail};
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64_STANDARD};
use sha2::{Digest, Sha256};
use which::which;

/// Relative path of the shared base template under the templates directory.
const BASE_TEMPLATE_REL_PATH: &str = "common/base.html";

/// Marker touched when switching into `OCG_DEV_STATIC=1` mode so cached hashed
/// builds in other Cargo profiles rerun and restore hashed `dist/templates`.
const BUILD_MODE_DEV_MARKER_PATH: &str = "dist/.build-mode-dev-static";

/// File recording the last active build mode (`dev-static` or `hashed`).
/// Not registered with Cargo; read only to decide when to touch a mode marker.
const BUILD_MODE_FILE_PATH: &str = "dist/.build-mode";

/// Marker touched when switching into hashed mode so cached `OCG_DEV_STATIC=1`
/// builds rerun and restore unhashed `dist/templates`.
const BUILD_MODE_HASHED_MARKER_PATH: &str = "dist/.build-mode-hashed";

/// Environment variable indicating a CI build environment.
const CI_ENV_VAR: &str = "CI";

/// Environment variable that may provide the current commit SHA.
const COMMIT_SHA_ENV_VAR: &str = "OCG_COMMIT_SHA";

/// Environment variable that opts into live-disk static serving in debug builds.
/// Pair with `just server-dev` (or `tailwindcss --watch`) for live CSS rebuilds.
const DEV_STATIC_ENV_VAR: &str = "OCG_DEV_STATIC";

/// Path to the documentation source directory.
const DOCS_PATH: &str = "../docs";

/// Subdirectory inside the static distribution directory for documentation files.
const DOCS_STATIC_SUBDIR: &str = "docs";

/// Static asset directories whose files should be content hashed.
const HASHED_ASSET_DIRS: [&str; 2] = ["css", "js"];

/// Opening tag of the static inline import map in the base template.
const IMPORT_MAP_OPEN_TAG: &str = r#"<script type="importmap">"#;

/// Environment variable that keeps e2e static assets in release builds.
const INCLUDE_E2E_ASSETS_ENV_VAR: &str = "OCG_INCLUDE_E2E_ASSETS";

/// Relative paths of static inline scripts included in rendered templates.
const INLINE_SCRIPT_PATHS: [&str; 2] = [
    "common/scripts/deployment_refresh_cleanup.js",
    "common/scripts/preferences_init.js",
];

/// Path to the dedicated dev-static distribution directory used when
/// `OCG_DEV_STATIC=1` is active. Kept separate from `STATIC_DIST_PATH` so
/// hashed debug builds and tests never delete the live-watched stylesheet.
const STATIC_DEV_DIST_PATH: &str = "dist/static-dev";

/// Path to the static assets distribution directory that retains e2e fixtures
/// (used by debug builds and `OCG_INCLUDE_E2E_ASSETS=1` release builds). This
/// path contains a copy of the static assets with some modifications applied
/// (e.g. assets hashed paths).
const STATIC_DIST_PATH: &str = "dist/static";

/// Path to the e2e-only static images directory.
const STATIC_E2E_IMAGES_PATH: &str = "static/images/e2e";

/// Legacy generated stylesheet path under `static/` skipped when copying into
/// dist so stale pre-existing local files are never copied transiently.
const STATIC_GENERATED_STYLES_PATH: &str = "static/css/styles.css";

/// Path to the static assets directory.
const STATIC_PATH: &str = "static";

/// Path to the release static assets distribution directory that omits e2e
/// fixtures. Kept separate from `STATIC_DIST_PATH` so release builds never
/// remove e2e fixtures needed by debug or opted-in builds.
const STATIC_RELEASE_DIST_PATH: &str = "dist/static-release";

/// Relative path of the generated Tailwind stylesheet under the static directory.
const STYLES_REL_PATH: &str = "css/styles.css";

/// Relative path of the Tailwind CSS entry stylesheet under the static directory.
const STYLES_SRC_REL_PATH: &str = "css/styles.src.css";

/// Pinned Tailwind CSS CLI version. Keep in sync with `ocg-server/Dockerfile`
/// and `.github/actions/install-tailwind/action.yml`.
const TAILWIND_VERSION: &str = "4.3.5";

/// Path to the templates distribution directory. This path contains a copy of
/// the templates with some modifications applied (e.g. assets hashed paths).
const TEMPLATES_DIST_PATH: &str = "dist/templates";

/// Path to the templates directory.
const TEMPLATES_PATH: &str = "templates";

/// Mapping from plain static asset paths to their final hashed paths.
type AssetsManifest = BTreeMap<String, String>;

/// Static asset that receives a content-hashed filename.
struct HashedAsset {
    /// Plain static asset paths referenced by this asset.
    dependencies: Vec<String>,
    /// Source file path.
    source_path: PathBuf,
}

fn main() -> Result<()> {
    // Register rebuild triggers and compile-time configuration flags
    println!("cargo:rerun-if-changed={TEMPLATES_PATH}");
    println!("cargo:rerun-if-env-changed={CI_ENV_VAR}");
    println!("cargo:rerun-if-env-changed={COMMIT_SHA_ENV_VAR}");
    println!("cargo:rerun-if-env-changed={DEV_STATIC_ENV_VAR}");
    println!("cargo:rerun-if-env-changed={INCLUDE_E2E_ASSETS_ENV_VAR}");
    println!("cargo:rustc-check-cfg=cfg(ocg_dev_static)");
    println!("cargo:rustc-check-cfg=cfg(ocg_exclude_e2e_assets)");
    println!(
        "cargo:rustc-env=OCG_BUILD_PROFILE={}",
        env::var("PROFILE").unwrap_or_default()
    );
    println!("cargo:rustc-env=OCG_COMMIT_SHA={}", commit_sha());

    // Resolve live-disk dev static mode; watch only the opposite mode's marker
    // so switching modes across profiles invalidates the other profile without
    // making the current run self-invalidate on the next same-mode build
    let dev_static = use_dev_static()?;
    let (build_mode, own_marker, other_marker) = if dev_static {
        (
            "dev-static",
            BUILD_MODE_DEV_MARKER_PATH,
            BUILD_MODE_HASHED_MARKER_PATH,
        )
    } else {
        (
            "hashed",
            BUILD_MODE_HASHED_MARKER_PATH,
            BUILD_MODE_DEV_MARKER_PATH,
        )
    };
    ensure_epoch_marker_exists(Path::new(other_marker))?;
    println!("cargo:rerun-if-changed={other_marker}");
    if dev_static {
        println!("cargo:rustc-cfg=ocg_dev_static");
    } else {
        println!("cargo:rerun-if-changed={DOCS_PATH}");
        println!("cargo:rerun-if-changed={STATIC_PATH}");
    }

    // Route each build mode to an isolated static dist directory so debug,
    // dev-static, and release builds never overwrite one another's assets
    let exclude_e2e = !include_e2e_assets();
    if exclude_e2e {
        println!("cargo:rustc-cfg=ocg_exclude_e2e_assets");
    }
    let static_dist_dir = Path::new(if dev_static {
        STATIC_DEV_DIST_PATH
    } else if exclude_e2e {
        STATIC_RELEASE_DIST_PATH
    } else {
        STATIC_DIST_PATH
    });

    // Verify Tailwind CSS is installed and check its version against the pin
    check_tailwind_version()?;

    // Prepare static assets according to the active build mode
    let assets_manifest = if dev_static {
        build_tailwind_styles(static_dist_dir)?;
        AssetsManifest::new()
    } else {
        prepare_hashed_static_assets(static_dist_dir, exclude_e2e)?
    };

    // Touch this mode's marker before rewriting dist/templates so cached builds
    // of the opposite mode still rerun even if a later step fails
    record_build_mode_transition(build_mode, Path::new(own_marker))?;

    // Copy templates to the dist directory and rewrite hashed asset references
    prepare_templates(&assets_manifest)?;

    // Compute build-time CSP script hashes from the final emitted template bytes
    let csp_script_hashes = compute_csp_script_hashes(Path::new(TEMPLATES_DIST_PATH))?;
    println!(
        "cargo:rustc-env=OCG_CSP_SCRIPT_HASHES={}",
        csp_script_hashes.join(" ")
    );

    // Copy documentation and rewrite its standalone theme link for hashed builds
    if !dev_static {
        prepare_docs(static_dist_dir, &assets_manifest)?;
    }

    Ok(())
}

/// Returns supported static asset reference patterns for a path.
fn asset_ref_patterns(asset_path: &str) -> Vec<String> {
    vec![
        format!("\"{asset_path}\""),
        format!("'{asset_path}'"),
        format!("`{asset_path}`"),
        format!("url({asset_path})"),
        format!("url(\"{asset_path}\")"),
        format!("url('{asset_path}')"),
    ]
}

/// Returns manifest entries ordered by longest plain path first.
fn asset_refs_by_length(manifest: &AssetsManifest) -> Vec<(String, String)> {
    let mut refs: Vec<(String, String)> = manifest
        .iter()
        .map(|(plain_path, hashed_path)| (plain_path.clone(), hashed_path.clone()))
        .collect();
    refs.sort_by(|(left_path, _), (right_path, _)| {
        right_path
            .len()
            .cmp(&left_path.len())
            .then_with(|| left_path.cmp(right_path))
    });

    refs
}

/// Builds the graph of hashable static assets and the references between them
/// from the populated static distribution directory.
fn build_hashed_assets_graph(static_dist_dir: &Path) -> Result<BTreeMap<String, HashedAsset>> {
    // Collect all hashable source files from the static dist directory
    let mut source_paths = Vec::new();
    for dir in HASHED_ASSET_DIRS {
        collect_file_paths(&static_dist_dir.join(dir), &mut source_paths)?;
    }

    // Build the set of public paths that can be rewritten
    let mut plain_paths = Vec::with_capacity(source_paths.len());
    for source_path in &source_paths {
        plain_paths.push(static_asset_path(static_dist_dir, source_path)?);
    }
    plain_paths.sort();

    // Record references between hashable assets
    let mut graph = BTreeMap::new();
    for source_path in source_paths {
        let plain_path = static_asset_path(static_dist_dir, &source_path)?;
        let content = fs::read_to_string(&source_path)?;
        let dependencies = plain_paths
            .iter()
            .filter(|dependency_path| content_contains_asset_ref(&content, dependency_path))
            .cloned()
            .collect();

        graph.insert(
            plain_path,
            HashedAsset {
                dependencies,
                source_path,
            },
        );
    }

    Ok(graph)
}

/// Runs Tailwind CSS with minification, writing directly into the dist directory.
fn build_tailwind_styles(static_dist_dir: &Path) -> Result<()> {
    // Ensure the CSS output directory exists before invoking Tailwind
    let input = Path::new(STATIC_PATH).join(STYLES_SRC_REL_PATH);
    let output = static_dist_dir.join(STYLES_REL_PATH);
    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent)?;
    }

    run(
        "tailwindcss",
        &[
            "-i",
            input.to_string_lossy().as_ref(),
            "-o",
            output.to_string_lossy().as_ref(),
            "--minify",
        ],
    )
}

/// Calculates the hex-encoded SHA-256 hash of content.
fn calculate_hash(content: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(content);
    hex::encode(hasher.finalize())
}

/// Checks that `tailwindcss` is on `PATH` and validates its version against the pin.
///
/// Rejects missing, unparseable, or non-v4 binaries everywhere. Mismatches
/// within Tailwind CSS v4 fail the build when `CI` is set and emit a Cargo
/// warning locally.
fn check_tailwind_version() -> Result<()> {
    // Verify the Tailwind CLI binary is available on PATH
    if which("tailwindcss").is_err() {
        bail!("tailwindcss not found in PATH (required)");
    }

    // Query the CLI banner without running a stylesheet build or emitting ANSI colors
    let output = new_cmd("tailwindcss")
        .arg("--help")
        .env("NO_COLOR", "1")
        .env_remove("FORCE_COLOR")
        .output()?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    if !output.status.success() {
        bail!(
            "tailwindcss --help exited with {}\n(stderr)\n{stderr}\n(stdout)\n{stdout}",
            output.status
        );
    }

    // Parse and validate the installed Tailwind CSS version
    let Some(installed) =
        parse_tailwind_version(&stdout).or_else(|| parse_tailwind_version(&stderr))
    else {
        bail!(
            "could not determine tailwindcss version from `tailwindcss --help` output (expected v{TAILWIND_VERSION})"
        );
    };
    let Some(major) = parse_semver_major(&installed) else {
        bail!("unrecognized tailwindcss version '{installed}' (expected v{TAILWIND_VERSION})");
    };
    if major != 4 {
        bail!(
            "unsupported tailwindcss version v{installed}; expected v{TAILWIND_VERSION} (Tailwind CSS v4)"
        );
    }

    // Fail hard on version drift in CI and emit a warning locally
    if installed != TAILWIND_VERSION {
        if is_ci() {
            bail!("tailwindcss v{installed} does not match pinned version v{TAILWIND_VERSION}");
        }
        println!(
            "cargo:warning=tailwindcss v{installed} does not match pinned version v{TAILWIND_VERSION}"
        );
    }

    Ok(())
}

/// Collects all non-dotfile paths in a directory and its subdirectories.
fn collect_file_paths(path: &Path, file_paths: &mut Vec<PathBuf>) -> Result<()> {
    if path.is_dir() {
        for entry in fs::read_dir(path)? {
            let entry = entry?;
            if is_dotfile(&entry.file_name()) {
                continue;
            }
            let path = entry.path();
            if path.is_dir() {
                collect_file_paths(&path, file_paths)?;
            } else if path.is_file() {
                file_paths.push(path);
            }
        }
    }

    Ok(())
}

/// Returns the commit SHA for the current build.
fn commit_sha() -> String {
    if let Some(sha) = env::var(COMMIT_SHA_ENV_VAR)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
    {
        return sha;
    }

    "unknown".to_string()
}

/// Computes sorted CSP SHA-256 hashes for all static inline scripts and the import map.
fn compute_csp_script_hashes(templates_dist_dir: &Path) -> Result<Vec<String>> {
    let mut hashes = Vec::with_capacity(INLINE_SCRIPT_PATHS.len() + 1);

    // Normalize line endings to LF before hashing so Askama, build.rs, and browsers agree
    // even on CRLF checkouts; Askama trims a single trailing LF on included files
    for rel_path in INLINE_SCRIPT_PATHS {
        let script_path = templates_dist_dir.join(rel_path);
        let content = normalize_lf_in_file(&script_path)?;
        ensure_no_askama_delimiters(&content, &script_path)?;
        let emitted = strip_single_trailing_lf(&content);
        hashes.push(csp_sha256_hash(emitted.as_bytes()));
    }

    // Normalize the base template to LF and hash the static import map inner bytes
    let base_template_path = templates_dist_dir.join(BASE_TEMPLATE_REL_PATH);
    let base_template = normalize_lf_in_file(&base_template_path)?;
    let import_map_body = extract_unique_tag_body(
        &base_template,
        IMPORT_MAP_OPEN_TAG,
        "</script>",
        &base_template_path,
    )?;
    ensure_no_askama_delimiters(import_map_body, &base_template_path)?;
    if import_map_body != import_map_body.trim() {
        bail!(
            "{} contains leading or trailing whitespace inside {IMPORT_MAP_OPEN_TAG}",
            base_template_path.display()
        );
    }
    hashes.push(csp_sha256_hash(import_map_body.as_bytes()));

    // Sort and deduplicate hashes for deterministic compiler output
    hashes.sort();
    hashes.dedup();

    Ok(hashes)
}

/// Returns true when the content includes a supported reference to an asset path.
fn content_contains_asset_ref(content: &str, asset_path: &str) -> bool {
    asset_ref_patterns(asset_path)
        .iter()
        .any(|pattern| content.contains(pattern))
}

/// Copies a directory recursively, skipping dotfiles and excluded paths.
fn copy_dir(src: &Path, dst: &Path, excluded_paths: &[&Path]) -> Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let entry_name = entry.file_name();
        let entry_path = entry.path();
        if is_dotfile(&entry_name) || excluded_paths.contains(&entry_path.as_path()) {
            continue;
        }
        if entry.file_type()?.is_dir() {
            copy_dir(&entry_path, &dst.join(&entry_name), excluded_paths)?;
        } else {
            fs::copy(&entry_path, dst.join(&entry_name))?;
        }
    }

    Ok(())
}

/// Formats a CSP SHA-256 source expression for the given bytes.
fn csp_sha256_hash(content: &[u8]) -> String {
    let digest = Sha256::digest(content);
    format!("'sha256-{}'", BASE64_STANDARD.encode(digest))
}

/// Creates a marker file with Unix-epoch mtime if it does not exist yet so
/// registering it with `cargo:rerun-if-changed` never triggers a self-rerun.
fn ensure_epoch_marker_exists(path: &Path) -> Result<()> {
    if path.exists() {
        return Ok(());
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let file = File::create(path)?;
    file.set_modified(SystemTime::UNIX_EPOCH)?;

    Ok(())
}

/// Rejects Askama delimiters in static script bodies hashed at build time.
fn ensure_no_askama_delimiters(content: &str, path: &Path) -> Result<()> {
    for delimiter in ["{{", "{%", "{#"] {
        if content.contains(delimiter) {
            bail!(
                "{} contains Askama delimiter '{delimiter}' inside a build-time hashed script",
                path.display()
            );
        }
    }

    Ok(())
}

/// Extracts the inner text of a tag that must appear exactly once in `content`.
fn extract_unique_tag_body<'a>(
    content: &'a str,
    open_tag: &str,
    close_tag: &str,
    path: &Path,
) -> Result<&'a str> {
    let Some(start) = content.find(open_tag) else {
        bail!("{} does not contain {open_tag}", path.display());
    };
    let after_open = &content[start + open_tag.len()..];
    if after_open.contains(open_tag) {
        bail!("{} contains multiple {open_tag} tags", path.display());
    }
    let Some(end) = after_open.find(close_tag) else {
        bail!(
            "{} is missing closing {close_tag} for {open_tag}",
            path.display()
        );
    };

    Ok(&after_open[..end])
}

/// Returns the final public path for a content-hashed static asset.
fn hashed_static_asset_path(plain_path: &str, hash: &str) -> String {
    let (parent, file_name) = plain_path.rsplit_once('/').unwrap_or(("", plain_path));
    let hashed_file_name = match file_name.rsplit_once('.') {
        Some((stem, ext)) if !stem.is_empty() => format!("{stem}.{}.{ext}", &hash[..8]),
        _ => format!("{file_name}.{}", &hash[..8]),
    };

    if parent.is_empty() && !plain_path.starts_with('/') {
        hashed_file_name
    } else {
        format!("{parent}/{hashed_file_name}")
    }
}

/// Returns whether e2e static assets should be copied into the distribution directory.
fn include_e2e_assets() -> bool {
    if !is_release_profile() {
        return true;
    }

    match env::var(INCLUDE_E2E_ASSETS_ENV_VAR) {
        Ok(value) => match value.trim() {
            "1" => true,
            "" | "0" => false,
            other => {
                println!(
                    "cargo:warning=ignoring unrecognized {INCLUDE_E2E_ASSETS_ENV_VAR} value '{other}'; set {INCLUDE_E2E_ASSETS_ENV_VAR}=1 to include e2e static assets in release builds"
                );
                false
            }
        },
        Err(_) => false,
    }
}

/// Returns whether the build is running in a CI environment.
fn is_ci() -> bool {
    env::var(CI_ENV_VAR).is_ok_and(|value| {
        let trimmed = value.trim();
        !trimmed.is_empty() && !matches!(trimmed.to_ascii_lowercase().as_str(), "0" | "false")
    })
}

/// Returns whether a directory entry name starts with a dot.
fn is_dotfile(name: &OsStr) -> bool {
    name.as_encoded_bytes().starts_with(b".")
}

/// Returns whether Cargo is building the release profile.
fn is_release_profile() -> bool {
    env::var("PROFILE").is_ok_and(|profile| profile == "release")
}

/// Sets up a command based on the target OS.
fn new_cmd(program: &str) -> Command {
    if cfg!(target_os = "windows") {
        let mut cmd = Command::new("cmd");
        cmd.args(["/C", program]);
        cmd
    } else {
        Command::new(program)
    }
}

/// Normalizes CRLF and CR line endings to LF in place and returns the normalized text.
fn normalize_lf_in_file(path: &Path) -> Result<String> {
    let original = fs::read_to_string(path)?;
    if !original.contains('\r') {
        return Ok(original);
    }

    // Rewrite the copied dist file so Askama compiles the exact LF bytes hashed here
    let normalized = original.replace("\r\n", "\n").replace('\r', "\n");
    fs::write(path, &normalized)?;

    Ok(normalized)
}

/// Validates a full semantic version token and returns its major version number.
fn parse_semver_major(version: &str) -> Option<u64> {
    // Split optional build metadata (`+...`) and prerelease (`-...`) suffixes
    let (without_build, build_meta) = match version.split_once('+') {
        Some((before, after)) => (before, Some(after)),
        None => (version, None),
    };
    let (core, prerelease) = match without_build.split_once('-') {
        Some((before, after)) => (before, Some(after)),
        None => (without_build, None),
    };

    // Validate prerelease identifiers (numeric identifiers may not have leading zeros)
    if let Some(prerelease) = prerelease
        && (prerelease.is_empty()
            || prerelease.split('.').any(|ident| {
                ident.is_empty()
                    || !ident.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
                    || (ident.len() > 1
                        && ident.starts_with('0')
                        && ident.bytes().all(|b| b.is_ascii_digit()))
            }))
    {
        return None;
    }

    // Validate build metadata identifiers (leading zeros are allowed)
    if let Some(build_meta) = build_meta
        && (build_meta.is_empty()
            || build_meta.split('.').any(|ident| {
                ident.is_empty() || !ident.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
            }))
    {
        return None;
    }

    // Parse and validate numeric MAJOR.MINOR.PATCH components
    let mut parts = core.split('.');
    let major = parse_semver_number(parts.next()?)?;
    let _minor = parse_semver_number(parts.next()?)?;
    let _patch = parse_semver_number(parts.next()?)?;
    if parts.next().is_some() {
        return None;
    }

    Some(major)
}

/// Parses a non-empty ASCII-digits-only semantic version numeric component.
fn parse_semver_number(part: &str) -> Option<u64> {
    if part.is_empty() || !part.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    if part.len() > 1 && part.starts_with('0') {
        return None;
    }

    part.parse::<u64>().ok()
}

/// Extracts the Tailwind CSS version string from `tailwindcss --help` output.
fn parse_tailwind_version(output: &str) -> Option<String> {
    let cleaned = strip_ansi_escapes(output);
    let after_prefix = cleaned.split_once("tailwindcss v")?.1;
    let version = after_prefix.split_whitespace().next()?;
    if version.is_empty() {
        return None;
    }

    Some(version.to_string())
}

/// Copies documentation into the static dist directory and rewrites its theme link.
fn prepare_docs(static_dist_dir: &Path, assets_manifest: &AssetsManifest) -> Result<()> {
    // Copy documentation source files into dist
    let docs_static_dist_dir = static_dist_dir.join(DOCS_STATIC_SUBDIR);
    copy_dir(Path::new(DOCS_PATH), &docs_static_dist_dir, &[])?;

    // Point the standalone documentation index at the hashed docs theme. Only
    // the index is rewritten, as Markdown prose quoting static asset paths
    // must stay as written.
    replace_hashed_assets_refs_in_file(&docs_static_dist_dir.join("index.html"), assets_manifest)
}

/// Copies static assets into dist, builds minified Tailwind CSS there, and hashes assets.
fn prepare_hashed_static_assets(
    static_dist_dir: &Path,
    exclude_e2e: bool,
) -> Result<AssetsManifest> {
    // Recreate the static dist directory excluding dotfiles and legacy generated CSS
    remove_dir_if_exists(static_dist_dir)?;
    let mut excluded_static_paths = vec![Path::new(STATIC_GENERATED_STYLES_PATH)];
    if exclude_e2e {
        excluded_static_paths.push(Path::new(STATIC_E2E_IMAGES_PATH));
    }
    copy_dir(
        Path::new(STATIC_PATH),
        static_dist_dir,
        &excluded_static_paths,
    )?;

    // Build minified Tailwind CSS directly into the dist directory
    build_tailwind_styles(static_dist_dir)?;

    // Rewrite hashable assets and generate a manifest mapping original asset
    // paths to their final hashed versions
    write_hashed_static_assets(static_dist_dir)
}

/// Copies templates into dist and rewrites static asset references when hashed.
fn prepare_templates(assets_manifest: &AssetsManifest) -> Result<()> {
    // Copy templates into a clean dist directory
    remove_dir_if_exists(Path::new(TEMPLATES_DIST_PATH))?;
    copy_dir(
        Path::new(TEMPLATES_PATH),
        Path::new(TEMPLATES_DIST_PATH),
        &[],
    )?;

    // Replace asset path references with their hashed versions when hashing is active
    if !assets_manifest.is_empty() {
        replace_hashed_assets_refs(Path::new(TEMPLATES_DIST_PATH), assets_manifest)?;
    }

    Ok(())
}

/// Records a mode switch and touches this mode's marker file so cached builds
/// of the opposite mode invalidate on their next run.
fn record_build_mode_transition(mode: &str, own_marker: &Path) -> Result<()> {
    let mode_file = Path::new(BUILD_MODE_FILE_PATH);
    if fs::read_to_string(mode_file).ok().as_deref() == Some(mode) {
        return Ok(());
    }
    if let Some(parent) = own_marker.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(own_marker, mode)?;
    fs::write(mode_file, mode)?;

    Ok(())
}

/// Removes a directory recursively if it exists.
fn remove_dir_if_exists(path: &Path) -> Result<()> {
    if let Err(err) = fs::remove_dir_all(path)
        && err.kind() != std::io::ErrorKind::NotFound
    {
        bail!(err);
    }

    Ok(())
}

/// Replaces asset path references with their hashed versions in a directory tree.
fn replace_hashed_assets_refs(path: &Path, manifest: &AssetsManifest) -> Result<()> {
    if path.is_dir() {
        for entry in fs::read_dir(path)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_dir() {
                replace_hashed_assets_refs(&path, manifest)?;
            } else if path.is_file() {
                replace_hashed_assets_refs_in_file(&path, manifest)?;
            }
        }
    }

    Ok(())
}

/// Replaces asset path references in a string using the hashed assets manifest.
fn replace_hashed_assets_refs_in_content(content: &str, manifest: &AssetsManifest) -> String {
    let mut new_content = content.to_string();

    for (plain_path, hashed_path) in asset_refs_by_length(manifest) {
        new_content = new_content.replace(&plain_path, &hashed_path);
    }

    new_content
}

/// Replaces asset path references with their hashed versions in a single file.
fn replace_hashed_assets_refs_in_file(path: &Path, manifest: &AssetsManifest) -> Result<()> {
    // Read file content, skipping non-UTF-8 binary files
    let original_content = match fs::read_to_string(path) {
        Ok(content) => content,
        Err(err) => {
            if err.kind() != std::io::ErrorKind::InvalidData {
                bail!(err);
            }
            return Ok(());
        }
    };

    // Replace asset paths with hashed versions
    let new_content = replace_hashed_assets_refs_in_content(&original_content, manifest);

    // Write updated content back to the file if needed
    if new_content != original_content {
        fs::write(path, new_content)?;
    }

    Ok(())
}

/// Runs an external program and fails with its output on non-zero exit.
fn run(program: &str, args: &[&str]) -> Result<()> {
    // Setup command
    let mut cmd = new_cmd(program);
    cmd.args(args);

    // Execute it and check output
    let output = cmd.output()?;
    if !output.status.success() {
        bail!(
            "\n\n> {cmd:?} (stderr)\n{}\n> {cmd:?} (stdout)\n{}\n",
            String::from_utf8_lossy(&output.stderr),
            String::from_utf8_lossy(&output.stdout)
        );
    }

    Ok(())
}

/// Returns the public `/static/...` path for an asset under `static_dist_dir`.
fn static_asset_path(static_dist_dir: &Path, path: &Path) -> Result<String> {
    let relative = path.strip_prefix(static_dist_dir)?;
    Ok(format!(
        "/{STATIC_PATH}/{}",
        relative.to_string_lossy().replace('\\', "/")
    ))
}

/// Returns the dist filesystem path for a static asset public path.
fn static_dist_path(static_dist_dir: &Path, asset_path: &str) -> Result<PathBuf> {
    Ok(static_dist_dir.join(Path::new(asset_path).strip_prefix(format!("/{STATIC_PATH}/"))?))
}

/// Removes ANSI CSI escape sequences from `input`.
fn strip_ansi_escapes(input: &str) -> String {
    let mut cleaned = String::with_capacity(input.len());
    let mut chars = input.chars().peekable();

    while let Some(ch) = chars.next() {
        if ch == '\x1b' && chars.peek() == Some(&'[') {
            chars.next();
            for seq_ch in chars.by_ref() {
                if ('@'..='~').contains(&seq_ch) {
                    break;
                }
            }
            continue;
        }
        cleaned.push(ch);
    }

    cleaned
}

/// Removes a single trailing LF, matching Askama's EOF newline trimming on includes.
fn strip_single_trailing_lf(content: &str) -> &str {
    content.strip_suffix('\n').unwrap_or(content)
}

/// Returns whether live-disk dev static serving is enabled via `OCG_DEV_STATIC=1`.
fn use_dev_static() -> Result<bool> {
    match env::var(DEV_STATIC_ENV_VAR) {
        Ok(value) => match value.trim() {
            "1" => {
                if is_release_profile() {
                    bail!("{DEV_STATIC_ENV_VAR}=1 is not supported in release builds");
                }
                if is_ci() {
                    bail!("{DEV_STATIC_ENV_VAR}=1 is not supported in CI builds");
                }
                Ok(true)
            }
            "" | "0" => Ok(false),
            other => {
                println!(
                    "cargo:warning=ignoring unrecognized {DEV_STATIC_ENV_VAR} value '{other}'; set {DEV_STATIC_ENV_VAR}=1 to serve static assets live from disk in debug builds"
                );
                Ok(false)
            }
        },
        Err(_) => Ok(false),
    }
}

/// Writes an asset after all of its dependencies have final hashed paths.
fn write_hashed_static_asset(
    plain_path: &str,
    graph: &BTreeMap<String, HashedAsset>,
    static_dist_dir: &Path,
    manifest: &mut AssetsManifest,
    visiting: &mut Vec<String>,
) -> Result<()> {
    // Return immediately when this asset has already been finalized
    if manifest.contains_key(plain_path) {
        return Ok(());
    }

    // Reject dependency cycles, which cannot produce stable content hashes
    if let Some(position) = visiting.iter().position(|path| path == plain_path) {
        let mut cycle = visiting[position..].to_vec();
        cycle.push(plain_path.to_string());
        bail!("circular hashed asset references: {}", cycle.join(" -> "));
    }

    let Some(asset) = graph.get(plain_path) else {
        bail!("hashed asset not found in dependency graph: {plain_path}");
    };

    // Finalize dependencies before hashing this asset
    visiting.push(plain_path.to_string());
    for dependency_path in &asset.dependencies {
        write_hashed_static_asset(dependency_path, graph, static_dist_dir, manifest, visiting)?;
    }
    visiting.pop();

    // Rewrite references using finalized dependencies and hash the final bytes
    let original_content = fs::read_to_string(&asset.source_path)?;
    let final_content = replace_hashed_assets_refs_in_content(&original_content, manifest);
    let hash = calculate_hash(final_content.as_bytes());
    let hashed_path = hashed_static_asset_path(plain_path, &hash);

    // Write the hashed asset and remove its unhashed dist copy
    let hashed_dist_path = static_dist_path(static_dist_dir, &hashed_path)?;
    if let Some(parent) = hashed_dist_path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(hashed_dist_path, final_content)?;

    let plain_dist_path = static_dist_path(static_dist_dir, plain_path)?;
    fs::remove_file(plain_dist_path)?;

    manifest.insert(plain_path.to_string(), hashed_path);

    Ok(())
}

/// Writes content-hashed static assets and returns their final path manifest.
fn write_hashed_static_assets(static_dist_dir: &Path) -> Result<AssetsManifest> {
    let graph = build_hashed_assets_graph(static_dist_dir)?;
    let mut manifest = AssetsManifest::new();
    let mut visiting = Vec::new();

    for plain_path in graph.keys() {
        write_hashed_static_asset(
            plain_path,
            &graph,
            static_dist_dir,
            &mut manifest,
            &mut visiting,
        )?;
    }

    Ok(manifest)
}
