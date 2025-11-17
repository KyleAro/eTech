import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class LoadingScreen extends StatelessWidget {
  final String message;
  final String animationAsset;
  final Color backgroundColor;
  final Color textColor;

  const LoadingScreen({
    Key? key,
    this.message = 'Please wait...',
    this.animationAsset = 'assets/anim/loading.json',
    this.backgroundColor = const Color(0xFFF7EC59),
    this.textColor = const Color(0xFF0F6C7C),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lottie Animation
            Lottie.asset(
              animationAsset,
              width: 100,
              height: 100,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                color: textColor,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
