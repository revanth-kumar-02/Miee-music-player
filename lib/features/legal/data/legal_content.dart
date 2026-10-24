/// Complete and clean in-app legal content for Miee v2.0.0.
///
/// Contains comprehensive, un-truncated sections for Privacy Policy, Terms of Service,
/// Open-Source Software Notices (167 packages), and Version 2.0.0 Release Notes.

class LegalSection {
  final String title;
  final String? summary;
  final List<String> paragraphs;

  const LegalSection({
    required this.title,
    this.summary,
    required this.paragraphs,
  });
}

class DependencyNotice {
  final String name;
  final String version;
  final String license;
  final bool isDirect;
  final String author;
  final String purpose;
  final String url;

  const DependencyNotice({
    required this.name,
    required this.version,
    required this.license,
    required this.isDirect,
    this.author = '',
    this.purpose = '',
    required this.url,
  });
}

class LegalContent {
  static const String officialEmail = 'imposterz.rev02@gmail.com';
  static const String currentVersion = '2.0.0';
  static const String buildNumber = '2';
  static const String releaseDate = 'October 2026';

  // ── 1. PRIVACY POLICY SECTIONS ──────────────────────────────────────────────
  static const List<LegalSection> privacyPolicy = [
    LegalSection(
      title: '1. Introduction & Local-First Scope',
      summary: 'Miee is engineered around a local-first architecture with user privacy at its core.',
      paragraphs: [
        'Welcome to Miee. We believe your music library, listening habits, and personal data belong exclusively to you.',
        'This Privacy Policy applies to the Miee mobile application and explains transparently what data is accessed, why it is accessed, where it is stored, and your rights over your data.',
        'Miee operates on a local-first principle: offline audio playback functions completely without an internet connection or account, keeping your files isolated on your device.'
      ],
    ),
    LegalSection(
      title: '2. Information Processed by Miee',
      summary: 'Distinguishing local device data from cloud-synced account data.',
      paragraphs: [
        'A. Local Device Data: Miee queries your device storage to discover local music files (MP3, FLAC, M4A, WAV, AAC, etc.), extracting embedded ID3 tags, artist names, album titles, and album cover art.',
        'B. Cloud-Synchronized Data: When you sign in with an account, your email, user ID, custom display name, favorite artist picks, liked songs, custom playlists, listening history timestamps, and shared listening room memberships are securely synchronized with our Supabase cloud database.',
        'C. Data Sovereignty: Your private audio files and files on your device storage are NEVER transmitted, mirrored, or uploaded to any cloud server.'
      ],
    ),
    LegalSection(
      title: '3. Device Permissions & Purpose',
      summary: 'Why Miee requests storage, notification, and media permissions.',
      paragraphs: [
        '• Audio Storage Permission (READ_MEDIA_AUDIO on Android 13+ / READ_EXTERNAL_STORAGE on earlier versions): Used solely to scan and play audio files on your device storage.',
        '• Notifications Permission (POST_NOTIFICATIONS): Required to display media controls (play, pause, next, track info) in your notification shade and lock screen.',
        '• Camera & Gallery: Requested on-demand only if you choose to take or upload a custom profile picture. The selected avatar is copied directly to the application sandbox directory.'
      ],
    ),
    LegalSection(
      title: '4. Account Authentication & Guest Mode',
      summary: 'Support for anonymous guest usage and secure Supabase authentication.',
      paragraphs: [
        'You can use Miee completely without creating an account. In guest mode, all playlists, favorites, and search history remain strictly within your device local Hive database.',
        'If you choose to create an account, authentication is processed securely by Supabase Auth using industry-standard cryptographic password hashing (bcrypt). We never store or view plain-text passwords.',
        'Signing out immediately clears active session tokens from your device while preserving your local offline music files.'
      ],
    ),
    LegalSection(
      title: '5. Playlists, History & Cache Control',
      summary: 'How playlists, favorites, and temporary caches are managed.',
      paragraphs: [
        '• Playlists & Favorites: Stored locally in Hive boxes and synced to your private user rows in PostgreSQL when authenticated, protected by Row-Level Security (RLS).',
        '• Search History: Recent search queries are cached locally to provide search auto-completion. You can wipe your search history at any time from Settings → Storage & Cache.',
        '• Cache Management: In Settings → Storage & Cache, you have granular controls to view exact storage footprints, clear the album artwork cache, delete scratch cache files, or perform a total library reset.'
      ],
    ),
    LegalSection(
      title: '6. Zero Analytics & Zero Advertising',
      summary: 'No ad networks, no tracking SDKs, and no telemetry.',
      paragraphs: [
        'Miee contains ZERO advertising frameworks (no Google AdMob, Unity, AppLovin, etc.).',
        'Miee embeds ZERO third-party analytics suites (no Firebase Analytics, Google Analytics, Mixpanel, or Segment).',
        'Miee embeds ZERO third-party crash telemetry SDKs (no Sentry, Bugsnag, or Crashlytics).',
        'We do not sell, rent, monetize, or disclose your personal data to any data brokers or advertisers.'
      ],
    ),
    LegalSection(
      title: '7. External Music Services & Public APIs',
      summary: 'Third-party endpoints utilized for streaming, lyrics, and artwork.',
      paragraphs: [
        '• YouTube & Google Video Endpoints (*.googlevideo.com): When searching or playing online tracks, your device connects directly to public YouTube stream endpoints via client-side manifest deciphering. Miee operates no intermediary streaming proxy.',
        '• LRCLIB (lrclib.net): Track title and artist queries are sent via HTTP GET to retrieve synchronized and plain lyrics. No user credentials or identifiers are shared.',
        '• Deezer CDN (cdn-images.dzcdn.net): Delivers high-resolution artist discovery photography.',
        '• Google Fonts: Downloads typography font binaries (Geist, Playfair Display) at runtime.'
      ],
    ),
    LegalSection(
      title: '8. Data Retention, Rights & Account Deletion',
      summary: 'Your rights under the Indian DPDP Act 2023, GDPR, CCPA, and how to delete your account.',
      paragraphs: [
        '• Account & Data Deletion: You have the right to permanently delete your Miee account and all associated cloud records (playlists, favorites, profile, history) from Supabase. Simply email imposterz.rev02@gmail.com with subject "Delete My Account", and all corresponding database records will be permanently expunged within 30 days.',
        '• Indian DPDP Act 2023 Rights: Users in India have the right to access summaries of personal data, request correction or erasure, and nominate a representative.',
        '• European & International Rights: Users in the EEA/UK have rights of access, rectification, erasure, restriction of processing, and data portability under GDPR.',
        '• Contact: For all privacy requests, data inquiries, or concerns, email our designated privacy contact directly at imposterz.rev02@gmail.com.'
      ],
    ),
  ];

  // ── 2. TERMS OF SERVICE SECTIONS ────────────────────────────────────────────
  static const List<LegalSection> termsOfService = [
    LegalSection(
      title: '1. Acceptance of Terms',
      summary: 'Your agreement to use Miee under these terms.',
      paragraphs: [
        'By downloading, installing, accessing, or using Miee, you agree to be bound by these Terms of Service. If you do not agree to these Terms, you must discontinue using and uninstall Miee.',
        'These Terms govern your use of the Miee mobile application and any connected services provided by the maintainers.'
      ],
    ),
    LegalSection(
      title: '2. Description & Media Player Scope',
      summary: 'Miee is a media playback software utility, not a content publisher.',
      paragraphs: [
        'Miee is a software media player designed to play audio files stored on your local device and discover public audio feeds.',
        'Miee is not a music publisher, record label, audio distributor, or content host.',
        'All audio playback of local files occurs entirely on your device using user-provided files.'
      ],
    ),
    LegalSection(
      title: '3. User Responsibilities & Acceptable Use',
      summary: 'Legal use of local audio files and compliance with copyright laws.',
      paragraphs: [
        'You are solely responsible for ensuring that you hold all necessary legal rights, licenses, or permissions to store, manage, and play audio files on your device.',
        'You agree not to use Miee to infringe any copyright, trademark, or intellectual property rights of any third party.',
        'You agree not to attempt to interfere with, overload, or disrupt backend database services or third-party APIs.',
        'You agree not to use offensive, defamatory, or unlawful names when creating shared listening rooms or user profiles.'
      ],
    ),
    LegalSection(
      title: '4. Third-Party Intellectual Property & Disclaimers',
      summary: 'Miee claims no rights over third-party music, lyrics, or artwork.',
      paragraphs: [
        'Miee does not claim ownership, authorship, or copyright over any songs, sound recordings, lyrics, musical compositions, album art, or artist photos accessed or displayed through the app.',
        'All intellectual property rights in third-party content belong exclusively to their respective copyright holders, artists, record labels, and publishers.',
        'Lyrics are retrieved from LRCLIB for personal reference and educational enjoyment.',
        'If you believe any content link or feature in Miee infringes your copyright, please contact us promptly at imposterz.rev02@gmail.com for takedown review.'
      ],
    ),
    LegalSection(
      title: '5. Third-Party Service Availability',
      summary: 'No warranty on external third-party API uptime.',
      paragraphs: [
        'Miee interfaces with third-party public services including Supabase, LRCLIB, Deezer CDN, and YouTube.',
        'We do not guarantee uninterrupted availability, uptime, or future continuity of these external endpoints.',
        'Upstream changes to third-party web manifests or API availability may temporarily affect online stream or lyrics resolution.'
      ],
    ),
    LegalSection(
      title: '6. Disclaimer of Warranties & Limitation of Liability',
      summary: 'Miee is provided AS IS with limitations on damages.',
      paragraphs: [
        'MIEE IS PROVIDED ON AN "AS IS" AND "AS AVAILABLE" BASIS, WITHOUT WARRANTIES OF ANY KIND, WHETHER EXPRESS, IMPLIED, OR STATUTORY, INCLUDING IMPLIED WARRANTIES OF MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.',
        'TO THE FULLEST EXTENT PERMITTED BY LAW, THE MAINTAINERS OF MIEE SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, OR CONSEQUENTIAL DAMAGES (INCLUDING LOSS OF DATA, DEVICE DAMAGE, OR SERVICE INTERRUPTION) ARISING OUT OF YOUR USE OF THE APPLICATION.'
      ],
    ),
    LegalSection(
      title: '7. Open Source Software & Official Contact',
      summary: 'Attribution to open-source libraries and designated contact.',
      paragraphs: [
        'Miee incorporates open-source libraries licensed under MIT, Apache-2.0, BSD-3-Clause, and SIL OFL 1.1. Full notices are accessible in the Open Source Licenses tab and in docs/OPEN_SOURCE_NOTICES.md.',
        'For terms questions, copyright notices, or legal inquiries, contact: imposterz.rev02@gmail.com.'
      ],
    ),
  ];

  // ── 3. RELEASE NOTES & ABOUT MIEE ──────────────────────────────────────────
  static const List<LegalSection> releaseNotes = [
    LegalSection(
      title: 'Version Overview',
      summary: 'Miee v2.0.0 (Build 2) — Major Release',
      paragraphs: [
        'Miee v2.0.0 represents a complete architectural evolution, introducing a high-performance Supabase cloud backend, natural multi-line synchronized lyrics layout, profile avatar customization, and refined Material 3 Vanilla Cream visual design.'
      ],
    ),
    LegalSection(
      title: 'What\'s New in v2.0.0',
      summary: 'Key features included in this release.',
      paragraphs: [
        '• Multilingual Lyrics Engine: Fully expanded lyrics overlay supporting multi-line phrasing, line-height 1.45, active line auto-centering with Scrollable.ensureVisible, and opaque high-contrast backdrop.',
        '• Profile Picture Customization: Full camera capture and photo gallery selection with sandbox persistence and top navigation bar avatar display.',
        '• Cloud Library Synchronization: Supabase backend sync for liked songs, custom playlists, listening history timestamps, and realtime listening rooms.',
        '• Resilient Sync Protocol: Schema-aligned database syncing with safe null-coalescing preventing sync failure loops.',
        '• Media Controls: Background audio session, lock-screen playback controls, and notification drawer media actions powered by just_audio and audio_service.'
      ],
    ),
    LegalSection(
      title: 'Confirmed Fixes & Optimizations',
      summary: 'Issues resolved in this release cycle.',
      paragraphs: [
        '• Fixed "Sync failed. Retrying..." error by aligning database column mappings (created_at, updated_at).',
        '• Fixed lyrics line clipping for Tamil, Telugu, Hindi, and Japanese multi-line verses by removing hardcoded height capping.',
        '• Fixed profile picture bottom sheet modal presentation hierarchy using useRootNavigator: true.',
        '• Fixed sign-out redirection and session cleanup in GoRouter.',
        '• Fixed album artwork resolution for recently played online streams.'
      ],
    ),
    LegalSection(
      title: 'Application Licensing & Contact',
      summary: 'Official support and inquiries.',
      paragraphs: [
        'Miee Application source code and branding: Copyright (c) 2024-2026 Miee Maintainers. All rights reserved.',
        'Third-party libraries: Governed by their respective open-source licenses as detailed in the Licenses section.',
        'Official Support Email: imposterz.rev02@gmail.com'
      ],
    ),
  ];

  // ── 4. DEPENDENCY NOTICES (ALL 167 PACKAGES AUDITED) ────────────────────────
  static const List<DependencyNotice> dependencies = [
    DependencyNotice(name: 'app_links', version: '7.2.0', license: 'Apache-2.0', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/app_links'),
    DependencyNotice(name: 'app_links_linux', version: '1.0.3', license: 'Apache-2.0', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/app_links_linux'),
    DependencyNotice(name: 'app_links_platform_interface', version: '2.0.3', license: 'Apache-2.0', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/app_links_platform_interface'),
    DependencyNotice(name: 'app_links_web', version: '1.0.4', license: 'Apache-2.0', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/app_links_web'),
    DependencyNotice(name: 'archive', version: '4.0.9', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/archive'),
    DependencyNotice(name: 'args', version: '2.7.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/args'),
    DependencyNotice(name: 'async', version: '2.13.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/async'),
    DependencyNotice(name: 'audio_service', version: '0.18.19', license: 'MIT', isDirect: true, author: 'Ryan Heise', purpose: 'Background audio lifecycle, notifications, and lock-screen controls', url: 'https://github.com/ryanheise/audio_service'),
    DependencyNotice(name: 'audio_service_platform_interface', version: '0.1.3', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/audio_service_platform_interface'),
    DependencyNotice(name: 'audio_service_web', version: '0.1.4', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/audio_service_web'),
    DependencyNotice(name: 'audio_session', version: '0.2.4', license: 'MIT', isDirect: true, author: 'Ryan Heise', purpose: 'Audio session configuration and audio focus management', url: 'https://github.com/ryanheise/audio_session'),
    DependencyNotice(name: 'boolean_selector', version: '2.1.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/boolean_selector'),
    DependencyNotice(name: 'characters', version: '1.4.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/characters'),
    DependencyNotice(name: 'checked_yaml', version: '2.0.4', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/checked_yaml'),
    DependencyNotice(name: 'cli_util', version: '0.4.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/cli_util'),
    DependencyNotice(name: 'clock', version: '1.1.2', license: 'Apache-2.0', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/clock'),
    DependencyNotice(name: 'code_assets', version: '1.2.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/code_assets'),
    DependencyNotice(name: 'collection', version: '1.19.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/collection'),
    DependencyNotice(name: 'connectivity_plus', version: '7.2.0', license: 'BSD-3-Clause', isDirect: true, author: 'Flutter Community', purpose: 'Network reachability and connectivity status detection', url: 'https://github.com/fluttercommunity/plus_plugins'),
    DependencyNotice(name: 'connectivity_plus_platform_interface', version: '2.1.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/connectivity_plus_platform_interface'),
    DependencyNotice(name: 'convert', version: '3.1.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/convert'),
    DependencyNotice(name: 'cross_file', version: '0.3.5+4', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/cross_file'),
    DependencyNotice(name: 'crypto', version: '3.0.7', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/crypto'),
    DependencyNotice(name: 'csslib', version: '1.0.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/csslib'),
    DependencyNotice(name: 'dart_jsonwebtoken', version: '3.4.1', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/dart_jsonwebtoken'),
    DependencyNotice(name: 'dbus', version: '0.7.14', license: 'MPL-2.0', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/dbus'),
    DependencyNotice(name: 'dio', version: '5.10.0', license: 'MIT', isDirect: true, author: 'FlutterChina / CFUG', purpose: 'HTTP client with interceptors for lyrics and metadata APIs', url: 'https://github.com/cfug/dio'),
    DependencyNotice(name: 'dio_web_adapter', version: '2.2.0', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/dio_web_adapter'),
    DependencyNotice(name: 'fake_async', version: '1.3.3', license: 'Apache-2.0', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/fake_async'),
    DependencyNotice(name: 'ffi', version: '2.2.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/ffi'),
    DependencyNotice(name: 'ffi_leak_tracker', version: '0.1.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/ffi_leak_tracker'),
    DependencyNotice(name: 'file', version: '7.0.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/file'),
    DependencyNotice(name: 'file_selector_linux', version: '0.9.4', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/file_selector_linux'),
    DependencyNotice(name: 'file_selector_macos', version: '0.9.5', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/file_selector_macos'),
    DependencyNotice(name: 'file_selector_platform_interface', version: '2.7.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/file_selector_platform_interface'),
    DependencyNotice(name: 'file_selector_windows', version: '0.9.3+5', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/file_selector_windows'),
    DependencyNotice(name: 'fixnum', version: '1.1.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/fixnum'),
    DependencyNotice(name: 'flutter', version: '0.0.0', license: 'BSD-3-Clause', isDirect: true, author: 'Google LLC', purpose: 'Core UI framework and rendering engine', url: 'https://github.com/flutter/flutter'),
    DependencyNotice(name: 'flutter_cache_manager', version: '3.4.1', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/flutter_cache_manager'),
    DependencyNotice(name: 'flutter_launcher_icons', version: '0.14.4', license: 'MIT', isDirect: true, author: 'Mark O\'Sullivan', purpose: 'Adaptive icon generator configuration', url: 'https://github.com/fluttercommunity/flutter_launcher_icons'),
    DependencyNotice(name: 'flutter_lints', version: '6.0.0', license: 'BSD-3-Clause', isDirect: true, author: 'Google LLC', purpose: 'Recommended static analysis rules for Dart/Flutter', url: 'https://github.com/flutter/packages/tree/main/packages/flutter_lints'),
    DependencyNotice(name: 'flutter_plugin_android_lifecycle', version: '2.0.35', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/flutter_plugin_android_lifecycle'),
    DependencyNotice(name: 'flutter_riverpod', version: '2.6.1', license: 'MIT', isDirect: true, author: 'Remi Rousselet', purpose: 'Reactive state management and dependency injection', url: 'https://github.com/rrousselGit/riverpod'),
    DependencyNotice(name: 'flutter_test', version: '0.0.0', license: 'BSD-3-Clause', isDirect: false, author: 'Google LLC', purpose: '', url: 'https://github.com/flutter/flutter'),
    DependencyNotice(name: 'flutter_web_plugins', version: '0.0.0', license: 'BSD-3-Clause', isDirect: false, author: 'Google LLC', purpose: '', url: 'https://github.com/flutter/flutter'),
    DependencyNotice(name: 'freezed_annotation', version: '3.1.0', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/freezed_annotation'),
    DependencyNotice(name: 'functions_client', version: '2.6.4', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/functions_client'),
    DependencyNotice(name: 'go_router', version: '17.3.0', license: 'BSD-3-Clause', isDirect: true, author: 'Flutter Team / Google LLC', purpose: 'Declarative routing and deep linking', url: 'https://github.com/flutter/packages/tree/main/packages/go_router'),
    DependencyNotice(name: 'google_fonts', version: '8.1.0', license: 'BSD-3-Clause', isDirect: true, author: 'Flutter Team / Google LLC', purpose: 'Runtime font loading for Geist & Playfair Display', url: 'https://github.com/material-foundation/google-fonts-flutter'),
    DependencyNotice(name: 'gotrue', version: '2.26.0', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/gotrue'),
    DependencyNotice(name: 'gtk', version: '2.2.0', license: 'MPL-2.0', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/gtk'),
    DependencyNotice(name: 'hive', version: '2.2.3', license: 'Apache-2.0', isDirect: true, author: 'Simon Leier', purpose: 'Lightweight and ultra-fast key-value database', url: 'https://github.com/hivedb/hive'),
    DependencyNotice(name: 'hive_flutter', version: '1.1.0', license: 'Apache-2.0', isDirect: true, author: 'Simon Leier', purpose: 'Flutter extensions for Hive database initialization', url: 'https://github.com/hivedb/hive'),
    DependencyNotice(name: 'hooks', version: '2.0.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/hooks'),
    DependencyNotice(name: 'html', version: '0.15.7', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/html'),
    DependencyNotice(name: 'http', version: '1.6.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/http'),
    DependencyNotice(name: 'http_parser', version: '4.1.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/http_parser'),
    DependencyNotice(name: 'id3', version: '1.0.2', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/id3'),
    DependencyNotice(name: 'image', version: '4.8.0', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/image'),
    DependencyNotice(name: 'image_picker', version: '1.2.3', license: 'Apache-2.0', isDirect: true, author: 'Flutter Team / Google LLC', purpose: 'Profile picture capture and photo gallery picker', url: 'https://github.com/flutter/packages/tree/main/packages/image_picker'),
    DependencyNotice(name: 'image_picker_android', version: '0.8.13+19', license: 'Apache-2.0', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/image_picker_android'),
    DependencyNotice(name: 'image_picker_for_web', version: '3.1.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/image_picker_for_web'),
    DependencyNotice(name: 'image_picker_ios', version: '0.8.13+6', license: 'Apache-2.0', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/image_picker_ios'),
    DependencyNotice(name: 'image_picker_linux', version: '0.2.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/image_picker_linux'),
    DependencyNotice(name: 'image_picker_macos', version: '0.2.2+1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/image_picker_macos'),
    DependencyNotice(name: 'image_picker_platform_interface', version: '2.11.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/image_picker_platform_interface'),
    DependencyNotice(name: 'image_picker_windows', version: '0.2.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/image_picker_windows'),
    DependencyNotice(name: 'jni', version: '1.0.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/jni'),
    DependencyNotice(name: 'jni_flutter', version: '1.0.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/jni_flutter'),
    DependencyNotice(name: 'js', version: '0.7.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/js'),
    DependencyNotice(name: 'json_annotation', version: '4.12.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/json_annotation'),
    DependencyNotice(name: 'just_audio', version: '0.10.6', license: 'Apache-2.0', isDirect: true, author: 'Ryan Heise', purpose: 'Feature-rich audio player for local and stream playback', url: 'https://github.com/ryanheise/just_audio'),
    DependencyNotice(name: 'just_audio_platform_interface', version: '4.6.0', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/just_audio_platform_interface'),
    DependencyNotice(name: 'just_audio_web', version: '0.4.16', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/just_audio_web'),
    DependencyNotice(name: 'jwt_decode', version: '0.3.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/jwt_decode'),
    DependencyNotice(name: 'leak_tracker', version: '11.0.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/leak_tracker'),
    DependencyNotice(name: 'leak_tracker_flutter_testing', version: '3.0.10', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/leak_tracker_flutter_testing'),
    DependencyNotice(name: 'leak_tracker_testing', version: '3.0.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/leak_tracker_testing'),
    DependencyNotice(name: 'lints', version: '6.1.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/lints'),
    DependencyNotice(name: 'logging', version: '1.3.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/logging'),
    DependencyNotice(name: 'matcher', version: '0.12.20', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/matcher'),
    DependencyNotice(name: 'material_color_utilities', version: '0.13.0', license: 'Apache-2.0', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/material_color_utilities'),
    DependencyNotice(name: 'meta', version: '1.19.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/meta'),
    DependencyNotice(name: 'mime', version: '2.0.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/mime'),
    DependencyNotice(name: 'nm', version: '0.5.0', license: 'MPL-2.0', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/nm'),
    DependencyNotice(name: 'objective_c', version: '9.4.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/objective_c'),
    DependencyNotice(name: 'on_audio_query', version: '2.9.0', license: 'BSD-3-Clause', isDirect: true, author: 'Lucio Maciel (Lucas Josino)', purpose: 'Local storage audio file querying and ID3 tag extraction', url: 'https://github.com/Lucio-Maciel/on_audio_query'),
    DependencyNotice(name: 'on_audio_query_android', version: '1.1.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/on_audio_query_android'),
    DependencyNotice(name: 'on_audio_query_ios', version: '1.1.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/on_audio_query_ios'),
    DependencyNotice(name: 'on_audio_query_platform_interface', version: '1.7.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/on_audio_query_platform_interface'),
    DependencyNotice(name: 'on_audio_query_web', version: '1.6.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/on_audio_query_web'),
    DependencyNotice(name: 'package_config', version: '2.2.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/package_config'),
    DependencyNotice(name: 'passkeys_platform_interface', version: '2.8.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/passkeys_platform_interface'),
    DependencyNotice(name: 'path', version: '1.9.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/path'),
    DependencyNotice(name: 'path_provider', version: '2.1.6', license: 'BSD-3-Clause', isDirect: true, author: 'Flutter Team / Google LLC', purpose: 'Filesystem directory resolution for cache and documents', url: 'https://github.com/flutter/packages/tree/main/packages/path_provider'),
    DependencyNotice(name: 'path_provider_android', version: '2.3.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/path_provider_android'),
    DependencyNotice(name: 'path_provider_foundation', version: '2.6.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/path_provider_foundation'),
    DependencyNotice(name: 'path_provider_linux', version: '2.2.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/path_provider_linux'),
    DependencyNotice(name: 'path_provider_platform_interface', version: '2.1.3', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/path_provider_platform_interface'),
    DependencyNotice(name: 'path_provider_windows', version: '2.3.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/path_provider_windows'),
    DependencyNotice(name: 'permission_handler', version: '12.0.3', license: 'MIT', isDirect: true, author: 'Baseflow', purpose: 'Android runtime permission management (storage & notifications)', url: 'https://github.com/Baseflow/flutter-permission-handler'),
    DependencyNotice(name: 'permission_handler_android', version: '13.0.1', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/permission_handler_android'),
    DependencyNotice(name: 'permission_handler_apple', version: '9.4.10', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/permission_handler_apple'),
    DependencyNotice(name: 'permission_handler_html', version: '0.1.3+5', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/permission_handler_html'),
    DependencyNotice(name: 'permission_handler_platform_interface', version: '4.3.0', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/permission_handler_platform_interface'),
    DependencyNotice(name: 'permission_handler_windows', version: '0.2.1', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/permission_handler_windows'),
    DependencyNotice(name: 'petitparser', version: '7.0.2', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/petitparser'),
    DependencyNotice(name: 'platform', version: '3.1.6', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/platform'),
    DependencyNotice(name: 'plugin_platform_interface', version: '2.1.8', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/plugin_platform_interface'),
    DependencyNotice(name: 'pointycastle', version: '4.0.0', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/pointycastle'),
    DependencyNotice(name: 'posix', version: '6.5.0', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/posix'),
    DependencyNotice(name: 'postgrest', version: '2.8.0', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/postgrest'),
    DependencyNotice(name: 'pub_semver', version: '2.2.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/pub_semver'),
    DependencyNotice(name: 'realtime_client', version: '2.11.0', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/realtime_client'),
    DependencyNotice(name: 'record_use', version: '0.6.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/record_use'),
    DependencyNotice(name: 'retry', version: '3.1.2', license: 'Apache-2.0', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/retry'),
    DependencyNotice(name: 'riverpod', version: '2.6.1', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/riverpod'),
    DependencyNotice(name: 'rxdart', version: '0.28.0', license: 'Apache-2.0', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/rxdart'),
    DependencyNotice(name: 'share_plus', version: '13.2.0', license: 'BSD-3-Clause', isDirect: true, author: 'Flutter Community', purpose: 'Native platform share dialog integration', url: 'https://github.com/fluttercommunity/plus_plugins'),
    DependencyNotice(name: 'share_plus_platform_interface', version: '7.1.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/share_plus_platform_interface'),
    DependencyNotice(name: 'shared_preferences', version: '2.5.5', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/shared_preferences'),
    DependencyNotice(name: 'shared_preferences_android', version: '2.4.26', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/shared_preferences_android'),
    DependencyNotice(name: 'shared_preferences_foundation', version: '2.5.6', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/shared_preferences_foundation'),
    DependencyNotice(name: 'shared_preferences_linux', version: '2.4.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/shared_preferences_linux'),
    DependencyNotice(name: 'shared_preferences_platform_interface', version: '2.4.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/shared_preferences_platform_interface'),
    DependencyNotice(name: 'shared_preferences_web', version: '2.4.3', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/shared_preferences_web'),
    DependencyNotice(name: 'shared_preferences_windows', version: '2.4.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/shared_preferences_windows'),
    DependencyNotice(name: 'simple_sparse_list', version: '0.1.4', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/simple_sparse_list'),
    DependencyNotice(name: 'sky_engine', version: '0.0.0', license: 'BSD-3-Clause', isDirect: false, author: 'Google LLC', purpose: '', url: 'https://github.com/flutter/flutter'),
    DependencyNotice(name: 'source_span', version: '1.10.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/source_span'),
    DependencyNotice(name: 'sqflite', version: '2.4.3', license: 'BSD-2-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/sqflite'),
    DependencyNotice(name: 'sqflite_android', version: '2.4.3', license: 'BSD-2-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/sqflite_android'),
    DependencyNotice(name: 'sqflite_common', version: '2.5.11', license: 'BSD-2-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/sqflite_common'),
    DependencyNotice(name: 'sqflite_darwin', version: '2.4.3+1', license: 'BSD-2-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/sqflite_darwin'),
    DependencyNotice(name: 'sqflite_platform_interface', version: '2.4.1', license: 'BSD-2-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/sqflite_platform_interface'),
    DependencyNotice(name: 'stack_trace', version: '1.12.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/stack_trace'),
    DependencyNotice(name: 'state_notifier', version: '1.0.0', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/state_notifier'),
    DependencyNotice(name: 'storage_client', version: '2.6.0', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/storage_client'),
    DependencyNotice(name: 'stream_channel', version: '2.1.4', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/stream_channel'),
    DependencyNotice(name: 'string_scanner', version: '1.4.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/string_scanner'),
    DependencyNotice(name: 'supabase', version: '2.14.0', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/supabase'),
    DependencyNotice(name: 'supabase_flutter', version: '2.16.0', license: 'MIT', isDirect: true, author: 'Supabase Inc.', purpose: 'Supabase client for Auth, Database, and Realtime', url: 'https://github.com/supabase/supabase-flutter'),
    DependencyNotice(name: 'synchronized', version: '3.4.1', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/synchronized'),
    DependencyNotice(name: 'term_glyph', version: '1.2.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/term_glyph'),
    DependencyNotice(name: 'test_api', version: '0.7.12', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/test_api'),
    DependencyNotice(name: 'typed_data', version: '1.4.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/typed_data'),
    DependencyNotice(name: 'unicode', version: '1.1.9', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/unicode'),
    DependencyNotice(name: 'url_launcher', version: '6.3.2', license: 'BSD-3-Clause', isDirect: true, author: 'Flutter Team / Google LLC', purpose: 'System URL and mailto handler', url: 'https://github.com/flutter/packages/tree/main/packages/url_launcher'),
    DependencyNotice(name: 'url_launcher_android', version: '6.3.32', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/url_launcher_android'),
    DependencyNotice(name: 'url_launcher_ios', version: '6.4.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/url_launcher_ios'),
    DependencyNotice(name: 'url_launcher_linux', version: '3.2.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/url_launcher_linux'),
    DependencyNotice(name: 'url_launcher_macos', version: '3.2.5', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/url_launcher_macos'),
    DependencyNotice(name: 'url_launcher_platform_interface', version: '2.3.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/url_launcher_platform_interface'),
    DependencyNotice(name: 'url_launcher_web', version: '2.4.3', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/url_launcher_web'),
    DependencyNotice(name: 'url_launcher_windows', version: '3.1.5', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/url_launcher_windows'),
    DependencyNotice(name: 'uuid', version: '4.5.3', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/uuid'),
    DependencyNotice(name: 'vector_math', version: '2.4.2', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/vector_math'),
    DependencyNotice(name: 'vm_service', version: '15.2.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/vm_service'),
    DependencyNotice(name: 'web', version: '1.1.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/web'),
    DependencyNotice(name: 'web_socket', version: '1.0.1', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/web_socket'),
    DependencyNotice(name: 'web_socket_channel', version: '3.0.3', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/web_socket_channel'),
    DependencyNotice(name: 'win32', version: '6.3.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/win32'),
    DependencyNotice(name: 'xdg_directories', version: '1.1.0', license: 'BSD-3-Clause', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/xdg_directories'),
    DependencyNotice(name: 'xml', version: '6.6.1', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/xml'),
    DependencyNotice(name: 'yaml', version: '3.1.3', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/yaml'),
    DependencyNotice(name: 'yet_another_json_isolate', version: '2.1.1', license: 'MIT', isDirect: false, author: '', purpose: '', url: 'https://pub.dev/packages/yet_another_json_isolate'),
    DependencyNotice(name: 'youtube_explode_dart', version: '3.1.0', license: 'BSD-3-Clause', isDirect: true, author: 'Hexer10 (K vast)', purpose: 'Client-side YouTube audio stream manifest deciphering', url: 'https://github.com/Hexer10/youtube_explode_dart'),
  ];
}
