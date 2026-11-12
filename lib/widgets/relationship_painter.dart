import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/graph_layout_service.dart';
import 'app_widgets.dart';

/// Parent kinds remain on real edges in the relationship panel, not shared lines.
class RelationshipPainter extends CustomPainter {
  final GraphLayout layout;
  final int? selectedId;
  RelationshipPainter(this.layout, this.selectedId);
  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in layout.strokes) {
      final highlighted = selectedId != null && stroke.touches(selectedId!);
      final color = stroke.kind == StrokeKind.spouse
          ? const Color(0xFF9B599A)
          : forest;
      final paint = Paint()
        ..color = selectedId == null || highlighted
            ? color
            : color.withValues(alpha: .24)
        ..strokeWidth = highlighted ? 2.8 : 1.8
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final points = stroke.points;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      // A shared segment stays solid if it also represents a saved edge.
      if (stroke.relationships.isNotEmpty &&
          stroke.relationships.every((r) => r.id < 0)) {
        for (final metric in path.computeMetrics()) {
          for (double at = 0; at < metric.length; at += 10) {
            canvas.drawPath(
              metric.extractPath(at, math.min(at + 6, metric.length)),
              paint,
            );
          }
        }
      } else {
        canvas.drawPath(path, paint);
      }
      if (stroke.kind == StrokeKind.child ||
          stroke.kind == StrokeKind.fallback) {
        final end = points.last;
        final direction = (end - points[points.length - 2]).direction;
        final arrow = Path()
          ..moveTo(
            end.dx - 8 * math.cos(direction - .45),
            end.dy - 8 * math.sin(direction - .45),
          )
          ..lineTo(end.dx, end.dy)
          ..lineTo(
            end.dx - 8 * math.cos(direction + .45),
            end.dy - 8 * math.sin(direction + .45),
          );
        canvas.drawPath(arrow, paint);
      }
    }
    for (final joint in layout.junctions) {
      final highlighted =
          selectedId == null ||
          joint.relationships.any(
            (r) =>
                r.sourcePersonId == selectedId ||
                r.targetPersonId == selectedId,
          );
      canvas.drawCircle(
        joint.position,
        2.8,
        Paint()..color = highlighted ? forest : forest.withValues(alpha: .24),
      );
    }
  }

  @override
  bool shouldRepaint(RelationshipPainter oldDelegate) =>
      layout != oldDelegate.layout || selectedId != oldDelegate.selectedId;
}
