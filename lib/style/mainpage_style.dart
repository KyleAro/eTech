import 'package:flutter/material.dart'hide BoxDecoration, BoxShadow;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_inset_box_shadow/flutter_inset_box_shadow.dart';

// custom font for all of the app in the app
TextStyle getTitleTextStyle(BuildContext context) {
  return GoogleFonts.quicksand( // change font
    
    fontWeight: FontWeight.w600,
    color: const Color.fromARGB(255, 255, 255, 255),
    letterSpacing: 5.0,
    shadows: <Shadow>[
      Shadow(offset: Offset(1, 1),
      blurRadius: 20.0 ,
      color: Colors.black)
    ],
    
  );
}

// this of for  neu box design
class NeuBox extends StatelessWidget {
  final Widget? child;
  final bool isPressed; 

  const NeuBox({
    super.key,
    required this.child,
    required this.isPressed, 
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = Color(0xFFF7EC59);
    final Offset distance = isPressed ? Offset(10, 10) : Offset(28, 28);
    final double blur = isPressed ? 20.0 : 30.0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: backgroundColor,
        boxShadow: [
          BoxShadow(
            color: backgroundColor,
            blurRadius: blur,
            offset: -distance,
            inset: isPressed,
          ),
          BoxShadow(
            color: const Color.fromARGB(225, 167, 196, 82),
            blurRadius: blur,
            offset: distance,
            inset: isPressed,
          ),
        ],
      ),
      padding: const EdgeInsets.all(25),
      child: Center(child: child),
    );
  }
}

// text style of the app bar title



TextStyle titleTextStyle = TextStyle(
  fontSize: 18,
  
  color: Colors.black,
);

// for app bar theme

