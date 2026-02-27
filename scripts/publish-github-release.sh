#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-config.sh"

release_tag="${RELEASE_TAG:-v${release_version}}"
release_title="${RELEASE_TITLE:-${target_name} v${release_version}}"
release_generate_notes="${RELEASE_GENERATE_NOTES:-1}"
release_notes_file="${RELEASE_NOTES_FILE:-}"
release_draft="${RELEASE_DRAFT:-0}"
release_prerelease="${RELEASE_PRERELEASE:-0}"
release_build_artifacts="${RELEASE_BUILD_ARTIFACTS:-1}"
release_notarize="${RELEASE_NOTARIZE:-1}"
release_notarize_dmg="${RELEASE_NOTARIZE_DMG:-1}"
release_notarize_zip="${RELEASE_NOTARIZE_ZIP:-1}"
release_repo="${GITHUB_REPOSITORY:-}"

cd "${repo_root}"

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}"
    exit 1
  fi
}

extract_repo_slug_from_origin() {
  local remote_url
  remote_url="$(git config --get remote.origin.url || true)"
  if [[ -z "${remote_url}" ]]; then
    return 1
  fi

  if [[ "${remote_url}" =~ github\.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
    local owner="${BASH_REMATCH[1]}"
    local repo="${BASH_REMATCH[2]%.git}"
    echo "${owner}/${repo}"
    return 0
  fi

  return 1
}

resolve_repo_slug() {
  if [[ -n "${release_repo}" ]]; then
    echo "${release_repo}"
    return 0
  fi

  local origin_slug=""
  if origin_slug="$(extract_repo_slug_from_origin)"; then
    echo "${origin_slug}"
    return 0
  fi

  echo "Could not resolve GitHub repository slug." >&2
  echo "Set GITHUB_REPOSITORY=owner/repo or configure remote.origin to point to GitHub." >&2
  return 1
}

require_command gh
require_command git

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "Cannot publish a GitHub Release before the first commit exists (no HEAD yet)."
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree must be clean before building and publishing a release tag." >&2
  echo "Commit/stash changes and retry." >&2
  git status --short >&2
  exit 1
fi

if [[ "${release_build_artifacts}" == "1" ]]; then
  RELEASE_VERSION="${release_version}" \
  RELEASE_BUILD="${release_build}" \
  RELEASE_NOTARIZE="${release_notarize}" \
  RELEASE_NOTARIZE_DMG="${release_notarize_dmg}" \
  RELEASE_NOTARIZE_ZIP="${release_notarize_zip}" \
  ./scripts/release-build.sh
fi

for artifact in "${zip_path}" "${dmg_path}"; do
  if [[ ! -f "${artifact}" ]]; then
    echo "Missing release artifact: ${artifact}"
    echo "Run make release first, or set RELEASE_BUILD_ARTIFACTS=1."
    exit 1
  fi
done

repo_slug="$(resolve_repo_slug)"
gh_repo_args=(--repo "${repo_slug}")

if ! git rev-parse --verify "${release_tag}" >/dev/null 2>&1; then
  git tag -a "${release_tag}" -m "${release_tag}"
fi

git push origin "${release_tag}"

if gh release view "${release_tag}" "${gh_repo_args[@]}" >/dev/null 2>&1; then
  gh release upload "${release_tag}" "${zip_path}" "${dmg_path}" --clobber "${gh_repo_args[@]}"
  echo "Updated GitHub Release ${release_tag} on ${repo_slug}."
else
  create_args=()
  if [[ "${release_generate_notes}" == "1" ]]; then
    create_args+=(--generate-notes)
  elif [[ -n "${release_notes_file}" ]]; then
    create_args+=(--notes-file "${release_notes_file}")
  else
    create_args+=(--notes "Release ${release_tag}")
  fi

  if [[ "${release_draft}" == "1" ]]; then
    create_args+=(--draft)
  fi

  if [[ "${release_prerelease}" == "1" ]]; then
    create_args+=(--prerelease)
  fi

  gh release create "${release_tag}" "${zip_path}" "${dmg_path}" \
    --title "${release_title}" \
    "${create_args[@]}" \
    "${gh_repo_args[@]}"

  echo "Created GitHub Release ${release_tag} on ${repo_slug}."
fi

echo "Uploaded artifacts:"
echo " - ${zip_path}"
echo " - ${dmg_path}"
