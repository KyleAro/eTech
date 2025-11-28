import 'dart:typed_data';
import 'package:etech/pages/MainPage.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import '../../database/firebase_con.dart';
import '../../database/firestore_con.dart';

class ResultBottomSheet {
  static void show(
    BuildContext context, {
    required String prediction,
    required double confidence,
    Uint8List? rawBytes,
    String? baseName,
    bool isError = false,
    int? totalClips,
    int? maleClips,
    int? femaleClips,
    List<dynamic>? clipResults,
    bool showConfetti = true,
  }) {
    double malePercent = (totalClips != null && totalClips > 0 && maleClips != null)
        ? (maleClips / totalClips) * 100
        : 0.0;
    double femalePercent = (totalClips != null && totalClips > 0 && femaleClips != null)
        ? (femaleClips / totalClips) * 100
        : 0.0;

    Color primaryColor;
    Color secondaryColor;

    if (isError) {
      primaryColor = Colors.red[400]!;
      secondaryColor = Colors.red[100]!;
    } else {
      if (prediction.toLowerCase() == 'female') {
        primaryColor = Colors.pink[400]!;
        secondaryColor = Colors.pink[100]!;
      } else if (prediction.toLowerCase() == 'male') {
        primaryColor = Colors.blue[400]!;
        secondaryColor = Colors.blue[100]!;
      } else {
        primaryColor = Colors.grey[600]!;
        secondaryColor = Colors.grey[300]!;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        final FirebaseConnect storageService = FirebaseConnect();
        final FirestoreConnect firestoreService = FirestoreConnect();

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
          child: DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: isError 
                    ? const Color(0xFFFF8A80)  // Dark red for errors
                    : (prediction.toLowerCase() == 'female' 
                        ? const Color(0xFFFFC0CB)  // Dark purple/pink for female
                        : (prediction.toLowerCase() == 'male'
                            ? const Color(0xFFADD8E6)  // Dark blue for male
                            : const Color(0xFF1E1E1E))), // Default dark grey
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          // Drag handle
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 20),
                              decoration: BoxDecoration(
                                color: Colors.grey[700],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),

                          if (isError) ...[
                            // Error state
                            Container(
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.error_outline,
                                size: 80,
                                color: primaryColor,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              "An Error Occurred",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              prediction,
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () => Navigator.pop(context),
                                style: FilledButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: const Text('Close'),
                              ),
                            ),
                          ] else ...[
                            // Success state - Animation
                            if (prediction.toLowerCase() == "female")
                              Lottie.asset(
                                'assets/anim/girl.json',
                                width: 140,
                                height: 140,
                                repeat: true,
                              )
                            else if (prediction.toLowerCase() == "male")
                              Lottie.asset(
                                'assets/anim/boy.json',
                                width: 140,
                                height: 140,
                                repeat: true,
                              ),
                            const SizedBox(height: 16),

                            // Prediction text with badge
                            Text(
                              prediction,
                              style: TextStyle(
                                color: primaryColor,
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),

                            // Confidence Gauge Card
                            Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  children: [
                                    SizedBox(
                                      height: 180,
                                      child: SfRadialGauge(
                                        axes: <RadialAxis>[
                                          RadialAxis(
                                            minimum: 0,
                                            maximum: 100,
                                            showLabels: false,
                                            showTicks: false,
                                            startAngle: 180,
                                            endAngle: 0,
                                            radiusFactor: 0.95,
                                            axisLineStyle: AxisLineStyle(
                                              thickness: 0.2,
                                              color: Colors.grey[800],
                                              thicknessUnit: GaugeSizeUnit.factor,
                                            ),
                                            pointers: <GaugePointer>[
                                              RangePointer(
                                                value: confidence,
                                                width: 0.2,
                                                sizeUnit: GaugeSizeUnit.factor,
                                                gradient: SweepGradient(
                                                  colors: <Color>[
                                                    primaryColor.withOpacity(0.3),
                                                    primaryColor,
                                                  ],
                                                  stops: const <double>[0.25, 0.75],
                                                ),
                                                cornerStyle: CornerStyle.bothCurve,
                                              ),
                                            ],
                                            annotations: <GaugeAnnotation>[
                                              GaugeAnnotation(
                                                angle: 90,
                                                positionFactor: 0.1,
                                                widget: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      '${confidence.toStringAsFixed(1)}%',
                                                      style: TextStyle(
                                                        fontSize: 40,
                                                        fontWeight: FontWeight.bold,
                                                        color: primaryColor,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Confidence',
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        color: Colors.grey[400],
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Statistics Summary
                            if (totalClips != null && totalClips > 0) ...[
                              const SizedBox(height: 20),
                              Card(
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.analytics_outlined,
                                            color: const Color(0xFFFFD54F),
                                            size: 24,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Analysis Summary',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      _buildStatRow(
                                        icon: Icons.audiotrack,
                                        label: 'Total Clips',
                                        value: '$totalClips',
                                        color: const Color(0xFFFFD54F),
                                      ),
                                      const SizedBox(height: 16),
                                      _buildStatRow(
                                        icon: Icons.male,
                                        label: 'Male Clips',
                                        value: '${maleClips ?? 0}',
                                        subtitle: '${malePercent.toStringAsFixed(1)}%',
                                        color: Colors.blue[400]!,
                                      ),
                                      const SizedBox(height: 16),
                                      _buildStatRow(
                                        icon: Icons.female,
                                        label: 'Female Clips',
                                        value: '${femaleClips ?? 0}',
                                        subtitle: '${femalePercent.toStringAsFixed(1)}%',
                                        color: Colors.pink[400]!,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],

                            // Clip-by-Clip Details
                            if (clipResults != null && clipResults.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              Card(
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.list_alt,
                                            color: const Color(0xFFFFD54F),
                                            size: 24,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Clip-by-Clip Results',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      ...clipResults.asMap().entries.map((entry) {
                                        final index = entry.key;
                                        final clip = entry.value;
                                        final clipPrediction =
                                            clip['prediction'] ?? 'Unknown';
                                        final clipConfidence = clip['confidence'] ?? 0;
                                        final clipColor =
                                            clipPrediction.toLowerCase() == 'male'
                                                ? Colors.blue[400]
                                                : Colors.pink[400];

                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 12),
                                          child: Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[850],
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: clipColor!.withOpacity(0.3),
                                                width: 1,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 40,
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    color: clipColor.withOpacity(0.2),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      '${index + 1}',
                                                      style: TextStyle(
                                                        color: clipColor,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        clipPrediction,
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'Clip ${index + 1}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.grey[500],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: clipColor.withOpacity(0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(20),
                                                  ),
                                                  child: Text(
                                                    '$clipConfidence%',
                                                    style: TextStyle(
                                                      color: clipColor,
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ],
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(height: 24),

                            // Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.close),
                                    label: const Text('Close'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      side: BorderSide(color: Colors.grey[700]!),
                                    ),
                                  ),
                                ),
                                if (!isError && rawBytes != null && baseName != null) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: FilledButton.icon(
                                      onPressed: () async {
                                        String fileName = "${prediction}_$baseName.wav";

                                        String downloadUrl =
                                            await storageService.uploadBytes(
                                                rawBytes, fileName, prediction);

                                        await firestoreService.savePrediction(
                                          prediction: prediction,
                                          confidence: confidence,
                                          downloadUrl: downloadUrl,
                                          filePath: baseName,
                                        );

                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text("Saved to Firebase!"),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );

                                        Navigator.pop(context);
                                      },
                                      icon: const Icon(Icons.cloud_upload),
                                      label: const Text('Save to Firebase'),
                                      style: FilledButton.styleFrom(
                                        padding:
                                            const EdgeInsets.symmetric(vertical: 16),
                                        backgroundColor: Colors.green[600],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Confetti overlay
                    if (!isError && showConfetti)
                      IgnorePointer(
                        child: Lottie.asset(
                          'assets/anim/confetti.json',
                          width: double.infinity,
                          height: 500,
                          repeat: false,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  static Widget _buildStatRow({
    required IconData icon,
    required String label,
    required String value,
    String? subtitle,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 24,
            color: color,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}