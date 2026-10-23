#!/bin/bash
set -e

VERSION="${1:-1.0.0}"
APP_NAME="nervoussystemprotect"
BUNDLE_NAME="${APP_NAME}.app"
ARCH="macos-arm64"

RELEASE_DIR="releases"
DMG_NAME="${APP_NAME}-v${VERSION}-${ARCH}.dmg"
ZIP_NAME="${APP_NAME}-v${VERSION}-${ARCH}.zip"
CHECKSUMS_NAME="checksums.txt"

echo "=================================================="
echo " Packaging ${APP_NAME} v${VERSION} (${ARCH})"
echo "=================================================="

# 1. Build and sign application bundle
./build_app.sh

if [ ! -d "${BUNDLE_NAME}" ]; then
    echo "Error: ${BUNDLE_NAME} was not created!"
    exit 1
fi

mkdir -p "${RELEASE_DIR}"

# 2. Package DMG
echo "==> Creating Drag-to-Applications Disk Image (${DMG_NAME})..."
DMG_STAGE="dmg_stage_tmp"
rm -rf "${DMG_STAGE}"
mkdir -p "${DMG_STAGE}"

cp -R "${BUNDLE_NAME}" "${DMG_STAGE}/"
ln -s /Applications "${DMG_STAGE}/Applications"

# Copy AppIcon to root volume if available
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${DMG_STAGE}/.VolumeIcon.icns"
fi

rm -f "${RELEASE_DIR}/${DMG_NAME}"
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGE}" \
    -ov -format UDZO \
    "${RELEASE_DIR}/${DMG_NAME}"

rm -rf "${DMG_STAGE}"

# 3. Package ZIP archive
echo "==> Creating ZIP archive (${ZIP_NAME})..."
rm -f "${RELEASE_DIR}/${ZIP_NAME}"
ditto -c -k --keepParent "${BUNDLE_NAME}" "${RELEASE_DIR}/${ZIP_NAME}"

# 4. Generate SHA-256 Checksums
echo "==> Generating SHA-256 Checksums..."
cd "${RELEASE_DIR}"
shasum -a 256 "${DMG_NAME}" "${ZIP_NAME}" > "${CHECKSUMS_NAME}"
cd ..

echo "=================================================="
echo " Package Build Complete!"
echo " Artifacts located in: ${RELEASE_DIR}/"
ls -lh "${RELEASE_DIR}"
echo "=================================================="
