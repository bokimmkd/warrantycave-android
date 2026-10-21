#!/bin/sh
set -eu
if [ "${CONFIGURATION:-Debug}" != "Debug" ] && [ "${IOS_CONFIGURATION_KIND:-local}" != "release" ]; then
  echo 'error: Configure the real iOS services with scripts/configure_ios.py --release before archiving.' >&2
  exit 1
fi
if [ "${CONFIGURATION:-Debug}" != "Debug" ]; then
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
