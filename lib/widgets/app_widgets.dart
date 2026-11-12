import 'dart:math' as math;

import 'package:flutter/material.dart';

const forest = Color(0xFF17694F);
const mint = Color(0xFFE9F5EE);
const ink = Color(0xFF183C35);

class PageShell extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? bottom;
  final bool back;
  final bool showAppBar;
  final double maxWidth;
  const PageShell({
    super.key,
    required this.title,
    required this.child,
    this.bottom,
    this.back = true,
    this.showAppBar = true,
    this.maxWidth = 540,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F9F5),
    appBar: showAppBar
        ? AppBar(
            automaticallyImplyLeading: back,
            title: Text(title),
            centerTitle: true,
          )
        : null,
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    ),
    bottomNavigationBar: bottom,
  );
}

class Surface extends StatelessWidget {
  final Widget child;
  const Surface({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFDFEAE3)),
    ),
    child: child,
  );
}

class ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData icon;
  const ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon = Icons.arrow_forward_rounded,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 20),
      label: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Text(label),
      ),
    ),
  );
}

class Notice extends StatelessWidget {
  final String? text;
  final bool warning;
  const Notice(this.text, {super.key, this.warning = false});
  @override
  Widget build(BuildContext context) => text == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Semantics(
            liveRegion: true,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: warning
                    ? const Color(0xFFFFF3DB)
                    : const Color(0xFFFFEDEA),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                text!,
                style: TextStyle(
                  color: warning
                      ? const Color(0xFF72531B)
                      : const Color(0xFF943C31),
                ),
              ),
            ),
          ),
        );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  const SectionTitle(this.title, this.icon, {super.key, this.subtitle});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: mint,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: forest, size: 23),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: ink,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF667E73),
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

InputDecoration fieldDecoration(String label, IconData icon, {String? hint}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
    );
String? requiredName(String? v) => v == null || v.trim().isEmpty
    ? 'Vui lòng nhập thông tin này.'
    : v.trim().length > 150
    ? 'Tối đa 150 ký tự.'
    : null;
String displayDate(DateTime d) =>
    '${d.toLocal().day.toString().padLeft(2, '0')}/${d.toLocal().month.toString().padLeft(2, '0')}/${d.toLocal().year}';

/// Decorative illustration only. It never depicts actual genealogy data.
class FamilyIllustration extends StatelessWidget {
  final double height;
  const FamilyIllustration({super.key, this.height = 200});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _TreePainter()),
    ),
  );
}

class _TreePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height * .50);
    final scale = math.min(size.width / 300, size.height / 210);
    canvas.scale(scale);
    final paint = Paint();
    canvas.drawCircle(
      const Offset(0, 0),
      95,
      paint..color = const Color(0xFFE3F1DE),
    );
    for (var i = 0; i < 22; i++) {
      final angle = i * math.pi * 2 / 22;
      canvas.save();
      canvas.translate(math.cos(angle) * 82, math.sin(angle) * 77);
      canvas.rotate(angle);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 43, height: 19),
        paint
          ..color = i.isEven
              ? const Color(0xFFAFD39E)
              : const Color(0xFF84B98C),
      );
      canvas.restore();
    }
    paint
      ..color = const Color(0xFF648D65)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(0, 80), const Offset(0, -60), paint);
    for (final y in [-48.0, 4.0, 55.0]) {
      canvas.drawLine(Offset(-32, y), Offset(32, y), paint);
      for (final x in [-32.0, 32.0]) {
        final point = Offset(x, y);
        canvas.drawCircle(point, 25, paint..color = const Color(0xFFF8FCF5));
        canvas.drawCircle(
          point,
          20,
          paint
            ..color = x < 0 ? const Color(0xFFD8E7F1) : const Color(0xFFF4DAD1),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: point + const Offset(0, 13),
            width: 27,
            height: 19,
          ),
          paint
            ..color = x < 0 ? const Color(0xFF4E8C86) : const Color(0xFFD38B74),
        );
        canvas.drawCircle(
          point + const Offset(0, -2),
          11,
          paint..color = const Color(0xFFF4CFA6),
        );
        canvas.drawArc(
          Rect.fromCenter(
            center: point + const Offset(0, -5),
            width: 22,
            height: 21,
          ),
          math.pi,
          math.pi,
          false,
          paint
            ..color = y < 0 ? const Color(0xFFCDD1C5) : const Color(0xFF695448),
        );
        canvas.drawCircle(
          point + const Offset(-4, -1),
          1.2,
          paint..color = ink,
        );
        canvas.drawCircle(point + const Offset(4, -1), 1.2, paint);
      }
      paint.color = const Color(0xFF648D65);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
