#!/usr/bin/env bash

release_config_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${release_config_dir}/.." && pwd)"

target_name="CodexTurn"
release_output_dir="${RELEASE_OUTPUT_DIR:-dist}"
release_version="${RELEASE_VERSION:-1.0.0}"
release_build="${RELEASE_BUILD:-1}"
release_sparkle_feed_url="${RELEASE_SPARKLE_FEED_URL:-}"
release_sparkle_public_ed_key="${RELEASE_SPARKLE_PUBLIC_ED_KEY:-}"
release_sparkle_enable_automatic_checks="${RELEASE_SPARKLE_ENABLE_AUTOMATIC_CHECKS:-1}"

app_bundle_path="${repo_root}/${release_output_dir}/${target_name}.app"
zip_path="${repo_root}/${release_output_dir}/${target_name}-${release_version}.zip"
dmg_path="${repo_root}/${release_output_dir}/${target_name}-${release_version}.dmg"
