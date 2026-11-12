import 'package:flutter/material.dart';

import '../models/person.dart';
import 'app_widgets.dart';
import 'person_widgets.dart';

class PersonNode extends StatelessWidget {
  final Person person;
  final bool editing;
  final bool selected;
  final VoidCallback onOpen, onRelationships;
  const PersonNode({
    super.key,
    required this.person,
    this.editing = false,
    required this.selected,
    required this.onOpen,
    required this.onRelationships,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: selected ? mint : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: selected ? forest : const Color(0xFFD4E4DB),
        width: selected ? 2 : 1,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Expanded(
          child: InkWell(
            onTap: onOpen,
            onLongPress: onRelationships,
            child: Padding(
              padding: EdgeInsets.fromLTRB(8, editing ? 24 : 8, 8, 0),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    PersonAvatar(person, radius: 16),
                    const SizedBox(height: 4),
                    Flexible(
                      child: Text(
                        person.id < 0
                            ? 'Hồ sơ trắng tmp-${-person.id}'
                            : person.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      'Sinh: ${person.birthLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (editing)
          const SizedBox(height: 24)
        else
          SizedBox(
            height: 28,
            width: double.infinity,
            child: TextButton(
              onPressed: onRelationships,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Quan hệ', style: const TextStyle(fontSize: 11)),
            ),
          ),
      ],
    ),
  );
}
