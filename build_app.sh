#!/bin/bash
set -e

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

APP_NAME="nervoussystemprotect"
BUNDLE_NAME="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_NAME}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Building ${APP_NAME} binary via Swift Package Manager..."
swift build -c release

BIN_DIR=$(swift build -c release --show-bin-path)
BIN_PATH="${BIN_DIR}/${APP_NAME}"

echo "==> Creating application bundle: ${BUNDLE_NAME}..."
rm -rf "${BUNDLE_NAME}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

echo "==> Copying Metal libraries and resource bundles..."
if [ -d "${BIN_DIR}/mlx-swift_Cmlx.bundle" ]; then
    cp -R "${BIN_DIR}/mlx-swift_Cmlx.bundle" "${RESOURCES_DIR}/"
    cp -R "${BIN_DIR}/mlx-swift_Cmlx.bundle" "${MACOS_DIR}/"
fi

if [ -f "${BIN_DIR}/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" ]; then
    cp "${BIN_DIR}/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" "${RESOURCES_DIR}/default.metallib"
    cp "${BIN_DIR}/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" "${RESOURCES_DIR}/mlx.metallib"
    cp "${BIN_DIR}/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" "${MACOS_DIR}/default.metallib"
    cp "${BIN_DIR}/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" "${MACOS_DIR}/mlx.metallib"
fi

echo "==> Copying AppIcon and assets..."
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi
if [ -f "Resources/AppLogo.png" ]; then
    cp "Resources/AppLogo.png" "${RESOURCES_DIR}/AppLogo.png"
fi

echo "==> Copying Python neural daemon scripts..."
if [ -d "scripts" ]; then
    cp -R "scripts" "${RESOURCES_DIR}/"
fi

echo "==> Generating Info.plist..."
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>nervoussystemprotect</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.nervoussystemprotect</string>
    <key>CFBundleName</key>
    <string>nervoussystemprotect</string>
    <key>CFBundleDisplayName</key>
    <string>nervoussystemprotect</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>nervoussystemprotect requires audio input access to capture and process audio streams from your microphone, BlackHole 2ch, or audio sources.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>nervoussystemprotect captures system audio (e.g. Teams) so it can process it before it reaches your speakers.</string>
</dict>
</plist>
EOF

echo "==> Ad-hoc code signing bundle..."
codesign --force --deep --sign - "${BUNDLE_NAME}"

echo "==> Successfully created ${BUNDLE_NAME}!"
echo "You can launch the app by running:"
echo "    open nervoussystemprotect.app"
