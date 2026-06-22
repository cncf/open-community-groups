use std::{
    collections::BTreeMap,
    env, fs,
    path::{Path, PathBuf},
    process::Command,
};

use anyhow::{Result, bail};
use sha2::{Digest, Sha256};
use which::which;

/// Environment variable that may provide the current commit SHA.
const COMMIT_SHA_ENV_VAR: &str = "OCG_COMMIT_SHA";

/// Path to the documentation source directory.
const DOCS_PATH: &str = "../docs";

/// Path to the generated documentation static files directory.
const DOCS_STATIC_DIST_PATH: &str = "dist/static/docs";

/// Static asset directories whose files should be content hashed.
const HASHED_ASSET_DIRS: [&str; 2] = ["css", "js"];

/// Path to the static assets distribution directory. This path contains a copy
/// of the static assets with some modifications applied (e.g. assets hashed
/// paths).
const STATIC_DIST_PATH: &str = "dist/static";

/// Path to the static assets directory.
const STATIC_PATH: &str = "static";

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
    // Rerun this build script if changes are detected in the following paths.
    println!("cargo:rerun-if-changed={DOCS_PATH}");
    println!("cargo:rerun-if-changed=static");
    println!("cargo:rerun-if-changed=templates");
    println!("cargo:rerun-if-env-changed={COMMIT_SHA_ENV_VAR}");
    println!("cargo:rustc-env=OCG_COMMIT_SHA={}", commit_sha());

    // Check if required external tools are available
    if which("tailwindcss").is_err() {
        bail!("tailwindcss not found in PATH (required)");
    }

    // Prepare static assets

    // Build styles using Tailwind CSS
    run(
        "tailwindcss",
        &[
            "-i",
            format!("{STATIC_PATH}/css/styles.src.css").as_str(),
            "-o",
            format!("{STATIC_PATH}/css/styles.css").as_str(),
        ],
    )?;

    // Copy static assets to the dist directory
    if let Err(err) = fs::remove_dir_all(STATIC_DIST_PATH)
        && err.kind() != std::io::ErrorKind::NotFound
    {
        bail!(err);
    }
    copy_dir(Path::new(STATIC_PATH), Path::new(STATIC_DIST_PATH))?;

    // Rewrite hashable assets and generate a manifest mapping original asset
    // paths to their final hashed versions.
    let assets_manifest = write_hashed_static_assets()?;

    // Prepare templates

    // Copy templates to the dist directory
    if let Err(err) = fs::remove_dir_all(TEMPLATES_DIST_PATH)
        && err.kind() != std::io::ErrorKind::NotFound
    {
        bail!(err);
    }
    copy_dir(Path::new(TEMPLATES_PATH), Path::new(TEMPLATES_DIST_PATH))?;

    // Replace assets paths references with their hashed versions
    replace_hashed_assets_refs(Path::new(TEMPLATES_DIST_PATH), &assets_manifest)?;

    // Copy documentation to the dist directory
    copy_dir(Path::new(DOCS_PATH), Path::new(DOCS_STATIC_DIST_PATH))?;

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

/// Writes content-hashed static assets and returns their final path manifest.
fn write_hashed_static_assets() -> Result<AssetsManifest> {
    let graph = build_hashed_assets_graph()?;
    let mut manifest = AssetsManifest::new();
    let mut visiting = Vec::new();

    for plain_path in graph.keys() {
        write_hashed_static_asset(plain_path, &graph, &mut manifest, &mut visiting)?;
    }

    Ok(manifest)
}

/// Builds the graph of hashable static assets and the references between them.
fn build_hashed_assets_graph() -> Result<BTreeMap<String, HashedAsset>> {
    // Collect all hashable source files.
    let mut source_paths = Vec::new();
    for dir in HASHED_ASSET_DIRS {
        collect_file_paths(&Path::new(STATIC_PATH).join(dir), &mut source_paths)?;
    }

    // Build the set of public paths that can be rewritten.
    let mut plain_paths = Vec::with_capacity(source_paths.len());
    for source_path in &source_paths {
        plain_paths.push(static_asset_path(source_path));
    }
    plain_paths.sort();

    // Record references between hashable assets.
    let mut graph = BTreeMap::new();
    for source_path in source_paths {
        let plain_path = static_asset_path(&source_path);
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

/// Collects all file paths in a directory and its subdirectories.
fn collect_file_paths(path: &Path, file_paths: &mut Vec<PathBuf>) -> Result<()> {
    if path.is_dir() {
        for entry in fs::read_dir(path)? {
            let entry = entry?;
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

/// Writes an asset after all of its dependencies have final hashed paths.
fn write_hashed_static_asset(
    plain_path: &str,
    graph: &BTreeMap<String, HashedAsset>,
    manifest: &mut AssetsManifest,
    visiting: &mut Vec<String>,
) -> Result<()> {
    // Return immediately when this asset has already been finalized.
    if manifest.contains_key(plain_path) {
        return Ok(());
    }

    // Reject dependency cycles, which cannot produce stable content hashes.
    if let Some(position) = visiting.iter().position(|path| path == plain_path) {
        let mut cycle = visiting[position..].to_vec();
        cycle.push(plain_path.to_string());
        bail!("circular hashed asset references: {}", cycle.join(" -> "));
    }

    let Some(asset) = graph.get(plain_path) else {
        bail!("hashed asset not found in dependency graph: {plain_path}");
    };

    // Finalize dependencies before hashing this asset.
    visiting.push(plain_path.to_string());
    for dependency_path in &asset.dependencies {
        write_hashed_static_asset(dependency_path, graph, manifest, visiting)?;
    }
    visiting.pop();

    // Rewrite references using finalized dependencies and hash the final bytes.
    let original_content = fs::read_to_string(&asset.source_path)?;
    let final_content = replace_hashed_assets_refs_in_content(&original_content, manifest);
    let hash = calculate_hash(final_content.as_bytes());
    let hashed_path = hashed_static_asset_path(plain_path, &hash);

    // Write the hashed asset and remove its unhashed dist copy.
    let hashed_dist_path = static_dist_path(&hashed_path)?;
    if let Some(parent) = hashed_dist_path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(hashed_dist_path, final_content)?;

    let plain_dist_path = static_dist_path(plain_path)?;
    fs::remove_file(plain_dist_path)?;

    manifest.insert(plain_path.to_string(), hashed_path);

    Ok(())
}

/// Returns the public path for a source static asset.
fn static_asset_path(path: &Path) -> String {
    format!("/{}", path.display())
}

/// Returns the final public path for a content-hashed static asset.
fn hashed_static_asset_path(plain_path: &str, hash: &str) -> String {
    let path = Path::new(plain_path);
    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("");
    let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("");

    let hashed_file_name = if ext.is_empty() {
        format!("{}.{}", stem, &hash[..8])
    } else {
        format!("{}.{}.{}", stem, &hash[..8], ext)
    };
    let hashed_path = path
        .parent()
        .map(|parent| parent.join(&hashed_file_name))
        .unwrap_or_else(|| Path::new(&hashed_file_name).to_path_buf());

    hashed_path.display().to_string()
}

/// Returns the dist filesystem path for a static asset public path.
fn static_dist_path(asset_path: &str) -> Result<PathBuf> {
    Ok(Path::new(STATIC_DIST_PATH)
        .join(Path::new(asset_path).strip_prefix(format!("/{STATIC_PATH}/"))?))
}

/// Calculate sha256 hash of content.
fn calculate_hash(content: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(content);
    hex::encode(hasher.finalize())
}

/// Helper function to copy a directory recursively.
fn copy_dir(src: &Path, dst: &Path) -> Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        if entry.file_type()?.is_dir() {
            copy_dir(&entry.path(), &dst.join(entry.file_name()))?;
        } else {
            fs::copy(entry.path(), dst.join(entry.file_name()))?;
        }
    }
    Ok(())
}

/// Replace assets paths references with their hashed versions in the files in
/// the specified directory and its subdirectories based on the manifest.
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

/// Replace assets paths references with their hashed versions in the specified
/// file based on the manifest.
fn replace_hashed_assets_refs_in_file(path: &Path, manifest: &AssetsManifest) -> Result<()> {
    // Read file content
    let original_content = match fs::read_to_string(path) {
        Ok(content) => content,
        Err(err) => {
            if err.kind() != std::io::ErrorKind::InvalidData {
                bail!(err);
            }
            return Ok(());
        }
    };

    // Replace assets paths with hashed versions
    let new_content = replace_hashed_assets_refs_in_content(&original_content, manifest);

    // Write updated content back to the file if needed
    if new_content != original_content {
        fs::write(path, new_content)?;
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

/// Returns true when the content includes a supported reference to an asset path.
fn content_contains_asset_ref(content: &str, asset_path: &str) -> bool {
    asset_ref_patterns(asset_path)
        .iter()
        .any(|pattern| content.contains(pattern))
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

/// Helper function to run a command.
fn run(program: &str, args: &[&str]) -> Result<()> {
    // Setup command
    let mut cmd = new_cmd(program);
    cmd.args(args);

    // Execute it and check output
    let output = cmd.output()?;
    if !output.status.success() {
        bail!(
            "\n\n> {cmd:?} (stderr)\n{}\n> {cmd:?} (stdout)\n{}\n",
            String::from_utf8(output.stderr)?,
            String::from_utf8(output.stdout)?
        );
    }

    Ok(())
}

/// Helper function to setup a command based on the target OS.
fn new_cmd(program: &str) -> Command {
    if cfg!(target_os = "windows") {
        let mut cmd = Command::new("cmd");
        cmd.args(["/C", program]);
        cmd
    } else {
        Command::new(program)
    }
}
