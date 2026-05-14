import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:etech/style/mainpage_style.dart';
import 'package:etech/style/ripple_background.dart';

// ============================================================================
// DATA MODELS
// ============================================================================

/// The full SVM result handed to the bottom sheet.
/// Wrap whatever your Python pipeline returns in this — it's a thin shape
/// so the UI doesn't have to care about pipeline internals.
class PredictionResult {
  final String gender; // "male" | "female"
  final double confidence; // 0.0–1.0
  final int specimenNumber;
  final DateTime recordedAt;
  final Duration duration;
  final List<ClipPrediction> clips;

  const PredictionResult({
    required this.gender,
    required this.confidence,
    required this.specimenNumber,
    required this.recordedAt,
    required this.duration,
    required this.clips,
  });

  bool get isFemale => gender.toLowerCase() == 'female';
}

class ClipPrediction {
  final int index;
  final String gender;
  final double confidence;

  const ClipPrediction({
    required this.index,
    required this.gender,
    required this.confidence,
  });
}

// ============================================================================
// PUBLIC ENTRY POINT
// ============================================================================

/// Call this from your record / upload flows once SVM inference completes.
///
///   await showResultBottomSheet(context, result: myPrediction);
Future<void> showResultBottomSheet(
  BuildContext context, {
  required PredictionResult result,
  VoidCallback? onSaveToArchive,
  VoidCallback? onDiscard,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: textcolor.withValues(alpha: 0.25),
    builder: (_) => ResultBottomSheet(
      result: result,
      onSaveToArchive: onSaveToArchive,
      onDiscard: onDiscard,
    ),
  );
}

// ============================================================================
// THE SHEET
// ============================================================================

class ResultBottomSheet extends StatelessWidget {
  final PredictionResult result;
  final VoidCallback? onSaveToArchive;
  final VoidCallback? onDiscard;

  const ResultBottomSheet({
    super.key,
    required this.result,
    this.onSaveToArchive,
    this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.88;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: const BoxDecoration(
          gradient: pondGradient,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Stack(
            children: [
              // Subtle ripples behind everything
              Positioned.fill(
                child: RippleBackground(
                  centerAlignment: const Alignment(0, -0.6),
                ),
              ),

              // Scrollable content
              SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: media.padding.bottom + 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Handle(),
                      _Header(result: result),
                      const SizedBox(height: 20),
                      _AvatarBlock(result: result),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _ConfidenceBar(value: result.confidence),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _StatsRow(result: result),
                      ),
                      const SizedBox(height: 24),
                      if (result.clips.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _ClipBreakdown(clips: result.clips),
                        ),
                        const SizedBox(height: 24),
                      ],
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _Actions(
                          onSaveToArchive: onSaveToArchive,
                          onDiscard: onDiscard,
                          context: context,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PIECES
// ============================================================================

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 14),
      width: 44,
      height: 4,
      decoration: BoxDecoration(
        color: textcolor.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final PredictionResult result;
  const _Header({required this.result});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Text(
            'SPECIMEN ${result.specimenNumber.toString().padLeft(3, '0')}',
            style: getCapsLabel(size: 11, opacity: 0.55),
          ),
          const SizedBox(height: 6),
          Text(
            'Field Note',
            style: getSerifHeading(size: 28),
          ),
        ],
      ),
    );
  }
}

class _AvatarBlock extends StatelessWidget {
  final PredictionResult result;
  const _AvatarBlock({required this.result});

  @override
  Widget build(BuildContext context) {
    // Icon fallback — swap to Lottie when assets land.
    // Female = warm yellow ring (duckling), Male = teal ring (drake-ish).
    final accent = result.isFemale ? secondColor : textcolor;
    final iconColor = result.isFemale ? ducklingYellowDark : Colors.white;
    final ringFill = result.isFemale
        ? secondColor.withValues(alpha: 0.85)
        : textcolor.withValues(alpha: 0.92);

    return Column(
      children: [
        Container(
          width: 116,
          height: 116,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ringFill,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.7),
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.35),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            result.isFemale ? Icons.female_rounded : Icons.male_rounded,
            size: 58,
            color: iconColor,
          ),
        ),
        const SizedBox(height: 14),
        // Success badge + gender label, side-by-side
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: successGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              result.isFemale ? 'Female' : 'Male',
              style: getSerifHeading(size: 32, color: textcolor),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  final double value; // 0.0–1.0
  const _ConfidenceBar({required this.value});

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).clamp(0, 100);
    return NeuBox(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('CONFIDENCE', style: getCapsLabel(size: 10, opacity: 0.55)),
              Text(
                '${pct.toStringAsFixed(1)}%',
                style: GoogleFonts.quicksand(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textcolor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Container(
                  height: 10,
                  color: textcolor.withValues(alpha: 0.08),
                ),
                FractionallySizedBox(
                  widthFactor: value.clamp(0.0, 1.0),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          secondColor,
                          ducklingYellowDark,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final PredictionResult result;
  const _StatsRow({required this.result});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'DURATION',
            value: _fmtDuration(result.duration),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: 'CLIPS',
            value: result.clips.isEmpty ? '—' : '${result.clips.length}',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: 'RECORDED',
            value: _fmtDate(result.recordedAt),
          ),
        ),
      ],
    );
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return NeuBox(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        children: [
          Text(label, style: getCapsLabel(size: 9, opacity: 0.5)),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.quicksand(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: textcolor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClipBreakdown extends StatelessWidget {
  final List<ClipPrediction> clips;
  const _ClipBreakdown({required this.clips});

  @override
  Widget build(BuildContext context) {
    return NeuBox(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('CLIP BREAKDOWN',
                  style: getCapsLabel(size: 10, opacity: 0.55)),
              Text(
                '${clips.length} windows',
                style: GoogleFonts.quicksand(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: textcolor.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...clips.map((c) => _ClipRow(clip: c)),
        ],
      ),
    );
  }
}

class _ClipRow extends StatelessWidget {
  final ClipPrediction clip;
  const _ClipRow({required this.clip});

  @override
  Widget build(BuildContext context) {
    final isFemale = clip.gender.toLowerCase() == 'female';
    final dotColor = isFemale ? secondColor : textcolor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 38,
            child: Text(
              '#${clip.index.toString().padLeft(2, '0')}',
              style: GoogleFonts.quicksand(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textcolor.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              isFemale ? 'Female' : 'Male',
              style: GoogleFonts.quicksand(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: textcolor,
              ),
            ),
          ),
          // mini confidence bar
          SizedBox(
            width: 80,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(
                    height: 5,
                    color: textcolor.withValues(alpha: 0.08),
                  ),
                  FractionallySizedBox(
                    widthFactor: clip.confidence.clamp(0.0, 1.0),
                    child: Container(
                      height: 5,
                      color: dotColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 38,
            child: Text(
              '${(clip.confidence * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: GoogleFonts.quicksand(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: textcolor.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final VoidCallback? onSaveToArchive;
  final VoidCallback? onDiscard;
  final BuildContext context;
  const _Actions({
    required this.context,
    this.onSaveToArchive,
    this.onDiscard,
  });

  @override
  Widget build(BuildContext _) {
    return Row(
      children: [
        Expanded(
          child: _SecondaryButton(
            label: 'Discard',
            onTap: () {
              onDiscard?.call();
              Navigator.of(context).pop();
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _PrimaryButton(
            label: 'Save to Archive',
            onTap: () {
              onSaveToArchive?.call();
              Navigator.of(context).pop();
            },
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: textcolor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: textcolor.withValues(alpha: 0.25),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.quicksand(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SecondaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: textcolor.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.quicksand(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: textcolor.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}