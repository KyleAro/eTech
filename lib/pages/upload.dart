import 'package:etech/pages/MainPage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
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

      // Get all audio files
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

        // Check LocalPredictions collection first
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
          // Check if it's an undetermined file
          final undeterminedSnapshot = await firestore
              .collection('Undetermined')
              .where('file_name', isEqualTo: fileName)
              .limit(1)
              .get();

          if (undeterminedSnapshot.docs.isNotEmpty || fileName.contains('Undetermined')) {
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
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFFFD54F),
          secondary: const Color(0xFFFFD54F),
          surface: const Color(0xFF1E1E1E),
          background: const Color(0xFF121212),
        ),
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'My Recordings',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: loadStatistics,
              tooltip: 'Refresh',
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: loadStatistics,
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Statistics Card
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Statistics',
                        style: TextStyle(
                          color: textcolor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isLoading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _statItem(
                                icon: Icons.audiotrack,
                                label: 'Total',
                                value: totalFiles.toString(),
                                color: const Color(0xFFFFD54F),
                              ),
                              _statItem(
                                icon: Icons.male,
                                label: 'Male',
                                value: maleFiles.toString(),
                                color: Colors.blue[400]!,
                              ),
                              _statItem(
                                icon: Icons.female,
                                label: 'Female',
                                value: femaleFiles.toString(),
                                color: Colors.pink[400]!,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Progress bar
                          if (totalFiles > 0) ...[
                            const Divider(),
                            const SizedBox(height: 12),
                            _buildProgressBar(),
                            const SizedBox(height: 12),
                          ],
                          const Divider(),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  totalFiles == 0
                                      ? 'Start recording or uploading to see statistics'
                                      : 'Pull down to refresh statistics',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Quick Actions Section
                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      color: textcolor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _actionCard(
                          context,
                          icon: Icons.mic,
                          label: 'Record Audio',
                          color: const Color(0xFFFFD54F),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => RecordPage()),
                            );
                            loadStatistics();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _actionCard(
                          context,
                          icon: Icons.folder_open,
                          label: 'View All',
                          color: const Color(0xFF64B5F6),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => FileManagement()),
                            );
                            loadStatistics();
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Categories Section
                  const Text(
                    'Browse Categories',
                    style: TextStyle(
                      color: textcolor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  _categoryCard(
                    context,
                    icon: Icons.boy,
                    title: 'Male Recordings',
                    subtitle: '$maleFiles recording${maleFiles != 1 ? 's' : ''}',
                    count: maleFiles,
                    color: Colors.blue[400]!,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FileManagement(initialFilter: 'Male'),
                        ),
                      );
                      loadStatistics();
                    },
                  ),

                  const SizedBox(height: 12),

                  _categoryCard(
                    context,
                    icon: Icons.girl,
                    title: 'Female Recordings',
                    subtitle: '$femaleFiles recording${femaleFiles != 1 ? 's' : ''}',
                    count: femaleFiles,
                    color: Colors.pink[400]!,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FileManagement(initialFilter: 'Female'),
                        ),
                      );
                      loadStatistics();
                    },
                  ),

                  const SizedBox(height: 12),

                  _categoryCard(
                    context,
                    icon: Icons.question_mark,
                    title: 'Undetermined',
                    subtitle: '$undeterminedFiles recording${undeterminedFiles != 1 ? 's' : ''}',
                    count: undeterminedFiles,
                    color: Colors.grey[600]!,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FileManagement(initialFilter: 'Undetermined'),
                        ),
                      );
                      loadStatistics();
                    },
                  ),

                  const SizedBox(height: 80), // Space for FAB
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => RecordPage()),
            );
            loadStatistics();
          },
          icon: const Icon(Icons.mic),
          label: const Text('Record'),
          backgroundColor: const Color(0xFFFFD54F),
          foregroundColor: Colors.black,
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    if (totalFiles == 0) return const SizedBox.shrink();

    final malePercent = (maleFiles / totalFiles);
    final femalePercent = (femaleFiles / totalFiles);
    final undeterminedPercent = (undeterminedFiles / totalFiles);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Classification Progress',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${((maleFiles + femaleFiles) / totalFiles * 100).toStringAsFixed(0)}% Classified',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                if (maleFiles > 0)
                  Flexible(
                    flex: (malePercent * 100).toInt(),
                    child: Container(color: Colors.blue[400]),
                  ),
                if (femaleFiles > 0)
                  Flexible(
                    flex: (femalePercent * 100).toInt(),
                    child: Container(color: Colors.pink[400]),
                  ),
                if (undeterminedFiles > 0)
                  Flexible(
                    flex: (undeterminedPercent * 100).toInt(),
                    child: Container(color: Colors.grey[700]),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendItem(Colors.blue[400]!, 'Male', malePercent),
            const SizedBox(width: 16),
            _legendItem(Colors.pink[400]!, 'Female', femalePercent),
            const SizedBox(width: 16),
            _legendItem(Colors.grey[700]!, 'Undetermined', undeterminedPercent),
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
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label (${(percent * 100).toStringAsFixed(0)}%)',
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }

  Widget _actionCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: color,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _categoryCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: count > 0 ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: count > 0 ? color : Colors.grey[700],
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: count > 0 ? null : Colors.grey[700],
                          ),
                        ),
                        if (count > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              count.toString(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count > 0 ? subtitle : 'No recordings yet',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: count > 0 ? Colors.grey[600] : Colors.grey[800],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          color: color,
          size: 32,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }
}