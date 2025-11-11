// lib/services/firestore_connect.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreConnect {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Saves prediction details to Firestore.
  Future<void> savePrediction({
    required String prediction,
    required double confidence,
    required String downloadUrl,
    required String filePath,
  }) async {
    
    try {
      final collectionName =
          prediction.toLowerCase() == 'male' ? 'Male Ducklings' : 'Female Ducklings';
      final category = "${prediction} Ducklings";
      final originalName = filePath.split('/').last;
      final renamedFile = "${prediction}_$originalName";

      await _firestore.collection(collectionName).doc(renamedFile).set({
        'File_Name': renamedFile,
        'Category': category,
        'Previous Prediction': 'Undetermined Ducklings',
        'Final Prediction': prediction,
        'Confidence_Percentage': confidence,
        'Url': downloadUrl,
        'Timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print("✅ Firestore document saved successfully!");
    } catch (e) {
      print("🔥 Firestore save error: $e");
    }
  }
}
