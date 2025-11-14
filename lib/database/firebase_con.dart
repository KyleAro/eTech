import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseConnect {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<String> uploadBytes(Uint8List data, String fileName, String gender) async {
    try {
      final folderName =
          gender.toLowerCase() == 'male' ? 'Male Ducklings' : 'Female Ducklings';
      final ref = _storage.ref().child('$folderName/$fileName');

      await ref.putData(data);

      final downloadUrl = await ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print("🔥 Firebase Storage uploadBytes error: $e");
      return '';
    }
  }
}