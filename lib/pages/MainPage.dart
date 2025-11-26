import 'package:etech/pages/upload.dart';
import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';

import 'file_management.dart';
import 'recordPage.dart';
import 'merge.dart';

const backgroundColor = Color.fromARGB(255, 240, 234, 159);
const secondColor =Color(0xFFF7EC59);
const textcolor = Color(0xFF0F6C7C);

class Mainpage extends StatefulWidget {
  const Mainpage({super.key});

  @override
  State<Mainpage> createState() => _MainpageState();
}

class _MainpageState extends State<Mainpage> {
  int _currentIndex = 1;
  int _previousIndex = 1;

  final List<Widget> _pages = [
    FileManagement(),
    RecordPage(),
    GenderPredictorApp(),
    MyRecordingsPage(),
    
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: secondColor,
        title: const Text(
          'eTech',
          style: TextStyle(
            color: textcolor,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
         ),
      body: AnimatedSwitcher(
        duration: Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          final isForward = _currentIndex >= _previousIndex;
          final offsetAnimation = Tween<Offset>(
            begin: Offset(isForward ? 1 : -1, 0),
            end: Offset(0, 0),
          ).animate(animation);

          return SlideTransition(
            position: offsetAnimation,
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
        child: Container(
          key: ValueKey<int>(_currentIndex),
          child: _pages[_currentIndex],
        ),
      ),
      bottomNavigationBar: Container(
        color: secondColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10),
          child: GNav(
            backgroundColor: secondColor,
            color: Colors.black,
            activeColor: Colors.white,
            tabBackgroundColor: const Color.fromARGB(255, 0, 0, 0),
            gap: 10,
            padding: EdgeInsets.all(16),
            selectedIndex: _currentIndex,
            onTabChange: (index) {
              setState(() {
                _previousIndex = _currentIndex;
                _currentIndex = index;
              });
            },
            tabs: const [
              GButton(
                icon: Icons.folder,
                text: 'Files',
              ),
              GButton(
                icon: Icons.mic,
                text: 'Record',
              ),
              GButton(
                icon: Icons.upload,
                text: 'Upload',
              ),
              GButton(
                icon: Icons.hourglass_bottom,
                text: 'For Test',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
