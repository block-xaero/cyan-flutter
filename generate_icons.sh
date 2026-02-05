#!/bin/bash
# generate_icons.sh
# Generates app icons for all platforms from a 1024x1024 source image
# Requires: ImageMagick (brew install imagemagick)

set -e

SOURCE_IMAGE="${1:-assets/icons/app_icon.png}"
PROJECT_DIR="$(pwd)"

if [ ! -f "$SOURCE_IMAGE" ]; then
    echo "❌ Source image not found: $SOURCE_IMAGE"
    echo "Usage: ./generate_icons.sh [path/to/1024x1024/icon.png]"
    exit 1
fi

echo "🎨 Generating icons from: $SOURCE_IMAGE"

# ============================================================================
# macOS Icons
# ============================================================================
echo "📱 Generating macOS icons..."
MACOS_DIR="$PROJECT_DIR/macos/Runner/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$MACOS_DIR"

convert "$SOURCE_IMAGE" -resize 16x16 "$MACOS_DIR/app_icon_16.png"
convert "$SOURCE_IMAGE" -resize 32x32 "$MACOS_DIR/app_icon_32.png"
convert "$SOURCE_IMAGE" -resize 64x64 "$MACOS_DIR/app_icon_64.png"
convert "$SOURCE_IMAGE" -resize 128x128 "$MACOS_DIR/app_icon_128.png"
convert "$SOURCE_IMAGE" -resize 256x256 "$MACOS_DIR/app_icon_256.png"
convert "$SOURCE_IMAGE" -resize 512x512 "$MACOS_DIR/app_icon_512.png"
convert "$SOURCE_IMAGE" -resize 1024x1024 "$MACOS_DIR/app_icon_1024.png"

# Create Contents.json for macOS
cat > "$MACOS_DIR/Contents.json" << 'EOF'
{
  "images" : [
    {
      "size" : "16x16",
      "idiom" : "mac",
      "filename" : "app_icon_16.png",
      "scale" : "1x"
    },
    {
      "size" : "16x16",
      "idiom" : "mac",
      "filename" : "app_icon_32.png",
      "scale" : "2x"
    },
    {
      "size" : "32x32",
      "idiom" : "mac",
      "filename" : "app_icon_32.png",
      "scale" : "1x"
    },
    {
      "size" : "32x32",
      "idiom" : "mac",
      "filename" : "app_icon_64.png",
      "scale" : "2x"
    },
    {
      "size" : "128x128",
      "idiom" : "mac",
      "filename" : "app_icon_128.png",
      "scale" : "1x"
    },
    {
      "size" : "128x128",
      "idiom" : "mac",
      "filename" : "app_icon_256.png",
      "scale" : "2x"
    },
    {
      "size" : "256x256",
      "idiom" : "mac",
      "filename" : "app_icon_256.png",
      "scale" : "1x"
    },
    {
      "size" : "256x256",
      "idiom" : "mac",
      "filename" : "app_icon_512.png",
      "scale" : "2x"
    },
    {
      "size" : "512x512",
      "idiom" : "mac",
      "filename" : "app_icon_512.png",
      "scale" : "1x"
    },
    {
      "size" : "512x512",
      "idiom" : "mac",
      "filename" : "app_icon_1024.png",
      "scale" : "2x"
    }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
EOF

echo "✅ macOS icons generated"

# ============================================================================
# iOS Icons
# ============================================================================
echo "📱 Generating iOS icons..."
IOS_DIR="$PROJECT_DIR/ios/Runner/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$IOS_DIR"

convert "$SOURCE_IMAGE" -resize 20x20 "$IOS_DIR/Icon-App-20x20@1x.png"
convert "$SOURCE_IMAGE" -resize 40x40 "$IOS_DIR/Icon-App-20x20@2x.png"
convert "$SOURCE_IMAGE" -resize 60x60 "$IOS_DIR/Icon-App-20x20@3x.png"
convert "$SOURCE_IMAGE" -resize 29x29 "$IOS_DIR/Icon-App-29x29@1x.png"
convert "$SOURCE_IMAGE" -resize 58x58 "$IOS_DIR/Icon-App-29x29@2x.png"
convert "$SOURCE_IMAGE" -resize 87x87 "$IOS_DIR/Icon-App-29x29@3x.png"
convert "$SOURCE_IMAGE" -resize 40x40 "$IOS_DIR/Icon-App-40x40@1x.png"
convert "$SOURCE_IMAGE" -resize 80x80 "$IOS_DIR/Icon-App-40x40@2x.png"
convert "$SOURCE_IMAGE" -resize 120x120 "$IOS_DIR/Icon-App-40x40@3x.png"
convert "$SOURCE_IMAGE" -resize 120x120 "$IOS_DIR/Icon-App-60x60@2x.png"
convert "$SOURCE_IMAGE" -resize 180x180 "$IOS_DIR/Icon-App-60x60@3x.png"
convert "$SOURCE_IMAGE" -resize 76x76 "$IOS_DIR/Icon-App-76x76@1x.png"
convert "$SOURCE_IMAGE" -resize 152x152 "$IOS_DIR/Icon-App-76x76@2x.png"
convert "$SOURCE_IMAGE" -resize 167x167 "$IOS_DIR/Icon-App-83.5x83.5@2x.png"
convert "$SOURCE_IMAGE" -resize 1024x1024 "$IOS_DIR/Icon-App-1024x1024@1x.png"

# iOS Contents.json is usually already present from Flutter template

echo "✅ iOS icons generated"

# ============================================================================
# Android Icons
# ============================================================================
echo "🤖 Generating Android icons..."
ANDROID_RES="$PROJECT_DIR/android/app/src/main/res"

mkdir -p "$ANDROID_RES/mipmap-mdpi"
mkdir -p "$ANDROID_RES/mipmap-hdpi"
mkdir -p "$ANDROID_RES/mipmap-xhdpi"
mkdir -p "$ANDROID_RES/mipmap-xxhdpi"
mkdir -p "$ANDROID_RES/mipmap-xxxhdpi"

convert "$SOURCE_IMAGE" -resize 48x48 "$ANDROID_RES/mipmap-mdpi/ic_launcher.png"
convert "$SOURCE_IMAGE" -resize 72x72 "$ANDROID_RES/mipmap-hdpi/ic_launcher.png"
convert "$SOURCE_IMAGE" -resize 96x96 "$ANDROID_RES/mipmap-xhdpi/ic_launcher.png"
convert "$SOURCE_IMAGE" -resize 144x144 "$ANDROID_RES/mipmap-xxhdpi/ic_launcher.png"
convert "$SOURCE_IMAGE" -resize 192x192 "$ANDROID_RES/mipmap-xxxhdpi/ic_launcher.png"

echo "✅ Android icons generated"

# ============================================================================
# Windows Icon
# ============================================================================
echo "🪟 Generating Windows icon..."
WINDOWS_DIR="$PROJECT_DIR/windows/runner/resources"
mkdir -p "$WINDOWS_DIR"

# Create multi-size ICO file
convert "$SOURCE_IMAGE" -resize 256x256 -define icon:auto-resize=256,128,64,48,32,16 "$WINDOWS_DIR/app_icon.ico"

echo "✅ Windows icon generated"

# ============================================================================
# Linux Icon
# ============================================================================
echo "🐧 Generating Linux icon..."
LINUX_DIR="$PROJECT_DIR/linux"

convert "$SOURCE_IMAGE" -resize 256x256 "$LINUX_DIR/app_icon.png"

echo "✅ Linux icon generated"

# ============================================================================
# Web Icons
# ============================================================================
echo "🌐 Generating Web icons..."
WEB_DIR="$PROJECT_DIR/web"
mkdir -p "$WEB_DIR/icons"

convert "$SOURCE_IMAGE" -resize 192x192 "$WEB_DIR/icons/Icon-192.png"
convert "$SOURCE_IMAGE" -resize 512x512 "$WEB_DIR/icons/Icon-512.png"
convert "$SOURCE_IMAGE" -resize 16x16 "$WEB_DIR/favicon.png"

echo "✅ Web icons generated"

# ============================================================================
# Assets folder (for Flutter)
# ============================================================================
echo "📁 Copying to assets..."
mkdir -p "$PROJECT_DIR/assets/icons"
cp "$SOURCE_IMAGE" "$PROJECT_DIR/assets/icons/app_icon.png"
cp "$SOURCE_IMAGE" "$PROJECT_DIR/assets/icons/splash_logo.png"

echo "✅ Assets copied"

echo ""
echo "🎉 All icons generated successfully!"
echo ""
echo "Next steps:"
echo "1. Run 'flutter clean && flutter pub get'"
echo "2. Run 'flutter run -d macos' to test"
