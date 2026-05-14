import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ============================================================================
// POND & RIPPLES PALETTE
// ============================================================================
// These constants keep the same names as before so the rest of your app
// (recordPage, upload, result_botsheet, etc.) keeps working without changes.

/// Pond mist — the lightest tone, used at the top of the gradient.
const backgroundColor = Color(0xFFE8F4F0);

/// Shallow water — the warm yellow becomes a duckling accent now.
/// Renamed in spirit but the variable name stays so imports don't break.
const secondColor = Color(0xFFF7EC59);

/// Deep teal — primary text and icon color across the app.
const textcolor = Color(0xFF0F6C7C);

// Extra tones for the new design — additive, doesn't break existing imports.
const pondShallow = Color(0xFFC8E4D8);
const pondDeep = Color(0xFFA8D4C2);
const ducklingYellowDark = Color(0xFFD4C840);
const beakOrange = Color(0xFFFF9F1C);
const successGreen = Color(0xFF4ADE80);
const recordRed = Color(0xFFEF4444);

/// The full pond gradient — apply this to a Container's decoration
/// to get the signature background.
const pondGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [backgroundColor, pondShallow, pondDeep],
  stops: [0.0, 0.5, 1.0],
);

// ============================================================================
// TEXT STYLES
// ============================================================================

/// Custom font for app bar titles — kept the same signature as before
/// so MainPage.dart and any other callers don't need to change.
TextStyle getTitleTextStyle(BuildContext context) {
  return GoogleFonts.quicksand(
    fontWeight: FontWeight.w600,
    color: textcolor,
    letterSpacing: 3.0,
    shadows: const [
      Shadow(
        offset: Offset(0, 1),
        blurRadius: 8.0,
        color: Color(0x1A0F6C7C),
      ),
    ],
  );
}

/// Serif font for naturalist-style headings (Specimen, Archive, etc).
/// Use this on screens where you want the "field journal" feel.
TextStyle getSerifHeading({double size = 26, Color? color}) {
  return GoogleFonts.cormorantGaramond(
    fontSize: size,
    fontWeight: FontWeight.w500,
    color: color ?? textcolor,
    letterSpacing: -0.3,
    height: 1.1,
  );
}

/// Small caps label — used for "TODAY", "RECORDING", "CONFIDENCE" tags.
TextStyle getCapsLabel({double size = 10, double opacity = 0.5}) {
  return GoogleFonts.quicksand(
    fontSize: size,
    fontWeight: FontWeight.w500,
    color: textcolor.withOpacity(opacity),
    letterSpacing: 1.5,
  );
}

// ============================================================================
// FROSTED CARD
// ============================================================================
// Replaces the old NeuBox. Same constructor name so existing usage in your
// pages keeps working — but it now renders as a translucent "pond water"
// card instead of a neumorphic bubble.

class NeuBox extends StatelessWidget {
  final Widget? child;
  final bool isPressed;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;

  const NeuBox({
    super.key,
    required this.child,
    this.isPressed = false,
    this.padding,
    this.borderRadius = 18,
  });

  @override
  Widget build(BuildContext context) {
    // Pressed state = slightly darker frost + tighter shadow,
    // giving subtle tactile feedback without going neumorphic.
    final fill = isPressed
        ? Colors.white.withOpacity(0.35)
        : Colors.white.withOpacity(0.5);

    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: textcolor.withOpacity(0.10),
          width: 0.5,
        ),
        boxShadow: isPressed
            ? []
            : [
                BoxShadow(
                  color: textcolor.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Center(child: child),
    );
  }
}

// ============================================================================
// FROSTED CHIP — small pill for filters, tags, status indicators
// ============================================================================

class FrostedChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const FrostedChip({
    super.key,
    required this.label,
    this.isActive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? textcolor : Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(11),
          border: isActive
              ? null
              : Border.all(color: textcolor.withOpacity(0.10), width: 0.5),
        ),
        child: Text(
          label,
          style: GoogleFonts.quicksand(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isActive ? Colors.white : textcolor,
          ),
        ),
      ),
    );
  }
}