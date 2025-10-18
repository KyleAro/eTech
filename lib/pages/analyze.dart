import 'package:flutter/material.dart';
import 'package:etech/style/mainpage_style.dart';


class AudioAnalyzer extends StatelessWidget {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF7EC59), 
      body: Center(
        child: Text(
          'Audio Analyzer Page',
          style: getTitleTextStyle(context).copyWith(
            fontSize: 20, 
            color: Colors.white), 
      ),
      ),
    );
  }
}