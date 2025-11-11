
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

    final Offset distance = isPressed ? Offset(10, 10) : Offset(28, 28);
    final double blur = isPressed ? 10.0 : 30.0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: const Color.fromARGB(255, 223, 148, 10),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(255, 117, 96, 32),
            blurRadius: blur,
            offset: -distance,
            inset: isPressed,
          ),
          BoxShadow(
            color: const Color.fromARGB(134, 235, 163, 81),
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

// text style of the app bar tit
// for app bar theme

