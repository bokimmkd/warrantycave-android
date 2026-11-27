#!/bin/sh
set -eu
if [ "${CONFIGURATION:-Debug}" != "Debug" ]; then
  case "${IOS_CONFIGURATION_KIND:-local}" in
    release|internal|internal-sandbox) ;;
    *)
      echo 'error: Configure the registered iOS services before archiving.' >&2
      exit 1
      ;;
  esac
  python3 "$SRCROOT/../scripts/check_ios_release.py"
fi
source_plist="$SRCROOT/Runner/GoogleService-Info.plist"
target_plist="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/GoogleService-Info.plist"
if [ -f "$source_plist" ]; then
  mkdir -p "$(dirname "$target_plist")"
  cp "$source_plist" "$target_plist"
elif [ "${IOS_CONFIGURATION_KIND:-local}" != "local" ]; then
  echo 'error: The iOS Firebase configuration is missing.' >&2
  exit 1
fi
