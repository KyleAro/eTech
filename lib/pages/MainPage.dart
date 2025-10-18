import 'package:etech/pages/analyze.dart';
import 'package:etech/pages/enhance.dart';
import 'package:flutter/material.dart' ;
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'file_management.dart';
import 'upload.dart';
import 'recordPage.dart';

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

  int _currentIndex = 2;

  final List<Widget> _pages = [
    AudioAnalyzer(),
    FileManagement(),
    RecordPage(),
    Upload(),
    AudioEnhancer(),
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
        backgroundColor: Color.fromARGB(255, 126, 70, 6),
        title: 
          Text(
          'eTech',
          style: TextStyle(
            color: const Color.fromARGB(255, 255, 255, 255),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: CurvedNavigationBar(
        color: Color.fromARGB(255, 126, 70, 6),
        index: 2,
        backgroundColor: Colors.transparent,
      onTap: (value){
        setState(() {
          _currentIndex = value;
        });
      },
      items: [
        Icon(
          _currentIndex == 0 ? Icons.screen_search_desktop_rounded : Icons.screen_search_desktop_outlined,
          size: 30,
          color: Color.fromARGB(255, 255, 255, 255),
        ),
        Icon(
          _currentIndex == 1 ? Icons.folder : Icons.folder_outlined,
          size: 30,
          color: Color.fromARGB(255, 255, 255, 255),
        ),
        Icon(
          _currentIndex == 2 ? Icons.mic: Icons.mic_outlined,
          size: 30,
          color: Color.fromARGB(255, 255, 255, 255),
        ),
        Icon(
          _currentIndex == 3 ? Icons.backup : Icons.backup_outlined,
          size: 30,
          color: Color.fromARGB(255, 255, 255, 255),
        ),
        Icon(
          _currentIndex == 4 ? Icons.auto_awesome : Icons.auto_awesome_outlined,
          size: 30,
          color: Color.fromARGB(255, 255, 255, 255),
        ),
      ],  
    ),     
      ),
    ),
    );
    
    
    
    
  }
}






























