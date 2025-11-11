import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:firebase_core/firebase_core.dart';
import 'package:etech/firebase_options.dart'; 
import 'pages/MainPage.dart'; 
import 'package:firebase_app_check/firebase_app_check.dart';


void main() async {
  
   WidgetsFlutterBinding.ensureInitialized(); 
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.playIntegrity,
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'eTech Audio Recorder',
      theme: ThemeData(

      scaffoldBackgroundColor: backgroundColor,

  ),
      
      home: const Mainpage(), 
    );
  }
}
