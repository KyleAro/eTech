import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseConnect {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  
  Future<String> uploadToPrediction(String path, String gender) async {
    try {
      
      // Choose folder based on gender
      final folderName =
          gender.toLowerCase() == 'male' ? 'Male Ducklings' : 'Female Ducklings';

      final storageRef = _storage.ref().child(folderName);

      // Extract the original file name
      final originalName = path.split('/').last;

      // Add gender prefix to filename
      final fileName = "${gender}_$originalName";

      // Full path reference to the file in storage
      final fileRef = storageRef.child(fileName);

      // Upload the file
      await fileRef.putFile(File(path));

      // Get and return the file's download URL
      final downloadUrl = await fileRef.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print("🔥 Firebase Storage upload error: $e");
      return '';

      
    }
  }
}