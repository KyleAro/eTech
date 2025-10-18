import 'package:flutter/material.dart';
import 'pages/MainPage.dart';
void main() {
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
      scaffoldBackgroundColor: Color(0xFFF7EC59),
  ),
      home: Mainpage(),
    );
  }
}
