import 'package:etech/pages/upload.dart';
import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:google_nav_bar/google_nav_bar.dart';

import 'file_management.dart';
import 'recordPage.dart';
import 'merge.dart' hide textcolor;
import 'package:etech/style/mainpage_style.dart';
import '../style/ripple_background.dart';

class Mainpage extends StatefulWidget {
  const Mainpage({super.key});

  @override
  State<Mainpage> createState() => _MainpageState();
}

class _MainpageState extends State<Mainpage> {
  int _currentIndex = 1;
  int _previousIndex = 1;

  // Same 4 pages as before — no logic changes.
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
      // Important: Scaffold itself is transparent so the gradient shows through.
      backgroundColor: Colors.transparent,
      appBar: _buildAppBar(),
      body: Container(
        // The pond gradient is applied at the Scaffold body level —
        // every page inside _pages automatically inherits it.
        decoration: const BoxDecoration(gradient: pondGradient),
        child: Stack(
          children: [
            // Ripple pattern sits behind everything, very subtle.
            const Positioned.fill(child: RippleBackground(opacity: 0.10)),

            // Page content with the slide-fade transition you already had.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                final isForward = _currentIndex >= _previousIndex;
                final offsetAnimation = Tween<Offset>(
                  begin: Offset(isForward ? 1 : -1, 0),
                  end: Offset.zero,
                ).animate(animation);

                return SlideTransition(
                  position: offsetAnimation,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: Container(
                key: ValueKey<int>(_currentIndex),
                child: _pages[_currentIndex],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ---------------------------------------------------------------------------
  // APP BAR
  // ---------------------------------------------------------------------------
  // Frosted, semi-transparent — sits over the gradient so the ripples
  // peek through at the top.

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white.withOpacity(0.4),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      // Subtle hairline divider at the bottom of the app bar.
      shape: Border(
        bottom: BorderSide(
          color: textcolor.withOpacity(0.08),
          width: 0.5,
        ),
      ),
      title: Text(
        'eTech',
        style: GoogleFonts.cormorantGaramond(
          fontSize: 24,
          fontWeight: FontWeight.w500,
          color: textcolor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BOTTOM NAV
  // ---------------------------------------------------------------------------
  // Kept GNav since it's already in your pubspec — just restyled to match
  // the pond aesthetic. The 4 tab structure is identical to before.

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        border: Border(
          top: BorderSide(
            color: textcolor.withOpacity(0.08),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: GNav(
            backgroundColor: Colors.transparent,
            color: textcolor.withOpacity(0.5),
            activeColor: Colors.white,
            tabBackgroundColor: textcolor,
            gap: 10,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            iconSize: 22,
            textStyle: GoogleFonts.quicksand(
              fontWeight: FontWeight.w500,
              color: Colors.white,
              fontSize: 13,
            ),
            selectedIndex: _currentIndex,
            onTabChange: (index) {
              setState(() {
                _previousIndex = _currentIndex;
                _currentIndex = index;
              });
            },
            tabs: const [
              GButton(icon: Icons.water_drop_outlined, text: 'Files'),
              GButton(icon: Icons.mic_none_rounded, text: 'Record'),
              GButton(icon: Icons.auto_awesome_outlined, text: 'Upload'),
              GButton(icon: Icons.menu_book_outlined, text: 'Archive'),
            ],
          ),
        ),
      ),
    );
  }
}