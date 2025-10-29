import 'package:etech/style/mainpage_style.dart';
import 'package:flutter/material.dart';
import 'MainPage.dart';



class Upload extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Text(
          'Upload Page',
          style: getTitleTextStyle(context).copyWith(
            fontSize: 30, 
            color: Colors.white), 
      ),
      ),
    );
  }
}