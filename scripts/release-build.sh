#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-config.sh"

release_bundle_id="${RELEASE_BUNDLE_ID:-com.hosmelq.codexturn}"
release_notarize="${RELEASE_NOTARIZE:-0}"
release_notarize_dmg="${RELEASE_NOTARIZE_DMG:-1}"
release_notarize_zip="${RELEASE_NOTARIZE_ZIP:-0}"
release_archs="${RELEASE_ARCHS:-arm64 x86_64}"
release_dmg_layout="${RELEASE_DMG_LAYOUT:-1}"
release_dmg_window_width="${RELEASE_DMG_WINDOW_WIDTH:-560}"
release_dmg_window_height="${RELEASE_DMG_WINDOW_HEIGHT:-360}"
release_dmg_window_left="${RELEASE_DMG_WINDOW_LEFT:-120}"
release_dmg_window_top="${RELEASE_DMG_WINDOW_TOP:-120}"
release_dmg_icon_size="${RELEASE_DMG_ICON_SIZE:-128}"
release_dmg_icon_spacing="${RELEASE_DMG_ICON_SPACING:-220}"
release_icon_source="${RELEASE_ICON_SOURCE:-${repo_root}/assets/AppIcon.png}"
release_icon_name="${RELEASE_ICON_NAME:-AppIcon}"
release_icon_zoom="${RELEASE_ICON_ZOOM:-1.15}"
app_contents_path="${app_bundle_path}/Contents"
app_executable_path="${app_contents_path}/MacOS/${target_name}"
app_resources_path="${app_contents_path}/Resources"
app_frameworks_path="${app_contents_path}/Frameworks"
app_info_plist_path="${app_contents_path}/Info.plist"
app_icon_icns_path="${app_resources_path}/${release_icon_name}.icns"
build_bin_path=""
build_products_path=""
release_dmg_volume_name="${RELEASE_DMG_VOLUME_NAME:-${target_name}}"
release_dmg_mount_dir=""
release_dmg_temp_rw_path=""
release_dmg_attached=0
release_dmg_layout_created=0
declare -a cleanup_tmp_dirs=()

cd "${repo_root}"

if [[ ! "${release_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "RELEASE_VERSION must use semantic version format (for example: 1.0.0)."
  exit 1
fi

if [[ ! "${release_build}" =~ ^[0-9]+$ ]]; then
  echo "RELEASE_BUILD must be a positive integer."
  exit 1
fi

if [[ -n "${release_sparkle_feed_url}" && -z "${release_sparkle_public_ed_key}" ]]; then
  echo "RELEASE_SPARKLE_PUBLIC_ED_KEY is required when RELEASE_SPARKLE_FEED_URL is set."
  exit 1
fi

if [[ -z "${release_sparkle_feed_url}" && -n "${release_sparkle_public_ed_key}" ]]; then
  echo "RELEASE_SPARKLE_FEED_URL is required when RELEASE_SPARKLE_PUBLIC_ED_KEY is set."
  exit 1
fi

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}"
    exit 1
  fi
}

register_cleanup_tmp_dir() {
  local tmp_path="$1"
  if [[ -n "${tmp_path}" ]]; then
    cleanup_tmp_dirs+=("${tmp_path}")
  fi
}

safe_cleanup_path() {
  local cleanup_path="$1"
  local recursive="${2:-0}"
  local cleanup_tmp_root="${TMPDIR:-/tmp}"

  cleanup_tmp_root="${cleanup_tmp_root%/}"
  if [[ -z "${cleanup_tmp_root}" || "${cleanup_tmp_root}" == "/" ]]; then
    cleanup_tmp_root="/tmp"
  fi

  if [[ -z "${cleanup_path}" ]]; then
    return 0
  fi

  if command -v trash >/dev/null 2>&1; then
    if trash "${cleanup_path}" >/dev/null 2>&1; then
      return 0
    fi
  fi

  if [[ "${recursive}" == "1" ]]; then
    case "${cleanup_path}" in
      "${cleanup_tmp_root}"/*|/tmp/*)
        rm -rf "${cleanup_path}" >/dev/null 2>&1 || true
        ;;
    esac
    return 0
  fi

  case "${cleanup_path}" in
    "${repo_root}/${release_output_dir}/"*-layout.dmg)
      rm -f "${cleanup_path}" >/dev/null 2>&1 || true
      ;;
  esac
}

cleanup() {
  local cleanup_status=$?
  local cleanup_tmp_dir
  local skip_mount_dir_cleanup=0

  if [[ "${release_dmg_attached}" == "1" && -n "${release_dmg_mount_dir}" ]]; then
    if hdiutil detach "${release_dmg_mount_dir}" >/dev/null 2>&1 || hdiutil detach -force "${release_dmg_mount_dir}" >/dev/null 2>&1; then
      release_dmg_attached=0
    else
      skip_mount_dir_cleanup=1
      echo "Warning: could not detach DMG mount during cleanup: ${release_dmg_mount_dir}" >&2
    fi
  fi

  if [[ "${release_dmg_layout_created}" == "1" && -n "${release_dmg_temp_rw_path}" ]]; then
    safe_cleanup_path "${release_dmg_temp_rw_path}" 0
  fi

  for cleanup_tmp_dir in "${cleanup_tmp_dirs[@]}"; do
    if [[ "${skip_mount_dir_cleanup}" == "1" && "${cleanup_tmp_dir}" == "${release_dmg_mount_dir}" ]]; then
      continue
    fi
    safe_cleanup_path "${cleanup_tmp_dir}" 1
  done

  return "${cleanup_status}"
}

on_interrupt() {
  exit 130
}

on_terminate() {
  exit 143
}

trap cleanup EXIT
trap on_interrupt INT
trap on_terminate TERM

declare -a notary_auth_args=()
if [[ "${release_notarize}" == "1" ]]; then
  if [[ -z "${APPLE_CODESIGN_IDENTITY:-}" ]]; then
    echo "RELEASE_NOTARIZE=1 requires APPLE_CODESIGN_IDENTITY."
    exit 1
  fi

  require_command xcrun

  if [[ -n "${APPLE_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    notary_auth_args=(--keychain-profile "${APPLE_NOTARY_KEYCHAIN_PROFILE}")
  elif [[ -n "${APPLE_NOTARY_KEY_PATH:-}" && -n "${APPLE_NOTARY_KEY_ID:-}" && -n "${APPLE_NOTARY_ISSUER:-}" ]]; then
    notary_auth_args=(
      --key "${APPLE_NOTARY_KEY_PATH}"
      --key-id "${APPLE_NOTARY_KEY_ID}"
      --issuer "${APPLE_NOTARY_ISSUER}"
    )
  else
    echo "Notarization credentials missing."
    echo "Set APPLE_NOTARY_KEYCHAIN_PROFILE, or set APPLE_NOTARY_KEY_PATH + APPLE_NOTARY_KEY_ID + APPLE_NOTARY_ISSUER."
    exit 1
  fi

  if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
    notary_auth_args+=(--team-id "${APPLE_TEAM_ID}")
  fi
fi

notarize_artifact() {
  local artifact_path="$1"
  echo "Submitting for notarization: ${artifact_path}"
  xcrun notarytool submit "${artifact_path}" --wait "${notary_auth_args[@]}"
}

build_icns_from_png() {
  local source_png="$1"
  local output_icns="$2"
  local iconset_dir
  local render_source_png="$source_png"
  iconset_dir="$(mktemp -d "${TMPDIR:-/tmp}/${target_name}.XXXXXX.iconset")"
  register_cleanup_tmp_dir "${iconset_dir}"

  if [[ "${release_icon_zoom}" != "1" && "${release_icon_zoom}" != "1.0" && "${release_icon_zoom}" != "1.00" ]]; then
    local source_width
    local source_height
    local crop_size
    source_width="$(sips -g pixelWidth "$source_png" | awk '/pixelWidth/ {print $2}')"
    source_height="$(sips -g pixelHeight "$source_png" | awk '/pixelHeight/ {print $2}')"
    crop_size="$(awk -v w="$source_width" -v h="$source_height" -v z="$release_icon_zoom" 'BEGIN { m = (w < h ? w : h); c = int(m / z); if (c < 16) c = 16; print c }')"
    render_source_png="${iconset_dir}/source-cropped.png"
    sips -c "$crop_size" "$crop_size" "$source_png" --out "$render_source_png" >/dev/null
  fi

  sips -z 16 16 "$render_source_png" --out "${iconset_dir}/icon_16x16.png" >/dev/null
  sips -z 32 32 "$render_source_png" --out "${iconset_dir}/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$render_source_png" --out "${iconset_dir}/icon_32x32.png" >/dev/null
  sips -z 64 64 "$render_source_png" --out "${iconset_dir}/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$render_source_png" --out "${iconset_dir}/icon_128x128.png" >/dev/null
  sips -z 256 256 "$render_source_png" --out "${iconset_dir}/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$render_source_png" --out "${iconset_dir}/icon_256x256.png" >/dev/null
  sips -z 512 512 "$render_source_png" --out "${iconset_dir}/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$render_source_png" --out "${iconset_dir}/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$render_source_png" --out "${iconset_dir}/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$iconset_dir" -o "$output_icns"
  safe_cleanup_path "${iconset_dir}" 1
}

copy_frameworks_for_release() {
  local source_directory="$1"

  if [[ ! -d "${source_directory}" ]]; then
    return
  fi

  if compgen -G "${source_directory}/*.framework" >/dev/null; then
    for framework_path in "${source_directory}"/*.framework; do
      local framework_name
      framework_name="$(basename "${framework_path}")"
      ditto "${framework_path}" "${app_frameworks_path}/${framework_name}"
    done
  fi
}

ensure_executable_framework_rpath() {
  local executable_path="$1"
  local expected_rpath="@executable_path/../Frameworks"

  if otool -l "${executable_path}" | awk '
    $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
    in_rpath && $1 == "path" { print $2; in_rpath = 0 }
  ' | grep -Fxq "${expected_rpath}"; then
    return
  fi

  install_name_tool -add_rpath "${expected_rpath}" "${executable_path}"
}

if [[ "${RELEASE_CLEAN_BUILD:-1}" == "1" ]]; then
  swift package clean
fi

declare -a release_arch_args=()
for release_arch in ${release_archs}; do
  release_arch_args+=(--arch "${release_arch}")
done

swift build -c release --product "${target_name}" "${release_arch_args[@]}"
build_products_path="$(swift build -c release --product "${target_name}" "${release_arch_args[@]}" --show-bin-path)"
build_bin_path="${build_products_path}/${target_name}"

if [[ ! -x "${build_bin_path}" ]]; then
  echo "Release binary not found at ${build_bin_path}"
  exit 1
fi

if [[ ! -f "${release_icon_source}" ]]; then
  echo "Release icon source not found at ${release_icon_source}."
  echo "Set RELEASE_ICON_SOURCE to a PNG file path."
  exit 1
fi

require_command sips
require_command iconutil
require_command otool
require_command install_name_tool

mkdir -p "${app_contents_path}/MacOS" "${app_resources_path}" "${app_frameworks_path}"
cp "${build_bin_path}" "${app_executable_path}"
chmod +x "${app_executable_path}"

if compgen -G "${build_products_path}/*.bundle" >/dev/null; then
  for resource_bundle_path in "${build_products_path}"/*.bundle; do
    ditto "${resource_bundle_path}" "${app_resources_path}/$(basename "${resource_bundle_path}")"
  done
fi

copy_frameworks_for_release "${build_products_path}"
copy_frameworks_for_release "${build_products_path}/PackageFrameworks"
ensure_executable_framework_rpath "${app_executable_path}"

build_icns_from_png "${release_icon_source}" "${app_icon_icns_path}"

sparkle_enable_automatic_checks_plist_value="<true/>"
if [[ "${release_sparkle_enable_automatic_checks}" != "1" ]]; then
  sparkle_enable_automatic_checks_plist_value="<false/>"
fi

cat > "${app_info_plist_path}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${target_name}</string>
  <key>CFBundleIdentifier</key>
  <string>${release_bundle_id}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>${release_icon_name}</string>
  <key>CFBundleName</key>
  <string>CodexTurn</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${release_version}</string>
  <key>CFBundleVersion</key>
  <string>${release_build}</string>
  <key>LSUIElement</key>
  <true/>
  <key>SUEnableAutomaticChecks</key>
  ${sparkle_enable_automatic_checks_plist_value}
  <key>SUFeedURL</key>
  <string>${release_sparkle_feed_url}</string>
  <key>SUPublicEDKey</key>
  <string>${release_sparkle_public_ed_key}</string>
</dict>
</plist>
PLIST

if [[ -n "${APPLE_CODESIGN_IDENTITY:-}" ]]; then
  codesign \
    --force \
    --deep \
    --options runtime \
    --sign "${APPLE_CODESIGN_IDENTITY}" \
    --timestamp \
    "${app_bundle_path}"
else
  codesign \
    --force \
    --deep \
    --sign - \
    "${app_bundle_path}"
fi

ditto -c -k --keepParent --sequesterRsrc "${app_bundle_path}" "${zip_path}"

release_dmg_staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/${target_name}-dmg.XXXXXX")"
release_dmg_mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/${target_name}-dmg-mount.XXXXXX")"
register_cleanup_tmp_dir "${release_dmg_staging_dir}"
register_cleanup_tmp_dir "${release_dmg_mount_dir}"
release_dmg_temp_rw_path="${repo_root}/${release_output_dir}/${target_name}-${release_version}-layout.dmg"
ditto "${app_bundle_path}" "${release_dmg_staging_dir}/${target_name}.app"
ln -s /Applications "${release_dmg_staging_dir}/Applications"

hdiutil create \
  -volname "${release_dmg_volume_name}" \
  -srcfolder "${release_dmg_staging_dir}" \
  -ov \
  -format UDRW \
  "${release_dmg_temp_rw_path}"
release_dmg_layout_created=1

hdiutil attach \
  -mountpoint "${release_dmg_mount_dir}" \
  -nobrowse \
  -readwrite \
  "${release_dmg_temp_rw_path}" >/dev/null
release_dmg_attached=1

if [[ "${release_dmg_layout}" == "1" ]] && command -v osascript >/dev/null 2>&1; then
  release_dmg_window_right=$((release_dmg_window_left + release_dmg_window_width))
  release_dmg_window_bottom=$((release_dmg_window_top + release_dmg_window_height))
  release_dmg_center_x=$((release_dmg_window_width / 2))
  release_dmg_center_y=$((release_dmg_window_height / 2))
  release_dmg_half_spacing=$((release_dmg_icon_spacing / 2))
  release_dmg_app_x=$((release_dmg_center_x - release_dmg_half_spacing))
  release_dmg_apps_x=$((release_dmg_center_x + release_dmg_half_spacing))

  if ! osascript <<APPLESCRIPT
      tell application "Finder"
        set dmgFolder to POSIX file "${release_dmg_mount_dir}" as alias
        open dmgFolder
        set dmgWindow to container window of dmgFolder
        set current view of dmgWindow to icon view
        set toolbar visible of dmgWindow to false
        set statusbar visible of dmgWindow to false
        set bounds of dmgWindow to {${release_dmg_window_left}, ${release_dmg_window_top}, ${release_dmg_window_right}, ${release_dmg_window_bottom}}
        set iconOptions to the icon view options of dmgWindow
        set arrangement of iconOptions to not arranged
        set icon size of iconOptions to ${release_dmg_icon_size}
        set position of item "${target_name}.app" of container window of dmgFolder to {${release_dmg_app_x}, ${release_dmg_center_y}}
        set position of item "Applications" of container window of dmgFolder to {${release_dmg_apps_x}, ${release_dmg_center_y}}
        set extension hidden of item "${target_name}.app" of dmgFolder to true
        delay 1
        close window of dmgFolder
      end tell
APPLESCRIPT
  then
    echo "Warning: could not apply Finder layout to DMG window."
  fi
fi

sync
hdiutil detach "${release_dmg_mount_dir}" >/dev/null
release_dmg_attached=0

hdiutil convert \
  "${release_dmg_temp_rw_path}" \
  -ov \
  -format UDZO \
  -o "${dmg_path}" >/dev/null

if [[ "${release_notarize}" == "1" && "${release_notarize_dmg}" == "1" ]]; then
  notarize_artifact "${dmg_path}"
  xcrun stapler staple -v "${dmg_path}"
fi

if [[ "${release_notarize}" == "1" && "${release_notarize_zip}" == "1" ]]; then
  notarize_artifact "${zip_path}"
fi

echo "Release version: ${release_version} (${release_build})"
echo "Release app: ${app_bundle_path}"
echo "Release zip: ${zip_path}"
echo "Release dmg: ${dmg_path}"
