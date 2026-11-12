import 'package:flutter/material.dart';

import '../models/person.dart';
import 'app_widgets.dart';

class PersonAvatar extends StatelessWidget {
  final Person person;
  final double radius;
  const PersonAvatar(this.person, {super.key, this.radius = 24});
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: mint,
    child: Icon(Icons.person_outline, size: radius * 1.15, color: forest),
  );
}

class ProfileField extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const ProfileField(this.label, this.value, this.icon, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: forest, size: 22),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Color(0xFF667E73)),
              ),
              const SizedBox(height: 5),
              SelectableText(
                value,
                style: const TextStyle(fontSize: 16, color: ink, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
