# Miee Diagnostics & Stream Investigation Tools

This directory contains standalone diagnostic scripts developed during the YouTube playback, stream resolution, and audio headers investigation.

## Purpose

These scripts are kept to diagnose streaming behavior against live YouTube servers, inspecting manifests, HTTP headers, range requests, and audio codecs without coupling to unit testing pipelines.

## Scripts Catalog

1. **`stream_diag_test.dart`**:
   - Diagnoses YouTube stream resolution, container types, audio bitrates, and HTTP status with Android client credentials.
   - Run: `flutter test diagnostics/stream_diag_test.dart`

2. **`stream_diag_test2.dart`**:
   - Diagnoses header combinations (User-Agent, Referer, Origin) against specific video IDs.
   - Run: `flutter test diagnostics/stream_diag_test2.dart`

3. **`stream_range_test.dart`**:
   - Tests streaming behavior past the initial 1MB allowance using VISIONOS vs TVHTML5 clients.
   - Run: `flutter test diagnostics/stream_range_test.dart`

4. **`visionos_headers_test.dart`**:
   - Tests 2MB chunk downloads using ExoPlayer User-Agent vs default headers.
   - Run: `flutter test diagnostics/visionos_headers_test.dart`

5. **`visionos_streams_test.dart`**:
   - Detailed format breakdown for VISIONOS audio streams.
   - Run: `flutter test diagnostics/visionos_streams_test.dart`

6. **`device_playback_test.dart`**:
   - Real device / emulator test for `just_audio` AudioPlayer setting audio source with custom headers.
   - Run on an attached device or emulator with `flutter run diagnostics/device_playback_test.dart` or on device test runner.

7. **`lana_test.dart`**:
   - Rapid validation of video search and stream resolution for Lana Del Rey tracks using VISIONOS client.
   - Run: `flutter test diagnostics/lana_test.dart`
