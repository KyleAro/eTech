import 'package:flutter/material.dart' ;
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'file_management.dart';
import 'upload.dart';
import 'recordPage.dart';
import 'package:firebase_core/firebase_core.dart';

 const buttonColor = Colors.black;
 const backgroundColor = Color.fromARGB(255, 126, 70, 6);


final List<Widget> pages = [
      FileManagement(),  
      Mainpage(),
      Upload(),
    ];

 
class Mainpage extends StatefulWidget {
  const Mainpage ({super.key});

  @override
  State<Mainpage> createState() => _MainpageState();
}


class _MainpageState extends State<Mainpage> {

  int _currentIndex = 1;

  final List<Widget> _pages = [
    FileManagement(),
    RecordPage(),
    Upload(),
  ];
 @override
  Widget build(BuildContext context) {
    

    return Container(
      color:Color.fromARGB(255, 126, 70, 6) ,
    child:SafeArea(
      top: false,
      left: false,
      right: false,

      child: Scaffold(
      
      appBar: AppBar(
        backgroundColor: Color(0xFFF7EC59),
        title: 
          Text(
          'eTech',
          style: TextStyle(
            color: const Color.fromARGB(255, 0, 0, 0),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: CurvedNavigationBar(
        color: Color(0xFFF7EC59),
        index: 1,
        backgroundColor: Colors.transparent,
      onTap: (value){
        setState(() {
          _currentIndex = value;
        });
      },

      items: [
        Icon(
          _currentIndex == 1 ? Icons.folder : Icons.folder_outlined,
          size: 30,
          color: buttonColor,
        ),
        Icon(
          _currentIndex == 2 ? Icons.mic: Icons.mic_outlined,
          size: 30,
          color: buttonColor,
        ),
        Icon(
          _currentIndex == 3 ? Icons.backup : Icons.backup_outlined,
          size: 30,
          color: buttonColor,
        ),
        
      ],  
    ),     
      ),
    ),
    );
    
    
    
    
  }
}






























