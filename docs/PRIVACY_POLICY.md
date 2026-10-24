# Miee — Privacy Policy

**Effective Version:** `2.0.0` (Build `2`)  
**Last Updated:** October 2026  
**Official Privacy & Data Inquiries:** `imposterz.rev02@gmail.com`  

---

## 1. Introduction & Scope

Welcome to **Miee** ("we", "our", or "the application"). Miee is a minimalist, local-first music player application developed with Flutter, providing seamless local audio playback, cloud library synchronization, synchronized lyrics, and online audio stream discovery.

This Privacy Policy explains clearly and transparently how Miee processes, stores, and protects information when you use our mobile application and related services. We are dedicated to data minimization: Miee operates on a **local-first principle**, giving you full ownership and control over your music library and personal listening habits.

---

## 2. Information Processed by Miee

Miee processes information in two distinct categories depending on how you use the app:

### A. Local Device Data (Never Transmitted to External Servers)
- **Local Audio Files & Storage:** Miee accesses local audio files stored on your device to discover, catalog, and play offline music tracks.
- **Audio Metadata:** Metadata embedded within your audio files (track titles, artist names, album titles, track durations, genre tags, and embedded album artwork) is read and indexed locally.
- **Cached Artwork & Temporary Files:** Album covers and processed images are cached in your device's local application sandbox directory.
- **Local Settings & Preferences:** UI preferences, volume state, repeat/shuffle modes, playback resume points, and theme settings are stored strictly in local Hive databases on your device.

### B. Account & Cloud-Synchronized Data (When Authenticated)
If you choose to create a Miee account or sign in, the following data is synchronized with our cloud backend powered by **Supabase**:
- **Account Identity:** Your email address, encrypted authentication token, and user identifier (UUID).
- **Profile Details:** Custom display name, username, favorite artist selections, and custom avatar URL or reference.
- **Library Synchronization:** Songs marked as liked/favorites, custom playlists, playlist track ordering, listening history timestamps, most-played counters, and cached search queries.
- **Shared Listening Rooms:** Transient room membership, host state, and current playback position when participating in real-time listening rooms.

---

## 3. Account Information & Authentication

- **Guest / Offline Mode:** You can use Miee completely without creating an account. In guest mode, all playlists, favorites, and listening records remain exclusively within your device's local Hive database.
- **Supabase Authentication:** When signing in with email and password, authentication is processed directly and securely by Supabase Auth over TLS-encrypted connections. Passwords are never visible to or stored in plain text by Miee; Supabase handles password hashing using industry-standard cryptographic algorithms (bcrypt).
- **Session Tokens:** Authentication JWTs and refresh tokens are stored securely in local device storage and are wiped upon signing out.

---

## 4. Local Music Files, Permissions & Audio Metadata

To provide offline playback, Miee requests runtime permissions on Android:
- **`READ_MEDIA_AUDIO` (Android 13+) / `READ_EXTERNAL_STORAGE` (Android 12 and below):** Required exclusively to scan for and play audio files residing on device storage.
- **`POST_NOTIFICATIONS` (Android 13+):** Required to display playback controls in the notification drawer and lock screen.
- **Camera & Photo Gallery Permissions:** Requested on demand only when you choose to capture or select a custom profile avatar.

**Data Sovereignty Guarantee:** Miee **never** uploads, scans, mirrors, or transmits your private local audio files or external storage contents to any remote server or cloud infrastructure. All local scanning, parsing, and caching occur entirely on your device.

---

## 5. Playlists, History & Search Records

- **Favorites & Playlists:** Stored locally in Hive boxes (`favorites`, `playlists`). When signed in, these are synchronized to your private user rows in Supabase PostgreSQL tables protected by Row-Level Security (RLS).
- **Recently Played & Listening History:** Recorded locally to track playback history. When authenticated, records sync to the `history` table to enable continuity across devices.
- **Search History:** Recent search terms are stored locally in Hive (`searchHistory`) and synced to your profile to offer search auto-completion. You can wipe search history instantly in **Settings → Storage & Cache → Clear Search History**.

---

## 6. Local Storage, Caches & Offline Persistence

Miee uses Hive and device cache directories for responsive, zero-latency performance:
- **Hive Databases:** Encrypted or sandboxed binary key-value stores holding playlists, track cache, and user profile state.
- **Artwork Cache:** Stored in the temporary app cache (`getTemporaryDirectory()`).
- **Data Erasure:** You can clear artwork caches, app caches, search history, or perform a total library data wipe directly from the in-app **Settings → Storage & Cache** menu.

---

## 7. Third-Party Music Services & External Network Requests

Miee connects to select external services to provide enriched playback features:

1. **Supabase (`*.supabase.co`):**
   - **Role:** Backend database, authentication provider, and realtime room synchronization.
   - **Data Transferred:** User account UUID, email, profile metadata, synced playlists, liked song IDs, history records.
   - **Privacy Policy:** https://supabase.com/privacy

2. **YouTube & Google Video Endpoints (`*.googlevideo.com`, `*.youtube.com`):**
   - **Role:** Online music search and audio stream deciphering via `youtube_explode_dart`.
   - **Data Transferred:** Direct client-side HTTP requests for public stream manifests. Your device communicates directly with YouTube servers; Miee operates no intermediary streaming proxy. Standard HTTP connection metadata (IP address, user agent) is visible to Google/YouTube under their standard policies.
   - **Privacy Policy:** https://policies.google.com/privacy

3. **LRCLIB (`lrclib.net`):**
   - **Role:** Synchronized and plain text lyrics retrieval.
   - **Data Transferred:** Track title, artist name, and duration sent via HTTP GET requests. No user account identifiers or credentials are shared.
   - **Privacy Policy:** https://lrclib.net/docs

4. **Deezer CDN (`cdn-images.dzcdn.net`):**
   - **Role:** Displaying high-resolution artist discovery portraits.
   - **Data Transferred:** Direct image URL fetching. No user identifiers are transmitted.

5. **Google Fonts (`fonts.googleapis.com`, `fonts.gstatic.com`):**
   - **Role:** Downloading typography font binaries (Geist, Playfair Display) at runtime via `google_fonts`.
   - **Data Transferred:** Standard HTTP request for font assets.

---

## 8. Data Sharing & Disclosure

Miee does **not** sell, rent, monetize, or trade your personal data. We do not disclose personal information to third parties except:
- **Core Cloud Infrastructure:** Supabase Inc., acting strictly as our backend hosting and authentication infrastructure provider.
- **Legal Compliance:** In the rare event required by applicable law, court order, or governmental authority with appropriate legal jurisdiction.

---

## 9. Analytics, Diagnostics & Advertising SDKs

Miee is designed to be free from intrusive tracking:
- **No Advertising SDKs:** Miee contains zero advertising frameworks (no Google AdMob, Unity Ads, AppLovin, etc.).
- **No Third-Party Analytics Trackers:** Miee does not embed Google Analytics, Firebase Analytics, Mixpanel, Segment, or Facebook SDKs.
- **No Crash Telemetry SDKs:** Miee does not embed third-party crash reporting suites (no Sentry, Bugsnag, or Firebase Crashlytics). Runtime errors and sync exceptions are handled locally.

---

## 10. Data Retention & Account Deletion

- **Local Retention:** Local databases and caches persist on your device until cleared via Settings or until you uninstall the application.
- **Sign-Out Data Handling:** Signing out clears active local session tokens. Local offline music files and existing local caches remain intact on your device.
- **Account & Cloud Deletion:** You have the right to permanently delete your Miee account and all associated cloud records (profile, playlists, liked tracks, history, rooms) from Supabase. To request complete account deletion, email `imposterz.rev02@gmail.com` with the subject "Delete My Account". All corresponding database rows will be permanently expunged within 30 days.

---

## 11. Security

We implement appropriate technical safeguards to protect your personal data:
- All remote API communications (Supabase, LRCLIB, Deezer, YouTube) utilize encrypted **HTTPS / TLS 1.3** transport.
- Supabase database tables enforce strict **Row-Level Security (RLS)** policies, ensuring users can only read and write their own records.
- Local data is isolated within the Android application sandbox.

---

## 12. Children's Privacy

Miee is not directed to children under the age of 13 (or under 16 in applicable jurisdictions). We do not knowingly collect personal information from children. If you become aware that a child has provided us with personal data without parental consent, please contact us at `imposterz.rev02@gmail.com`, and we will promptly delete the data.

---

## 13. Your Privacy Rights & User Choices

Depending on your geographic location, you may have specific privacy rights:
- **Indian Digital Personal Data Protection Act (DPDP Act 2023):** You have the right to access summaries of personal data processed, request correction or erasure of personal data, and nominate an individual to exercise rights on your behalf.
- **European Economic Area & UK (GDPR / UK GDPR):** You have rights of access, rectification, erasure, restriction of processing, data portability, and the right to lodge a complaint with your local supervisory authority.
- **California & US State Laws (CCPA/CPRA):** You have the right to know what personal data is collected, delete personal data, and opt-out of data sales (we do not sell your data).

To exercise any of these rights, contact us directly at `imposterz.rev02@gmail.com`.

---

## 14. International Data Transfers

When you use cloud features, your account data is processed in cloud infrastructure managed by Supabase (Tokyo, Japan region `ap-northeast-1`). By signing in and using cloud sync, you acknowledge that your information may be processed in jurisdictions that may have different data protection laws than your home country.

---

## 15. Changes to this Privacy Policy

We may update this Privacy Policy from time to time to reflect changes in application functionality, dependencies, or legal requirements. Updated policies will be included with application releases and published in the repository. We encourage you to review this policy periodically.

---

## 16. Official Privacy Contact

For questions, feedback, data subject requests, or account deletion, please contact our designated privacy contact:

**Email:** `imposterz.rev02@gmail.com`  
**Application:** Miee Music Player  
**Target Version:** `2.0.0`
