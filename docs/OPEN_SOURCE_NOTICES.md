# Miee v2.0.0 — Open-Source Software Notices & Licensing

**Application:** Miee
**Version:** `2.0.0` (Build `2`)
**Official Contact & Licensing Inquiries:** `imposterz.rev02@gmail.com`

---

## 1. Application Licensing & Intellectual Property Notice

### Miee Application Codebase
Unless otherwise explicitly indicated in a root `LICENSE` file committed by the repository maintainer, all rights to the proprietary architecture, visual interface design, custom iconography, brand assets, and original source code of the **Miee** application are reserved by the application author/maintainer:

> **Copyright (c) 2024-2026 Miee Project Maintainers. All rights reserved.**  
> Inquiries regarding commercial usage, redistribution, or source permissions should be directed to `imposterz.rev02@gmail.com`.

### Third-Party Software
Miee incorporates and links with open-source software libraries, frameworks, native Android SDKs, and digital typography assets. These third-party components are made available under permissive open-source licenses (primarily MIT, Apache-2.0, and BSD). Nothing in this application's terms or branding restricts, modifies, or overrides any rights granted to users under the respective third-party licenses.

This document contains the complete inventory of third-party software included in or utilized by Miee v2.0.0, together with required attributions, copyright notices, and license terms.

---

## 2. Direct Dependencies Inventory

The following table details all direct runtime and build dependencies declared in `pubspec.yaml`, their exact resolved release versions, primary authors/organizations, license types, and purposes:

| Component | Version | License | Copyright Holder / Author | Purpose & Scope | Upstream URL |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **audio_service** | `0.18.19` | MIT | Ryan Heise | Background audio lifecycle, notifications, and lock-screen controls | [audio_service](https://github.com/ryanheise/audio_service) |
| **audio_session** | `0.2.4` | MIT | Ryan Heise | Audio session configuration and audio focus management | [audio_session](https://github.com/ryanheise/audio_session) |
| **connectivity_plus** | `7.2.0` | BSD-3-Clause | Flutter Community | Network reachability and connectivity status detection | [connectivity_plus](https://github.com/fluttercommunity/plus_plugins) |
| **dio** | `5.10.0` | MIT | FlutterChina / CFUG | HTTP client with interceptors for lyrics and metadata APIs | [dio](https://github.com/cfug/dio) |
| **flutter** | `0.0.0` | BSD-3-Clause | Google LLC | Core UI framework and rendering engine | [flutter](https://github.com/flutter/flutter) |
| **flutter_launcher_icons** | `0.14.4` | MIT | Mark O'Sullivan | Adaptive icon generator configuration | [flutter_launcher_icons](https://github.com/fluttercommunity/flutter_launcher_icons) |
| **flutter_lints** | `6.0.0` | BSD-3-Clause | Google LLC | Recommended static analysis rules for Dart/Flutter | [flutter_lints](https://github.com/flutter/packages/tree/main/packages/flutter_lints) |
| **flutter_riverpod** | `2.6.1` | MIT | Remi Rousselet | Reactive state management and dependency injection | [flutter_riverpod](https://github.com/rrousselGit/riverpod) |
| **go_router** | `17.3.0` | BSD-3-Clause | Flutter Team / Google LLC | Declarative routing and deep linking | [go_router](https://github.com/flutter/packages/tree/main/packages/go_router) |
| **google_fonts** | `8.1.0` | Apache-2.0 | Flutter Team / Google LLC | Runtime font loading for Geist & Playfair Display | [google_fonts](https://github.com/material-foundation/google-fonts-flutter) |
| **hive** | `2.2.3` | Apache-2.0 | Simon Leier | Lightweight and ultra-fast key-value database | [hive](https://github.com/hivedb/hive) |
| **hive_flutter** | `1.1.0` | Apache-2.0 | Simon Leier | Flutter extensions for Hive database initialization | [hive_flutter](https://github.com/hivedb/hive) |
| **image_picker** | `1.2.3` | BSD-3-Clause | Flutter Team / Google LLC | Profile picture capture and photo gallery picker | [image_picker](https://github.com/flutter/packages/tree/main/packages/image_picker) |
| **just_audio** | `0.10.6` | Apache-2.0 | Ryan Heise | Feature-rich audio player for local and stream playback | [just_audio](https://github.com/ryanheise/just_audio) |
| **on_audio_query** | `2.9.0` | Apache-2.0 | Lucio Maciel (Lucas Josino) | Local storage audio file querying and ID3 tag extraction | [on_audio_query](https://github.com/Lucio-Maciel/on_audio_query) |
| **path_provider** | `2.1.6` | BSD-3-Clause | Flutter Team / Google LLC | Filesystem directory resolution for cache and documents | [path_provider](https://github.com/flutter/packages/tree/main/packages/path_provider) |
| **permission_handler** | `12.0.3` | MIT | Baseflow | Android runtime permission management (storage & notifications) | [permission_handler](https://github.com/Baseflow/flutter-permission-handler) |
| **share_plus** | `13.2.0` | BSD-3-Clause | Flutter Community | Native platform share dialog integration | [share_plus](https://github.com/fluttercommunity/plus_plugins) |
| **supabase_flutter** | `2.16.0` | MIT | Supabase Inc. | Supabase client for Auth, Database, and Realtime | [supabase_flutter](https://github.com/supabase/supabase-flutter) |
| **url_launcher** | `6.3.2` | BSD-3-Clause | Flutter Team / Google LLC | System URL and mailto handler | [url_launcher](https://github.com/flutter/packages/tree/main/packages/url_launcher) |
| **youtube_explode_dart** | `3.1.0` | MIT | Hexer10 (K vast) | Client-side YouTube audio stream manifest deciphering | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) |

---

## 3. Bundled Typography & Iconography

### Google Fonts — Geist
- **License:** SIL Open Font License, Version 1.1 (OFL-1.1)
- **Copyright:** Copyright (c) 2023 Vercel Inc. / The Geist Project Authors
- **Usage:** Primary body and display sans-serif typeface.
- **Repository:** https://github.com/vercel/geist-font

### Google Fonts — Playfair Display
- **License:** SIL Open Font License, Version 1.1 (OFL-1.1)
- **Copyright:** Copyright (c) 2010-2012 Claus Eggers Sorensen (claus@fort-foundry.com)
- **Usage:** Editorial and heading serif typography.
- **Repository:** https://github.com/clauseggers/Playfair-Display

### Material Symbols & Icons
- **License:** Apache License 2.0
- **Copyright:** Copyright (c) Google LLC
- **Usage:** User interface iconography.
- **Repository:** https://github.com/google/material-design-icons

---

## 4. Transitive Dependencies Inventory

Miee includes 146 transitive packages resolved through `pubspec.lock`. All packages are listed below with their locked versions, confirmed licenses, and upstream sources:

| Package Name | Locked Version | Verified License | Source / Upstream Repository |
| :--- | :--- | :--- | :--- |
| `app_links` | `7.2.0` | Apache-2.0 | [app_links](https://github.com/llfbandit/app_links) |
| `app_links_linux` | `1.0.3` | Apache-2.0 | [app_links_linux](https://github.com/llfbandit/app_links/tree/master/app_links_linux) |
| `app_links_platform_interface` | `2.0.3` | Apache-2.0 | [app_links_platform_interface](https://github.com/llfbandit/app_links/tree/main/app_links_platform_interface) |
| `app_links_web` | `1.0.4` | Apache-2.0 | [app_links_web](https://github.com/llfbandit/app_links/tree/master/app_links_web) |
| `archive` | `4.0.9` | MIT | [archive](https://github.com/brendan-duncan/archive) |
| `args` | `2.7.0` | BSD-3-Clause | [args](https://github.com/dart-lang/core/tree/main/pkgs/args) |
| `async` | `2.13.1` | BSD-3-Clause | [async](https://github.com/dart-lang/core/tree/main/pkgs/async) |
| `audio_service_platform_interface` | `0.1.3` | MIT | [audio_service_platform_interface](https://github.com/ryanheise/audio_service/tree/master/audio_service_platform_interface) |
| `audio_service_web` | `0.1.4` | MIT | [audio_service_web](https://github.com/ryanheise/audio_service/tree/master/audio_service_web) |
| `boolean_selector` | `2.1.2` | BSD-3-Clause | [boolean_selector](https://github.com/dart-lang/tools/tree/main/pkgs/boolean_selector) |
| `characters` | `1.4.1` | BSD-3-Clause | [characters](https://github.com/dart-lang/core/tree/main/pkgs/characters) |
| `checked_yaml` | `2.0.4` | BSD-3-Clause | [checked_yaml](https://github.com/google/json_serializable.dart/tree/master/checked_yaml) |
| `cli_util` | `0.4.2` | BSD-3-Clause | [cli_util](https://github.com/dart-lang/tools/tree/main/pkgs/cli_util) |
| `clock` | `1.1.2` | Apache-2.0 | [clock](https://github.com/dart-lang/tools/tree/main/pkgs/clock) |
| `code_assets` | `1.2.1` | BSD-3-Clause | [code_assets](https://github.com/dart-lang/native/tree/main/pkgs/code_assets) |
| `collection` | `1.19.1` | BSD-3-Clause | [collection](https://github.com/dart-lang/core/tree/main/pkgs/collection) |
| `connectivity_plus_platform_interface` | `2.1.0` | BSD-3-Clause | [connectivity_plus_platform_interface](https://github.com/fluttercommunity/plus_plugins/tree/main/packages/) |
| `convert` | `3.1.2` | BSD-3-Clause | [convert](https://github.com/dart-lang/core/tree/main/pkgs/convert) |
| `cross_file` | `0.3.5+4` | BSD-3-Clause | [cross_file](https://github.com/flutter/packages/tree/main/packages/cross_file) |
| `crypto` | `3.0.7` | BSD-3-Clause | [crypto](https://github.com/dart-lang/core/tree/main/pkgs/crypto) |
| `csslib` | `1.0.2` | BSD-3-Clause | [csslib](https://github.com/dart-lang/tools/tree/main/pkgs/csslib) |
| `dart_jsonwebtoken` | `3.4.1` | MIT | [dart_jsonwebtoken](https://github.com/jonasroussel/dart_jsonwebtoken) |
| `dbus` | `0.7.14` | MPL-2.0 | [dbus](https://github.com/canonical/dbus.dart) |
| `dio_web_adapter` | `2.2.0` | MIT | [dio_web_adapter](https://github.com/cfug/dio/blob/main/plugins/web_adapter) |
| `fake_async` | `1.3.3` | Apache-2.0 | [fake_async](https://github.com/dart-lang/test/tree/master/pkgs/fake_async) |
| `ffi` | `2.2.0` | BSD-3-Clause | [ffi](https://github.com/dart-lang/native/tree/main/pkgs/ffi) |
| `ffi_leak_tracker` | `0.1.2` | BSD-3-Clause | [ffi_leak_tracker](https://github.com/halildurmus/win32/tree/main/packages/ffi_leak_tracker) |
| `file` | `7.0.1` | BSD-3-Clause | [file](https://github.com/dart-lang/tools/tree/main/pkgs/file) |
| `file_selector_linux` | `0.9.4` | BSD-3-Clause | [file_selector_linux](https://github.com/flutter/packages/tree/main/packages/file_selector/file_selector_linux) |
| `file_selector_macos` | `0.9.5` | BSD-3-Clause | [file_selector_macos](https://github.com/flutter/packages/tree/main/packages/file_selector/file_selector_macos) |
| `file_selector_platform_interface` | `2.7.0` | BSD-3-Clause | [file_selector_platform_interface](https://github.com/flutter/packages/tree/main/packages/file_selector/file_selector_platform_interface) |
| `file_selector_windows` | `0.9.3+5` | BSD-3-Clause | [file_selector_windows](https://github.com/flutter/packages/tree/main/packages/file_selector/file_selector_windows) |
| `fixnum` | `1.1.1` | BSD-3-Clause | [fixnum](https://github.com/dart-lang/core/tree/main/pkgs/fixnum) |
| `flutter_cache_manager` | `3.4.1` | MIT | [flutter_cache_manager](https://github.com/Baseflow/flutter_cache_manager/tree/develop/flutter_cache_manager) |
| `flutter_plugin_android_lifecycle` | `2.0.35` | BSD-3-Clause | [flutter_plugin_android_lifecycle](https://github.com/flutter/packages/tree/main/packages/flutter_plugin_android_lifecycle) |
| `flutter_test` | `0.0.0` | BSD-3-Clause | [flutter_test](https://github.com/flutter/flutter) |
| `flutter_web_plugins` | `0.0.0` | BSD-3-Clause | [flutter_web_plugins](https://github.com/flutter/flutter) |
| `freezed_annotation` | `3.1.0` | MIT | [freezed_annotation](https://github.com/rrousselGit/freezed) |
| `functions_client` | `2.6.4` | MIT | [functions_client](https://github.com/supabase/supabase-flutter/tree/main/packages/functions_client) |
| `gotrue` | `2.26.0` | MIT | [gotrue](https://github.com/supabase/supabase-flutter/tree/main/packages/gotrue) |
| `gtk` | `2.2.0` | MPL-2.0 | [gtk](https://github.com/ubuntu-flutter-community/gtk.dart) |
| `hooks` | `2.0.2` | BSD-3-Clause | [hooks](https://github.com/dart-lang/native/tree/main/pkgs/hooks) |
| `html` | `0.15.7` | MIT | [html](https://github.com/dart-lang/tools/tree/main/pkgs/html) |
| `http` | `1.6.0` | BSD-3-Clause | [http](https://github.com/dart-lang/http/tree/master/pkgs/http) |
| `http_parser` | `4.1.2` | BSD-3-Clause | [http_parser](https://github.com/dart-lang/http/tree/master/pkgs/http_parser) |
| `id3` | `1.0.2` | MIT | [id3](https://github.com/sanket143/id3) |
| `image` | `4.8.0` | MIT | [image](https://github.com/brendan-duncan/image) |
| `image_picker_android` | `0.8.13+19` | Apache-2.0 | [image_picker_android](https://github.com/flutter/packages/tree/main/packages/image_picker/image_picker_android) |
| `image_picker_for_web` | `3.1.1` | BSD-3-Clause | [image_picker_for_web](https://github.com/flutter/packages/tree/main/packages/image_picker/image_picker_for_web) |
| `image_picker_ios` | `0.8.13+6` | Apache-2.0 | [image_picker_ios](https://github.com/flutter/packages/tree/main/packages/image_picker/image_picker_ios) |
| `image_picker_linux` | `0.2.2` | BSD-3-Clause | [image_picker_linux](https://github.com/flutter/packages/tree/main/packages/image_picker/image_picker_linux) |
| `image_picker_macos` | `0.2.2+1` | BSD-3-Clause | [image_picker_macos](https://github.com/flutter/packages/tree/main/packages/image_picker/image_picker_macos) |
| `image_picker_platform_interface` | `2.11.1` | BSD-3-Clause | [image_picker_platform_interface](https://github.com/flutter/packages/tree/main/packages/image_picker/image_picker_platform_interface) |
| `image_picker_windows` | `0.2.2` | BSD-3-Clause | [image_picker_windows](https://github.com/flutter/packages/tree/main/packages/image_picker/image_picker_windows) |
| `jni` | `1.0.0` | BSD-3-Clause | [jni](https://github.com/dart-lang/native/tree/main/pkgs/jni) |
| `jni_flutter` | `1.0.1` | BSD-3-Clause | [jni_flutter](https://github.com/dart-lang/native/tree/main/pkgs/jni_flutter) |
| `js` | `0.7.2` | BSD-3-Clause | [js](https://github.com/dart-lang/sdk/tree/main/pkg/js) |
| `json_annotation` | `4.12.0` | BSD-3-Clause | [json_annotation](https://github.com/google/json_serializable.dart/tree/master/json_annotation) |
| `just_audio_platform_interface` | `4.6.0` | MIT | [just_audio_platform_interface](https://github.com/ryanheise/just_audio/tree/master/just_audio_platform_interface) |
| `just_audio_web` | `0.4.16` | MIT | [just_audio_web](https://github.com/ryanheise/just_audio/tree/master/just_audio_web) |
| `jwt_decode` | `0.3.1` | BSD-3-Clause | [jwt_decode](https://github.com/sidsbrmnn/jwt_decode) |
| `leak_tracker` | `11.0.2` | BSD-3-Clause | [leak_tracker](https://github.com/dart-lang/leak_tracker/tree/main/pkgs/leak_tracker) |
| `leak_tracker_flutter_testing` | `3.0.10` | BSD-3-Clause | [leak_tracker_flutter_testing](https://github.com/dart-lang/leak_tracker/tree/main/pkgs/leak_tracker_flutter_testing) |
| `leak_tracker_testing` | `3.0.2` | BSD-3-Clause | [leak_tracker_testing](https://github.com/dart-lang/leak_tracker/tree/main/pkgs/leak_tracker_testing) |
| `lints` | `6.1.0` | BSD-3-Clause | [lints](https://github.com/dart-lang/core/tree/main/pkgs/lints) |
| `logging` | `1.3.0` | BSD-3-Clause | [logging](https://github.com/dart-lang/core/tree/main/pkgs/logging) |
| `matcher` | `0.12.20` | BSD-3-Clause | [matcher](https://github.com/dart-lang/test/tree/master/pkgs/matcher) |
| `material_color_utilities` | `0.13.0` | Apache-2.0 | [material_color_utilities](https://github.com/material-foundation/material-color-utilities/tree/main/dart) |
| `meta` | `1.19.0` | BSD-3-Clause | [meta](https://github.com/dart-lang/sdk/tree/main/pkg/meta) |
| `mime` | `2.0.0` | BSD-3-Clause | [mime](https://github.com/dart-lang/tools/tree/main/pkgs/mime) |
| `nm` | `0.5.0` | MPL-2.0 | [nm](https://github.com/canonical/nm.dart) |
| `objective_c` | `9.4.1` | BSD-3-Clause | [objective_c](https://github.com/dart-lang/native/tree/main/pkgs/objective_c) |
| `on_audio_query_android` | `1.1.0` | BSD-3-Clause | [on_audio_query_android](https://github.com/LucJosin/on_audio_query/tree/main/packages/on_audio_query_android) |
| `on_audio_query_ios` | `1.1.0` | BSD-3-Clause | [on_audio_query_ios](https://github.com/LucJosin/on_audio_query/tree/main/packages/on_audio_query_ios) |
| `on_audio_query_platform_interface` | `1.7.0` | BSD-3-Clause | [on_audio_query_platform_interface](https://github.com/LucJosin/on_audio_query/tree/main/packages/on_audio_query_platform_interface) |
| `on_audio_query_web` | `1.6.0` | BSD-3-Clause | [on_audio_query_web](https://github.com/LucJosin/on_audio_query/tree/main/packages/on_audio_query_web) |
| `package_config` | `2.2.0` | BSD-3-Clause | [package_config](https://github.com/dart-lang/tools/tree/main/pkgs/package_config) |
| `passkeys_platform_interface` | `2.8.0` | BSD-3-Clause | [passkeys_platform_interface](https://github.com/corbado/flutter-passkeys/tree/main/packages/passkeys/passkeys_platform_interface) |
| `path` | `1.9.1` | BSD-3-Clause | [path](https://github.com/dart-lang/core/tree/main/pkgs/path) |
| `path_provider_android` | `2.3.1` | BSD-3-Clause | [path_provider_android](https://github.com/flutter/packages/tree/main/packages/path_provider/path_provider_android) |
| `path_provider_foundation` | `2.6.0` | BSD-3-Clause | [path_provider_foundation](https://github.com/flutter/packages/tree/main/packages/path_provider/path_provider_foundation) |
| `path_provider_linux` | `2.2.2` | BSD-3-Clause | [path_provider_linux](https://github.com/flutter/packages/tree/main/packages/path_provider/path_provider_linux) |
| `path_provider_platform_interface` | `2.1.3` | BSD-3-Clause | [path_provider_platform_interface](https://github.com/flutter/packages/tree/main/packages/path_provider/path_provider_platform_interface) |
| `path_provider_windows` | `2.3.0` | BSD-3-Clause | [path_provider_windows](https://github.com/flutter/packages/tree/main/packages/path_provider/path_provider_windows) |
| `permission_handler_android` | `13.0.1` | MIT | [permission_handler_android](https://github.com/baseflow/flutter-permission-handler) |
| `permission_handler_apple` | `9.4.10` | MIT | [permission_handler_apple](https://github.com/baseflow/flutter-permission-handler) |
| `permission_handler_html` | `0.1.3+5` | MIT | [permission_handler_html](https://github.com/baseflow/flutter-permission-handler) |
| `permission_handler_platform_interface` | `4.3.0` | MIT | [permission_handler_platform_interface](https://github.com/baseflow/flutter-permission-handler/tree/master/permission_handler_platform_interface) |
| `permission_handler_windows` | `0.2.1` | MIT | [permission_handler_windows](https://github.com/baseflow/flutter-permission-handler) |
| `petitparser` | `7.0.2` | MIT | [petitparser](https://github.com/petitparser/dart-petitparser) |
| `platform` | `3.1.6` | BSD-3-Clause | [platform](https://github.com/dart-lang/core/tree/main/pkgs/platform) |
| `plugin_platform_interface` | `2.1.8` | BSD-3-Clause | [plugin_platform_interface](https://github.com/flutter/packages/tree/main/packages/plugin_platform_interface) |
| `pointycastle` | `4.0.0` | MIT | [pointycastle](https://github.com/bcgit/pc-dart) |
| `posix` | `6.5.0` | MIT | [posix](https://github.com/onepub-dev/dart_posix) |
| `postgrest` | `2.8.0` | MIT | [postgrest](https://github.com/supabase/supabase-flutter/tree/main/packages/postgrest) |
| `pub_semver` | `2.2.0` | BSD-3-Clause | [pub_semver](https://github.com/dart-lang/tools/tree/main/pkgs/pub_semver) |
| `realtime_client` | `2.11.0` | MIT | [realtime_client](https://github.com/supabase/supabase-flutter/tree/main/packages/realtime_client) |
| `record_use` | `0.6.0` | BSD-3-Clause | [record_use](https://github.com/dart-lang/native/tree/main/pkgs/record_use) |
| `retry` | `3.1.2` | Apache-2.0 | [retry](https://github.com/google/dart-neats.git) |
| `riverpod` | `2.6.1` | MIT | [riverpod](https://github.com/rrousselGit/riverpod) |
| `rxdart` | `0.28.0` | Apache-2.0 | [rxdart](https://github.com/ReactiveX/rxdart) |
| `share_plus_platform_interface` | `7.1.0` | BSD-3-Clause | [share_plus_platform_interface](https://github.com/fluttercommunity/plus_plugins/tree/main/packages/) |
| `shared_preferences` | `2.5.5` | BSD-3-Clause | [shared_preferences](https://github.com/flutter/packages/tree/main/packages/shared_preferences/shared_preferences) |
| `shared_preferences_android` | `2.4.26` | BSD-3-Clause | [shared_preferences_android](https://github.com/flutter/packages/tree/main/packages/shared_preferences/shared_preferences_android) |
| `shared_preferences_foundation` | `2.5.6` | BSD-3-Clause | [shared_preferences_foundation](https://github.com/flutter/packages/tree/main/packages/shared_preferences/shared_preferences_foundation) |
| `shared_preferences_linux` | `2.4.1` | BSD-3-Clause | [shared_preferences_linux](https://github.com/flutter/packages/tree/main/packages/shared_preferences/shared_preferences_linux) |
| `shared_preferences_platform_interface` | `2.4.2` | BSD-3-Clause | [shared_preferences_platform_interface](https://github.com/flutter/packages/tree/main/packages/shared_preferences/shared_preferences_platform_interface) |
| `shared_preferences_web` | `2.4.3` | BSD-3-Clause | [shared_preferences_web](https://github.com/flutter/packages/tree/main/packages/shared_preferences/shared_preferences_web) |
| `shared_preferences_windows` | `2.4.1` | BSD-3-Clause | [shared_preferences_windows](https://github.com/flutter/packages/tree/main/packages/shared_preferences/shared_preferences_windows) |
| `simple_sparse_list` | `0.1.4` | BSD-3-Clause | [simple_sparse_list](https://github.com/mezoni/simple_sparse_list) |
| `sky_engine` | `0.0.0` | BSD-3-Clause | [sky_engine](https://github.com/flutter/flutter) |
| `source_span` | `1.10.2` | BSD-3-Clause | [source_span](https://github.com/dart-lang/tools/tree/main/pkgs/source_span) |
| `sqflite` | `2.4.3` | BSD-2-Clause | [sqflite](https://github.com/tekartik/sqflite/tree/master/sqflite) |
| `sqflite_android` | `2.4.3` | BSD-2-Clause | [sqflite_android](https://github.com/tekartik/sqflite/tree/master/sqflite_android) |
| `sqflite_common` | `2.5.11` | BSD-2-Clause | [sqflite_common](https://github.com/tekartik/sqflite/tree/master/sqflite_common) |
| `sqflite_darwin` | `2.4.3+1` | BSD-2-Clause | [sqflite_darwin](https://github.com/tekartik/sqflite/tree/master/sqflite_darwin) |
| `sqflite_platform_interface` | `2.4.1` | BSD-2-Clause | [sqflite_platform_interface](https://github.com/tekartik/sqflite/tree/master/sqflite_platform_interface) |
| `stack_trace` | `1.12.1` | BSD-3-Clause | [stack_trace](https://github.com/dart-lang/tools/tree/main/pkgs/stack_trace) |
| `state_notifier` | `1.0.0` | MIT | [state_notifier](https://github.com/rrousselGit/state_notifier) |
| `storage_client` | `2.6.0` | MIT | [storage_client](https://github.com/supabase/supabase-flutter/tree/main/packages/storage_client) |
| `stream_channel` | `2.1.4` | BSD-3-Clause | [stream_channel](https://github.com/dart-lang/tools/tree/main/pkgs/stream_channel) |
| `string_scanner` | `1.4.1` | BSD-3-Clause | [string_scanner](https://github.com/dart-lang/tools/tree/main/pkgs/string_scanner) |
| `supabase` | `2.14.0` | MIT | [supabase](https://github.com/supabase/supabase-flutter/tree/main/packages/supabase) |
| `synchronized` | `3.4.1` | MIT | [synchronized](https://github.com/tekartik/synchronized.dart/tree/master/synchronized) |
| `term_glyph` | `1.2.2` | BSD-3-Clause | [term_glyph](https://github.com/dart-lang/tools/tree/main/pkgs/term_glyph) |
| `test_api` | `0.7.12` | BSD-3-Clause | [test_api](https://github.com/dart-lang/test/tree/master/pkgs/test_api) |
| `typed_data` | `1.4.0` | BSD-3-Clause | [typed_data](https://github.com/dart-lang/core/tree/main/pkgs/typed_data) |
| `unicode` | `1.1.9` | BSD-3-Clause | [unicode](https://github.com/mezoni/unicode) |
| `url_launcher_android` | `6.3.32` | BSD-3-Clause | [url_launcher_android](https://github.com/flutter/packages/tree/main/packages/url_launcher/url_launcher_android) |
| `url_launcher_ios` | `6.4.1` | BSD-3-Clause | [url_launcher_ios](https://github.com/flutter/packages/tree/main/packages/url_launcher/url_launcher_ios) |
| `url_launcher_linux` | `3.2.2` | BSD-3-Clause | [url_launcher_linux](https://github.com/flutter/packages/tree/main/packages/url_launcher/url_launcher_linux) |
| `url_launcher_macos` | `3.2.5` | BSD-3-Clause | [url_launcher_macos](https://github.com/flutter/packages/tree/main/packages/url_launcher/url_launcher_macos) |
| `url_launcher_platform_interface` | `2.3.2` | BSD-3-Clause | [url_launcher_platform_interface](https://github.com/flutter/packages/tree/main/packages/url_launcher/url_launcher_platform_interface) |
| `url_launcher_web` | `2.4.3` | BSD-3-Clause | [url_launcher_web](https://github.com/flutter/packages/tree/main/packages/url_launcher/url_launcher_web) |
| `url_launcher_windows` | `3.1.5` | BSD-3-Clause | [url_launcher_windows](https://github.com/flutter/packages/tree/main/packages/url_launcher/url_launcher_windows) |
| `uuid` | `4.5.3` | MIT | [uuid](https://github.com/Daegalus/dart-uuid) |
| `vector_math` | `2.4.2` | BSD-3-Clause | [vector_math](https://github.com/flutter/core-packages/tree/main/packages/vector_math) |
| `vm_service` | `15.2.0` | BSD-3-Clause | [vm_service](https://github.com/dart-lang/sdk/tree/main/pkg/vm_service) |
| `web` | `1.1.1` | BSD-3-Clause | [web](https://github.com/dart-lang/web) |
| `web_socket` | `1.0.1` | BSD-3-Clause | [web_socket](https://github.com/dart-lang/http/tree/master/pkgs/web_socket) |
| `web_socket_channel` | `3.0.3` | BSD-3-Clause | [web_socket_channel](https://github.com/dart-lang/http/tree/master/pkgs/web_socket_channel) |
| `win32` | `6.3.0` | BSD-3-Clause | [win32](https://github.com/halildurmus/win32) |
| `xdg_directories` | `1.1.0` | BSD-3-Clause | [xdg_directories](https://github.com/flutter/packages/tree/main/packages/xdg_directories) |
| `xml` | `6.6.1` | MIT | [xml](https://github.com/renggli/dart-xml) |
| `yaml` | `3.1.3` | MIT | [yaml](https://github.com/dart-lang/tools/tree/main/pkgs/yaml) |
| `yet_another_json_isolate` | `2.1.1` | MIT | [yet_another_json_isolate](https://github.com/supabase-community/json-isolate-dart) |

---

## 5. Compliance Notes on Specialized Licenses

### Mozilla Public License 2.0 (MPL-2.0)
The inventory identifies three transitive packages licensed under MPL-2.0:
- `dbus` (v0.7.14)
- `gtk` (v2.2.0)
- `nm` (v0.5.0)

**Technical & Compliance Status:**
1. **Target Architecture:** These packages provide Linux D-Bus, GTK, and NetworkManager desktop platform interfaces required transitively by `connectivity_plus_linux` and `app_links_linux`.
2. **Release Binary Verification:** When Miee is compiled for Android (APK/AAB), Linux platform libraries are stripped from the compilation graph by the Flutter build tree shaking.
3. **Source Availability:** In compliance with Section 3 of the MPL-2.0 license, the source code of these packages is unmodified and freely available in source form from upstream repositories and `https://pub.dev`.

---

## 6. Native Android Platform Components & Build Tools

| Component | Technology / Platform | License | Upstream Origin |
| :--- | :--- | :--- | :--- |
| **Android Gradle Plugin (AGP)** | Android Build System | Apache-2.0 | Google LLC / Android Open Source Project |
| **Kotlin Gradle Plugin & Stdlib** | Kotlin 1.9+ Runtime | Apache-2.0 | JetBrains s.r.o. |
| **AndroidX Core & Appcompat** | Android Jetpack Runtime | Apache-2.0 | Android Open Source Project |
| **AndroidX Media & Media2** | System Media Session Interface | Apache-2.0 | Android Open Source Project |
| **AndroidX ExifInterface** | Image EXIF orientation handling | Apache-2.0 | Android Open Source Project |
| **Flutter Engine & Shell** | Native C++ Rendering Engine | BSD-3-Clause | Google LLC / Flutter Authors |

---

## 7. Standard License Texts

### The MIT License (MIT)
```text
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### The 3-Clause BSD License (BSD-3-Clause)
```text
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### Apache License, Version 2.0 (Apache-2.0)
```text
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

### SIL Open Font License, Version 1.1 (OFL-1.1)
```text
This Font Software is licensed under the SIL Open Font License, Version 1.1.
This license is available with a FAQ at: http://scripts.sil.org/OFL

Permission is hereby granted, free of charge, to any person obtaining a copy
of the Font Software, to use, study, copy, merge, embed, modify, redistribute,
and sell modified and unmodified copies of the Font Software, subject to the
conditions specified in the SIL Open Font License 1.1.
```

---

## 8. In-App Access & Official Contact

All bundled open-source licenses and notices can be reviewed within the Miee app by navigating to **Settings → About Miee → Open Source Licenses**.

For open-source licensing questions, copyright inquiries, or requests for source bundles required under applicable licenses, contact:

**Contact Email:** `imposterz.rev02@gmail.com`