# leo_find_it

A new Flutter project.

## Getting Started

This project is a Flutter app with native Android BLE scanning that detects:

Apple AirTags / Apple devices

Tile trackers

Samsung SmartTags

Architecture: 

Flutter UI (Dart)
   ↓ MethodChannel
Android MainActivity (Kotlin)
   ↓
BLE Scanners (Kotlin)
   ↓
DetectedTracker objects
   ↓
Back to Flutter UI

Required Tools:

Android Studio, Includes:
Android SDK (After downloading studio) (Android studio should promp you to download SDKs

SDK tools can be found in the top left menu and clicking over to TOOLS 

In TOOLS you will see SDK Manager in there you can download the necessary tools like SDK build tools 

Android SDK Platform Tools

Android Emulator (If not using a android phone for testing but its highly reccommended to
use a test phone)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
