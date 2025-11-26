import 'dart:typed_data';
import 'package:etech/pages/MainPage.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../database/firebase_con.dart';
import '../../database/firestore_con.dart';

class ResultBottomSheet {
  static void show(
    BuildContext context, {
    required String prediction,
    required double confidence,
    Uint8List? rawBytes, // Audio bytes to save
    String? baseName,    // Base name for the file
    bool isError = false,
  }) {
    Color bgColor;
    Color textColor = Colors.black87;

    if (isError) {
      bgColor = const Color(0xFFFF8A80);
      textColor = Colors.white;
    } else {
      if (prediction.toLowerCase() == 'female') {
        bgColor = const Color(0xFFFFC0CB);
      } else if (prediction.toLowerCase() == 'male') {
        bgColor = const Color(0xFFADD8E6);
      } else {
        bgColor = Colors.grey[900]!;
        textColor = Colors.white;
      }
    }

    bool showConfetti = !isError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        final FirebaseConnect storageService = FirebaseConnect();
        final FirestoreConnect firestoreService = FirestoreConnect();

        return FractionallySizedBox(
          heightFactor: 0.55,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isError) ...[
                      const Text(
                        "An Error Occurred",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        prediction,
                        style: const TextStyle(color: Colors.white70, fontSize: 18),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Lottie.asset(
                        'assets/anim/error.json',
                        width: 160,
                        height: 160,
                        repeat: true,
                      ),
                    ] else ...[
                      if (prediction.toLowerCase() == "female")
                        Lottie.asset(
                          'assets/anim/girl.json',
                          width: 160,
                          height: 160,
                          repeat: true,
                        )
                      else if (prediction.toLowerCase() == "male")
                        Lottie.asset(
                          'assets/anim/boy.json',
                          width: 160,
                          height: 160,
                          repeat: true,
                        ),
                      Text(
                        prediction,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Confidence: ${confidence.toStringAsFixed(2)}%",
                        style: TextStyle(color: textColor, fontSize: 24),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 25),
                    // --- Save Button ---
                    if (!isError && rawBytes != null && baseName != null)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                        ),
                        onPressed: () async {
                          String fileName = "${prediction}_$baseName.wav";

                          // Upload audio to Firebase Storage
                          String downloadUrl = await storageService.uploadBytes(rawBytes, fileName, prediction);

                          // Save record to Firestore
                          await firestoreService.savePrediction(
                            prediction: prediction,
                            confidence: confidence,
                            downloadUrl: downloadUrl,
                            filePath: baseName,
                          );

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Saved to Firebase!")),
                          );

                          Navigator.pop(context); // Close bottom sheet
                        },
                        child: const Text("Save", style: TextStyle(color: Colors.white)),
                      ),
                  ],
                ),
                if (!isError && showConfetti)
                  Lottie.asset(
                    'assets/anim/confetti.json',
                    width: 500,
                    height: 500,
                    repeat: false,
                    onLoaded: (composition) {
                      Future.delayed(composition.duration, () {
                        // Confetti stops automatically
                      });
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
