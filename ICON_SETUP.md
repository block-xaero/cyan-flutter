# Cyan App Icon & Splash Screen Setup

## Quick Setup

### 1. Add dependencies to pubspec.yaml

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.13.1
  flutter_native_splash: ^2.3.10

flutter_launcher_icons:
  android: true
  ios: true
  macos: true
  windows: true
  linux: true
  image_path: "assets/icons/app_icon.png"
  adaptive_icon_background: "#0A1628"
  adaptive_icon_foreground: "assets/icons/app_icon.png"
  web:
    generate: true
    image_path: "assets/icons/app_icon.png"

flutter_native_splash:
  color: "#0A1628"
  image: "assets/icons/splash_logo.png"
  android_12:
    color: "#0A1628"
    icon_background_color: "#0A1628"
    image: "assets/icons/splash_logo.png"
```

### 2. Create assets directory structure

```bash
mkdir -p assets/icons
# Copy your cyan-wordmark-v4-thin-1024.png to assets/icons/app_icon.png
cp ~/Downloads/cyan-wordmark-v4-thin-1024.png assets/icons/app_icon.png
cp ~/Downloads/cyan-wordmark-v4-thin-1024.png assets/icons/splash_logo.png
```

### 3. Update pubspec.yaml assets section

```yaml
flutter:
  assets:
    - assets/icons/
```

### 4. Generate icons

```bash
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

---

## Manual Icon Setup (if needed)

### macOS

Place icons in `macos/Runner/Assets.xcassets/AppIcon.appiconset/`:
- app_icon_16.png (16x16)
- app_icon_32.png (32x32)
- app_icon_64.png (64x64)
- app_icon_128.png (128x128)
- app_icon_256.png (256x256)
- app_icon_512.png (512x512)
- app_icon_1024.png (1024x1024)

### iOS

Place icons in `ios/Runner/Assets.xcassets/AppIcon.appiconset/`:
- Icon-App-20x20@1x.png
- Icon-App-20x20@2x.png
- Icon-App-20x20@3x.png
- Icon-App-29x29@1x.png
- Icon-App-29x29@2x.png
- Icon-App-29x29@3x.png
- Icon-App-40x40@1x.png
- Icon-App-40x40@2x.png
- Icon-App-40x40@3x.png
- Icon-App-60x60@2x.png
- Icon-App-60x60@3x.png
- Icon-App-76x76@1x.png
- Icon-App-76x76@2x.png
- Icon-App-83.5x83.5@2x.png
- Icon-App-1024x1024@1x.png

### Android

Place icons in `android/app/src/main/res/`:
- mipmap-mdpi/ic_launcher.png (48x48)
- mipmap-hdpi/ic_launcher.png (72x72)
- mipmap-xhdpi/ic_launcher.png (96x96)
- mipmap-xxhdpi/ic_launcher.png (144x144)
- mipmap-xxxhdpi/ic_launcher.png (192x192)

### Windows

Place icon in `windows/runner/resources/app_icon.ico`

### Linux

Place icon in `linux/app_icon.png`

---

## Using the Animated Splash Screen

In your main.dart, wrap your app with SplashWrapper:

```dart
import 'package:cyan_flutter/screens/splash_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cyan',
      theme: ThemeData.dark(),
      home: SplashWrapper(
        child: MainScreen(), // Your main app screen
      ),
    );
  }
}
```

Or for ProviderScope:

```dart
void main() {
  runApp(
    ProviderScope(
      child: SplashWrapper(
        child: const CyanApp(),
      ),
    ),
  );
}
```
