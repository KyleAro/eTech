import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class Upload extends StatelessWidget {
  const Upload({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F6C7C), 
      body: Center(
        child: Lottie.asset(
          "assets/anim/confetti.json",   
          width: 1000,
          height: 2000,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
