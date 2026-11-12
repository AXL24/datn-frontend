import 'package:flutter/material.dart';

import 'app_widgets.dart';

/// Inflate the positioned card by 22px: buttons stay inside its hit-test bounds.
/// Graph layout and relationship endpoints still use the original card rect.
class PersonNodeControls extends StatelessWidget {
  final Widget child;
  final int personId;
  final VoidCallback? onParents, onLeftSpouse, onRightSpouse, onChild;
  const PersonNodeControls({
    super.key,
    required this.child,
    required this.personId,
    this.onParents,
    this.onLeftSpouse,
    this.onRightSpouse,
    this.onChild,
  });

  Widget button(String direction, String label, VoidCallback onTap) => Tooltip(
    message: label,
    child: Semantics(
      label: label,
      button: true,
      child: Material(
        color: forest,
        elevation: 1,
        shape: const CircleBorder(
          side: BorderSide(color: Colors.white, width: 2),
        ),
        child: InkWell(
          key: ValueKey('add-$direction-$personId'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox.square(
            dimension: 44,
            child: Icon(Icons.add_rounded, size: 24, color: Colors.white),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: Padding(padding: const EdgeInsets.all(22), child: child),
      ),
      if (onParents != null)
        Align(
          alignment: Alignment.topCenter,
          child: button('parents', 'Thêm cha/mẹ', onParents!),
        ),
      if (onLeftSpouse != null)
        Align(
          alignment: Alignment.centerLeft,
          child: button('left', 'Thêm vợ/chồng bên trái', onLeftSpouse!),
        ),
      if (onRightSpouse != null)
        Align(
          alignment: Alignment.centerRight,
          child: button('right', 'Thêm vợ/chồng bên phải', onRightSpouse!),
        ),
      if (onChild != null)
        Align(
          alignment: Alignment.bottomCenter,
          child: button('child', 'Thêm con', onChild!),
        ),
    ],
  );
}
