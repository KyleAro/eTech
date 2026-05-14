import 'package:etech/pages/MainPage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:etech/style/mainpage_style.dart';
import 'package:etech/style/ripple_background.dart';
import 'package:path_provider/path_provider.dart';
import 'file_management.dart';
import 'recordPage.dart';

class MyRecordingsPage extends StatefulWidget {
  const MyRecordingsPage({super.key});

  @override
  State<MyRecordingsPage> createState() => _MyRecordingsPageState();
}

class _MyRecordingsPageState extends State<MyRecordingsPage> {
  int totalFiles = 0;
  int maleFiles = 0;
  int femaleFiles = 0;
  int undeterminedFiles = 0;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadStatistics();
  }

  Future<void> loadStatistics() async {
    setState(() => isLoading = true);

    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        setState(() => isLoading = false);
        return;
      }

      final files = await Directory(directory.path)
          .list()
          .where((file) =>
              file.path.toLowerCase().endsWith(".wav") ||
              file.path.toLowerCase().endsWith(".aac") ||
              file.path.toLowerCase().endsWith(".mp3") ||
              file.path.toLowerCase().endsWith(".m4a"))
          .toList();

      final firestore = FirebaseFirestore.instance;
      int male = 0;
      int female = 0;
      int undetermined = 0;

      for (var file in files) {
        final fileName = file.uri.pathSegments.last;

        final predictionSnapshot = await firestore
            .collection('LocalPredictions')
            .where('file_name', isEqualTo: fileName)
            .limit(1)
            .get();

        if (predictionSnapshot.docs.isNotEmpty) {
          final prediction = predictionSnapshot.docs.first.data()['prediction'];
          if (prediction == 'Male') {
            male++;
          } else if (prediction == 'Female') {
            female++;
          }
        } else {
          final undeterminedSnapshot = await firestore
              .collection('Undetermined')
              .where('file_name', isEqualTo: fileName)
              .limit(1)
              .get();

          if (undeterminedSnapshot.docs.isNotEmpty ||
              fileName.contains('Undetermined')) {
            undetermined++;
          }
        }
      }

      setState(() {
        totalFiles = files.length;
        maleFiles = male;
        femaleFiles = female;
        undeterminedFiles = undetermined;
        isLoading = false;
      });
    } catch (e) {
      print("❌ Error loading statistics: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'SPECIMENS',
          style: getCapsLabel(size: 12, opacity: 0.7),
        ),
        centerTitle: true,
        iconTheme: IconThemeData(color: textcolor),
        actions: [
          IconButton(
            icon: isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: textcolor,
                    ),
                  )
                : Icon(Icons.refresh_rounded, color: textcolor),
            onPressed: isLoading ? null : loadStatistics,
            tooltip: 'Refresh tally',
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: pondGradient),
        child: Stack(
          children: [
            const Positioned.fill(child: RippleBackground()),
            SafeArea(
              child: RefreshIndicator(
                onRefresh: loadStatistics,
                color: textcolor,
                backgroundColor: Colors.white.withValues(alpha: 0.9),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Page header
                      Text(
                        'Overview',
                        style: getSerifHeading(size: 30),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'A glance at your field journal.',
                        style: GoogleFonts.quicksand(
                          fontSize: 12,
                          color: textcolor.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 22),

                      // Field tally card
                      _sectionLabel('FIELD TALLY'),
                      const SizedBox(height: 10),
                      _buildStatsCard(),

                      const SizedBox(height: 26),

                      // Quick actions
                      _sectionLabel('QUICK ACTIONS'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _actionCard(
                              context,
                              icon: Icons.mic_rounded,
                              label: 'Listen',
                              sublabel: 'Capture a specimen',
                              accent: secondColor,
                              iconColor: textcolor,
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => RecordPage()),
                                );
                                loadStatistics();
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _actionCard(
                              context,
                              icon: Icons.menu_book_outlined,
                              label: 'Archive',
                              sublabel: 'Browse all entries',
                              accent: textcolor,
                              iconColor: Colors.white,
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => FileManagement()),
                                );
                                loadStatistics();
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 26),

                      // Categories
                      _sectionLabel('BROWSE THE ARCHIVE'),
                      const SizedBox(height: 10),

                      _categoryCard(
                        context,
                        icon: Icons.female_rounded,
                        title: 'Female',
                        subtitle:
                            '$femaleFiles ${femaleFiles == 1 ? 'specimen' : 'specimens'}',
                        count: femaleFiles,
                        accent: ducklingYellowDark,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  FileManagement(initialFilter: 'Female'),
                            ),
                          );
                          loadStatistics();
                        },
                      ),

                      const SizedBox(height: 10),

                      _categoryCard(
                        context,
                        icon: Icons.male_rounded,
                        title: 'Male',
                        subtitle:
                            '$maleFiles ${maleFiles == 1 ? 'specimen' : 'specimens'}',
                        count: maleFiles,
                        accent: textcolor,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  FileManagement(initialFilter: 'Male'),
                            ),
                          );
                          loadStatistics();
                        },
                      ),

                      const SizedBox(height: 10),

                      _categoryCard(
                        context,
                        icon: Icons.help_outline_rounded,
                        title: 'Undetermined',
                        subtitle:
                            '$undeterminedFiles ${undeterminedFiles == 1 ? 'specimen' : 'specimens'}',
                        count: undeterminedFiles,
                        accent: textcolor.withValues(alpha: 0.5),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FileManagement(
                                  initialFilter: 'Undetermined'),
                            ),
                          );
                          loadStatistics();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _PondFab(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => RecordPage()),
          );
          loadStatistics();
        },
      ),
    );
  }

  // ===========================================================================
  // SMALL HELPERS
  // ===========================================================================

  Widget _sectionLabel(String label) {
    return Text(label, style: getCapsLabel(size: 11, opacity: 0.55));
  }

  // ===========================================================================
  // STATS CARD
  // ===========================================================================

  Widget _buildStatsCard() {
    return NeuBox(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          // Big total
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                totalFiles.toString(),
                style: getSerifHeading(size: 48),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  totalFiles == 1 ? 'specimen' : 'specimens',
                  style: GoogleFonts.quicksand(
                    fontSize: 13,
                    color: textcolor.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Mini breakdown row
          Row(
            children: [
              _miniStat(
                label: 'Female',
                value: femaleFiles,
                accent: ducklingYellowDark,
              ),
              _miniDivider(),
              _miniStat(
                label: 'Male',
                value: maleFiles,
                accent: textcolor,
              ),
              _miniDivider(),
              _miniStat(
                label: 'Undet.',
                value: undeterminedFiles,
                accent: textcolor.withValues(alpha: 0.5),
              ),
            ],
          ),

          // Progress bar
          if (totalFiles > 0) ...[
            const SizedBox(height: 18),
            Container(
              height: 0.5,
              color: textcolor.withValues(alpha: 0.12),
            ),
            const SizedBox(height: 14),
            _buildProgressBar(),
          ],

          const SizedBox(height: 14),
          Container(
            height: 0.5,
            color: textcolor.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.water_drop_outlined,
                size: 13,
                color: textcolor.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  totalFiles == 0
                      ? 'Start listening to build your tally.'
                      : 'Pull down to refresh.',
                  style: GoogleFonts.quicksand(
                    fontSize: 11,
                    color: textcolor.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat({
    required String label,
    required int value,
    required Color accent,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value.toString(),
            style: GoogleFonts.quicksand(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: getCapsLabel(size: 9, opacity: 0.55),
          ),
        ],
      ),
    );
  }

  Widget _miniDivider() {
    return Container(
      width: 0.5,
      height: 28,
      color: textcolor.withValues(alpha: 0.12),
    );
  }

  // ===========================================================================
  // PROGRESS BAR
  // ===========================================================================

  Widget _buildProgressBar() {
    if (totalFiles == 0) return const SizedBox.shrink();

    final malePercent = (maleFiles / totalFiles);
    final femalePercent = (femaleFiles / totalFiles);
    final undeterminedPercent = (undeterminedFiles / totalFiles);
    final classifiedPct =
        ((maleFiles + femaleFiles) / totalFiles * 100).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('CLASSIFIED', style: getCapsLabel(size: 10, opacity: 0.55)),
            Text(
              '$classifiedPct%',
              style: GoogleFonts.quicksand(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textcolor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            color: textcolor.withValues(alpha: 0.08),
            height: 7,
            child: Row(
              children: [
                if (femaleFiles > 0)
                  Flexible(
                    flex: (femalePercent * 1000).toInt(),
                    child: Container(color: ducklingYellowDark),
                  ),
                if (maleFiles > 0)
                  Flexible(
                    flex: (malePercent * 1000).toInt(),
                    child: Container(color: textcolor),
                  ),
                if (undeterminedFiles > 0)
                  Flexible(
                    flex: (undeterminedPercent * 1000).toInt(),
                    child: Container(
                      color: textcolor.withValues(alpha: 0.25),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _legendItem(ducklingYellowDark, 'Female', femalePercent),
            _legendItem(textcolor, 'Male', malePercent),
            _legendItem(
              textcolor.withValues(alpha: 0.3),
              'Undet.',
              undeterminedPercent,
            ),
          ],
        ),
      ],
    );
  }

  Widget _legendItem(Color color, String label, double percent) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '$label ${(percent * 100).toStringAsFixed(0)}%',
          style: GoogleFonts.quicksand(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: textcolor.withValues(alpha: 0.65),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // ACTION CARD (quick action)
  // ===========================================================================

  Widget _actionCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String sublabel,
    required Color accent,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: textcolor.withValues(alpha: 0.10),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: textcolor.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(icon, size: 28, color: iconColor),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: getSerifHeading(size: 18),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              textAlign: TextAlign.center,
              style: GoogleFonts.quicksand(
                fontSize: 10.5,
                color: textcolor.withValues(alpha: 0.55),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // CATEGORY CARD (browse the archive)
  // ===========================================================================

  Widget _categoryCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required int count,
    required Color accent,
    required VoidCallback onTap,
  }) {
    final disabled = count == 0;
    return Opacity(
      opacity: disabled ? 0.55 : 1.0,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: textcolor.withValues(alpha: 0.10),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: textcolor.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.18),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: getSerifHeading(size: 20),
                        ),
                        if (count > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.3),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              count.toString(),
                              style: GoogleFonts.quicksand(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      count == 0 ? 'No specimens yet' : subtitle,
                      style: GoogleFonts.quicksand(
                        fontSize: 11,
                        color: textcolor.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: textcolor.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// FLOATING ACTION BUTTON — pond-themed
// =============================================================================

class _PondFab extends StatelessWidget {
  final VoidCallback onTap;
  const _PondFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
          color: secondColor,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.7),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: ducklingYellowDark.withValues(alpha: 0.5),
              blurRadius: 20,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: textcolor.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_rounded, color: textcolor, size: 22),
            const SizedBox(width: 8),
            Text(
              'Listen',
              style: GoogleFonts.quicksand(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textcolor,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}