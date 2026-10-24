import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_colors.dart';
import '../data/legal_content.dart';

enum LegalTab {
  privacyPolicy,
  termsOfService,
  licenses,
  about,
}

/// Dedicated, pristine full-page viewer for Miee legal documents,
/// open-source licensing notices, and version release information.
class LegalDocumentPage extends StatefulWidget {
  final LegalTab initialTab;

  const LegalDocumentPage({
    super.key,
    this.initialTab = LegalTab.privacyPolicy,
  });

  @override
  State<LegalDocumentPage> createState() => _LegalDocumentPageState();
}

class _LegalDocumentPageState extends State<LegalDocumentPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _licenseSearchController = TextEditingController();
  String _licenseQuery = '';
  bool _filterOnlyDirect = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.index,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _licenseSearchController.dispose();
    super.dispose();
  }

  Future<void> _launchEmail({String subject = 'Miee Inquiry (v2.0.0)'}) async {
    final uri = Uri(
      scheme: 'mailto',
      path: LegalContent.officialEmail,
      queryParameters: {'subject': subject},
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showCopyEmailDialog();
      }
    } catch (_) {
      _showCopyEmailDialog();
    }
  }

  Future<void> _launchUrlString(String urlStr) async {
    final uri = Uri.tryParse(urlStr);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showCopyEmailDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
        title: const Text(
          'Official Support Contact',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.cocoaPlum),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please direct all privacy, licensing, and support inquiries to:',
              style: TextStyle(color: AppColors.mutedMauve),
            ),
            SizedBox(height: 12.0),
            SelectableText(
              LegalContent.officialEmail,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16.0,
                color: AppColors.dustyRose,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: AppColors.dustyRose)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.vanillaCream,
      appBar: AppBar(
        backgroundColor: AppColors.vanillaCream,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.cocoaPlum),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Legal & Release Info',
          style: TextStyle(
            fontSize: 20.0,
            fontWeight: FontWeight.w700,
            color: AppColors.cocoaPlum,
            letterSpacing: 0.1,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.mail_outline_rounded, color: AppColors.cocoaPlum),
            tooltip: 'Contact Support',
            onPressed: () => _launchEmail(),
          ),
          const SizedBox(width: 8.0),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48.0),
          child: Container(
            height: 48.0,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppColors.dustyRose,
              indicatorWeight: 3.0,
              labelColor: AppColors.cocoaPlum,
              unselectedLabelColor: AppColors.mutedMauve,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
              tabs: const [
                Tab(text: 'Privacy Policy'),
                Tab(text: 'Terms of Service'),
                Tab(text: 'Open Source Licenses'),
                Tab(text: 'About v2.0.0'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDocumentView(
            title: 'Privacy Policy',
            subtitle: 'Version ${LegalContent.currentVersion} • Updated ${LegalContent.releaseDate}',
            badge: 'Local-First Data Protection',
            sections: LegalContent.privacyPolicy,
            emailSubject: 'Miee Privacy Request (v2.0.0)',
          ),
          _buildDocumentView(
            title: 'Terms of Service',
            subtitle: 'Version ${LegalContent.currentVersion} • Updated ${LegalContent.releaseDate}',
            badge: 'User Agreement & Disclaimers',
            sections: LegalContent.termsOfService,
            emailSubject: 'Miee Terms Inquiry (v2.0.0)',
          ),
          _buildLicensesView(),
          _buildAboutView(),
        ],
      ),
    );
  }

  // ── 1 & 2. DOCUMENT SECTION VIEW ──────────────────────────────────────────

  Widget _buildDocumentView({
    required String title,
    required String subtitle,
    required String badge,
    required List<LegalSection> sections,
    required String emailSubject,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 36.0),
      children: [
        // Header Card
        Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: AppColors.oatBeige.withOpacity(0.8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: AppColors.dustyRose.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dustyRose,
                  ),
                ),
              ),
              const SizedBox(height: 12.0),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22.0,
                  fontWeight: FontWeight.bold,
                  color: AppColors.cocoaPlum,
                ),
              ),
              const SizedBox(height: 4.0),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13.0,
                  color: AppColors.mutedMauve,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16.0),

        // Section Cards
        ...sections.map((section) {
          return Container(
            margin: const EdgeInsets.only(bottom: 14.0),
            padding: const EdgeInsets.all(18.0),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(color: AppColors.oatBeige.withOpacity(0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.bold,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                if (section.summary != null) ...[
                  const SizedBox(height: 6.0),
                  Text(
                    section.summary!,
                    style: const TextStyle(
                      fontSize: 13.0,
                      fontWeight: FontWeight.w600,
                      color: AppColors.dustyRose,
                    ),
                  ),
                ],
                const SizedBox(height: 10.0),
                ...section.paragraphs.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      p,
                      style: const TextStyle(
                        fontSize: 14.0,
                        height: 1.55,
                        color: AppColors.mutedMauve,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),

        // Support Contact Card
        Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: AppColors.dustyRose.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Questions or Requests?',
                style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  color: AppColors.cocoaPlum,
                ),
              ),
              const SizedBox(height: 6.0),
              const Text(
                'For data privacy requests, account deletion, or legal questions, reach out to our official email address:',
                style: TextStyle(fontSize: 13.5, color: AppColors.mutedMauve),
              ),
              const SizedBox(height: 12.0),
              OutlinedButton.icon(
                icon: const Icon(Icons.send_rounded, size: 16.0, color: AppColors.dustyRose),
                label: const Text(
                  LegalContent.officialEmail,
                  style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.cocoaPlum),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.dustyRose),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                  padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                ),
                onPressed: () => _launchEmail(subject: emailSubject),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 3. OPEN SOURCE LICENSES VIEW ──────────────────────────────────────────

  Widget _buildLicensesView() {
    final filtered = LegalContent.dependencies.where((dep) {
      if (_filterOnlyDirect && !dep.isDirect) return false;
      if (_licenseQuery.isEmpty) return true;
      final q = _licenseQuery.toLowerCase();
      return dep.name.toLowerCase().contains(q) ||
          dep.license.toLowerCase().contains(q) ||
          dep.author.toLowerCase().contains(q) ||
          dep.purpose.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        // Search & Filter Header
        Container(
          color: AppColors.vanillaCream,
          padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
          child: Column(
            children: [
              TextField(
                controller: _licenseSearchController,
                onChanged: (val) => setState(() => _licenseQuery = val.trim()),
                decoration: InputDecoration(
                  hintText: 'Search 167 dependencies or licenses...',
                  hintStyle: const TextStyle(fontSize: 13.5, color: AppColors.mutedMauve),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.mutedMauve),
                  suffixIcon: _licenseQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18, color: AppColors.mutedMauve),
                          onPressed: () {
                            _licenseSearchController.clear();
                            setState(() => _licenseQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.surfaceContainerLowest,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                    borderSide: BorderSide(color: AppColors.oatBeige.withOpacity(0.8)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                    borderSide: BorderSide(color: AppColors.oatBeige.withOpacity(0.8)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                    borderSide: const BorderSide(color: AppColors.dustyRose, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 8.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      FilterChip(
                        selected: _filterOnlyDirect,
                        label: const Text('Direct (19)', style: TextStyle(fontSize: 12.0)),
                        selectedColor: AppColors.dustyRose.withOpacity(0.2),
                        backgroundColor: AppColors.surfaceContainerLowest,
                        checkmarkColor: AppColors.dustyRose,
                        onSelected: (val) => setState(() => _filterOnlyDirect = val),
                      ),
                      const SizedBox(width: 8.0),
                      Text(
                        '${filtered.length} packages shown',
                        style: const TextStyle(fontSize: 12.0, color: AppColors.mutedMauve),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_new_rounded, size: 14.0, color: AppColors.dustyRose),
                    label: const Text('Flutter License Page', style: TextStyle(fontSize: 12.0, color: AppColors.dustyRose, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      showLicensePage(
                        context: context,
                        applicationName: 'Miee',
                        applicationVersion: '2.0.0 (Build 2)',
                        applicationIcon: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Image.asset(
                            'assets/logo/miee_launcher_512.png',
                            width: 64,
                            height: 64,
                            errorBuilder: (_, __, ___) => const Icon(Icons.music_note, size: 48, color: AppColors.dustyRose),
                          ),
                        ),
                        applicationLegalese: 'Copyright © 2024–2026 Miee Maintainers.\nThird-party open-source notices documented in docs/OPEN_SOURCE_NOTICES.md.\nOfficial contact: imposterz.rev02@gmail.com',
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        // List of Dependencies
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 36.0),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final dep = filtered[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8.0),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(color: AppColors.oatBeige.withOpacity(0.6)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          dep.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                            color: AppColors.cocoaPlum,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                        decoration: BoxDecoration(
                          color: AppColors.oatBeige.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                        child: Text(
                          'v${dep.version}',
                          style: const TextStyle(fontSize: 11.0, color: AppColors.cocoaPlum, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (dep.isDirect) ...[
                        const SizedBox(width: 6.0),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                          decoration: BoxDecoration(
                            color: AppColors.dustyRose.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                          child: const Text(
                            'Direct',
                            style: TextStyle(fontSize: 10.0, color: AppColors.dustyRose, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4.0),
                      Text(
                        dep.purpose.isNotEmpty
                            ? dep.purpose
                            : (dep.author.isNotEmpty ? 'By ${dep.author}' : 'Transitive Flutter dependency'),
                        style: const TextStyle(fontSize: 12.5, color: AppColors.mutedMauve),
                      ),
                      const SizedBox(height: 6.0),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                            decoration: BoxDecoration(
                              color: dep.license == 'MIT'
                                  ? Colors.green.withOpacity(0.12)
                                  : dep.license.contains('BSD')
                                      ? Colors.blue.withOpacity(0.12)
                                      : dep.license.contains('Apache')
                                          ? Colors.orange.withOpacity(0.12)
                                          : Colors.purple.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4.0),
                            ),
                            child: Text(
                              dep.license,
                              style: TextStyle(
                                fontSize: 11.0,
                                fontWeight: FontWeight.w600,
                                color: dep.license == 'MIT'
                                    ? Colors.green[800]
                                    : dep.license.contains('BSD')
                                        ? Colors.blue[800]
                                        : dep.license.contains('Apache')
                                            ? Colors.orange[900]
                                            : Colors.purple[800],
                              ),
                            ),
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: () => _launchUrlString(dep.url),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
                              child: Row(
                                children: [
                                  Text(
                                    'Upstream',
                                    style: TextStyle(fontSize: 11.5, color: AppColors.dustyRose, fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(width: 2.0),
                                  Icon(Icons.arrow_outward, size: 12.0, color: AppColors.dustyRose),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── 4. ABOUT & RELEASE INFORMATION VIEW ───────────────────────────────────

  Widget _buildAboutView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 36.0),
      children: [
        // App Hero Header
        Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: AppColors.oatBeige.withOpacity(0.8)),
          ),
          child: Column(
            children: [
              Image.asset(
                'assets/logo/miee_launcher_512.png',
                width: 72,
                height: 72,
                errorBuilder: (_, __, ___) => const Icon(Icons.music_note, size: 60, color: AppColors.dustyRose),
              ),
              const SizedBox(height: 12.0),
              const Text(
                'Miee',
                style: TextStyle(
                  fontSize: 26.0,
                  fontWeight: FontWeight.bold,
                  color: AppColors.cocoaPlum,
                  fontFamily: 'Playfair Display',
                ),
              ),
              const SizedBox(height: 4.0),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: AppColors.dustyRose.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: const Text(
                  'Version 2.0.0 (Build 2) • Production Release',
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dustyRose,
                  ),
                ),
              ),
              const SizedBox(height: 10.0),
              const Text(
                'A minimalist, local-first music player application crafted with Flutter & Material 3.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: AppColors.mutedMauve),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16.0),

        // Release Sections
        ...LegalContent.releaseNotes.map((section) {
          return Container(
            margin: const EdgeInsets.only(bottom: 14.0),
            padding: const EdgeInsets.all(18.0),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(color: AppColors.oatBeige.withOpacity(0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.bold,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                if (section.summary != null) ...[
                  const SizedBox(height: 4.0),
                  Text(
                    section.summary!,
                    style: const TextStyle(
                      fontSize: 13.0,
                      fontWeight: FontWeight.w600,
                      color: AppColors.dustyRose,
                    ),
                  ),
                ],
                const SizedBox(height: 10.0),
                ...section.paragraphs.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      p,
                      style: const TextStyle(
                        fontSize: 14.0,
                        height: 1.55,
                        color: AppColors.mutedMauve,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),

        // Maintainer Contact Card
        Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: AppColors.oatBeige.withOpacity(0.8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Designated Support Contact',
                style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  color: AppColors.cocoaPlum,
                ),
              ),
              const SizedBox(height: 6.0),
              const Text(
                'For bugs, general support, copyright, and licensing inquiries:',
                style: TextStyle(fontSize: 13.5, color: AppColors.mutedMauve),
              ),
              const SizedBox(height: 12.0),
              ElevatedButton.icon(
                icon: const Icon(Icons.email_outlined, size: 16.0, color: Colors.white),
                label: const Text(
                  LegalContent.officialEmail,
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.dustyRose,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                ),
                onPressed: () => _launchEmail(subject: 'Miee v2.0.0 Support'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
