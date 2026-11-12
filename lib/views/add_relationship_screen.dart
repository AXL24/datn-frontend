import 'package:flutter/material.dart';

import '../controllers/graph_controller.dart';
import '../models/person.dart';
import '../widgets/app_widgets.dart';

String personLabel(Person p) =>
    '${p.id < 0 ? 'Hồ sơ trắng tmp-${-p.id}' : p.name} · ${p.id < 0 ? 'chưa lưu' : '#${p.id}'} · ${p.birthLabel}';
String roleLabel(String? v) => v == 'FATHER' ? 'Cha' : 'Mẹ';
String kindLabel(String? v) => switch (v) {
  'BIOLOGICAL' => 'ruột',
  'ADOPTIVE' => 'nuôi',
  'STEP' => 'kế',
  _ => 'chưa chọn',
};

enum RelationshipEntry { parents, leftSpouse, rightSpouse, child }

class AddRelationshipScreen extends StatefulWidget {
  final GraphController graph;
  final Person anchor;
  final RelationshipEntry entry;
  const AddRelationshipScreen({
    super.key,
    required this.graph,
    required this.anchor,
    required this.entry,
  });
  @override
  State<AddRelationshipScreen> createState() => _AddRelationshipScreenState();
}

class _AddRelationshipScreenState extends State<AddRelationshipScreen> {
  String? type, role, otherRole, kind, otherKind;
  int? selected, partner;
  bool existing = false;
  String? error;
  late final epoch = widget.graph.epoch;
  late final draft = widget.graph.draft!;
  List<Person> get people => draft.snapshot.persons;
  Person get anchor => widget.anchor;
  @override
  void initState() {
    super.initState();
    type = switch (widget.entry) {
      RelationshipEntry.child => 'CHILD',
      RelationshipEntry.leftSpouse || RelationshipEntry.rightSpouse => 'SPOUSE',
      RelationshipEntry.parents =>
        !draft.hasRole(anchor.id, 'FATHER') ? 'FATHER' : 'MOTHER',
    };
  }

  String get title => switch (widget.entry) {
    RelationshipEntry.parents => 'Thêm cha/mẹ',
    RelationshipEntry.child => 'Thêm con',
    _ => 'Thêm vợ/chồng',
  };

  Future<void> pick() async {
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Chọn hồ sơ trong gia phả'),
            content: SizedBox(
              width: 420,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Tìm tên hoặc ID',
                    ),
                    onChanged: (v) => setLocal(() => query = v.toLowerCase()),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final p in people.where(
                          (p) =>
                              p.id != anchor.id &&
                              personLabel(p).toLowerCase().contains(query),
                        ))
                          ListTile(
                            title: Text(personLabel(p)),
                            onTap: () => Navigator.pop(context, p.id),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy'),
              ),
            ],
          ),
        );
      },
    );
    if (mounted && chosen != null) setState(() => selected = chosen);
  }

  Widget choice(
    String label,
    String? value,
    Map<String, String> values,
    void Function(String?) change,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label-$type-$partner'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: values.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: (v) => setState(() => change(v)),
    ),
  );
  Future<void> submit() async {
    if (widget.graph.writeLocked ||
        widget.graph.epoch != epoch ||
        widget.graph.draft != draft) {
      return;
    }
    if (type == null ||
        (type != 'SPOUSE' && kind == null) ||
        (type == 'PARENTS' && otherKind == null) ||
        (type == 'CHILD' &&
            (role == null ||
                (partner != null &&
                    (otherRole == null || otherKind == null)))) ||
        (type != 'PARENTS' && existing && selected == null)) {
      setState(() => error = 'Chọn đầy đủ hồ sơ, vai trò và loại quan hệ.');
      return;
    }
    if (type == 'CHILD' && partner != null && role == otherRole) {
      setState(() => error = 'Hai cha mẹ phải có hai vai trò khác nhau.');
      return;
    }
    final other = existing
        ? personLabel(people.firstWhere((p) => p.id == selected))
        : 'Hồ sơ trắng mới';
    final preview = switch (type) {
      'SPOUSE' => '${personLabel(anchor)} ↔ $other: vợ/chồng.',
      'FATHER' || 'MOTHER' =>
        '$other làm ${roleLabel(type)} ${kindLabel(kind)} của ${personLabel(anchor)}.',
      'PARENTS' =>
        'Tạo hai hồ sơ trắng làm cha ${kindLabel(kind)} và mẹ ${kindLabel(otherKind)} của ${personLabel(anchor)}. Không tạo quan hệ vợ/chồng.',
      _ =>
        '${personLabel(anchor)} làm ${roleLabel(role)} ${kindLabel(kind)} của $other.${partner == null ? '' : '\n${personLabel(people.firstWhere((p) => p.id == partner))} làm ${roleLabel(otherRole)} ${kindLabel(otherKind)} của $other.'}',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận thêm quan hệ'),
        content: SingleChildScrollView(
          child: Text(
            '$preview\n\nChỉ thêm vào bản nháp, chưa ghi dữ liệu. Sau khi Lưu sơ đồ, không thể gỡ riêng quan hệ; muốn loại bỏ phải xóa một hồ sơ cùng các quan hệ liên quan. Không gộp hồ sơ hoặc tự thêm quan hệ khác.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Thêm vào bản nháp'),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        widget.graph.writeLocked ||
        widget.graph.epoch != epoch) {
      return;
    }
    try {
      final a = draft.ref(anchor.id);
      if (type == 'PARENTS') {
        final father = draft.newPerson(), mother = draft.newPerson();
        draft.add({
          'type': 'ADD_PARENTS',
          'child': a,
          'father': draft.ref(father),
          'mother': draft.ref(mother),
          'fatherKind': kind,
          'motherKind': otherKind,
        });
      } else {
        final target = existing ? selected! : draft.newPerson(),
            b = draft.ref(target);
        switch (type) {
          case 'SPOUSE':
            draft.add({'type': 'ADD_SPOUSE', 'person': a, 'spouse': b});
            widget.graph.placeSpouse(
              anchor.id,
              target,
              left: widget.entry == RelationshipEntry.leftSpouse,
            );
          case 'FATHER' || 'MOTHER':
            draft.add({
              'type': 'ADD_PARENT',
              'child': a,
              'parent': b,
              'role': type,
              'kind': kind,
            });
          case 'CHILD':
            draft.add({
              'type': 'ADD_CHILD',
              'child': b,
              'parents': [
                {'person': a, 'role': role, 'kind': kind},
                if (partner != null)
                  {
                    'person': draft.ref(partner!),
                    'role': otherRole,
                    'kind': otherKind,
                  },
              ],
            });
        }
      }
      widget.graph.changed();
      Navigator.pop(context);
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spouses = draft.spouses(anchor.id);
    return PageShell(
      title: title,
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Text(
            personLabel(anchor),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 16),
          Notice(error),
          if (widget.entry == RelationshipEntry.parents) ...[
            const Text(
              'Bổ sung cho hồ sơ này',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in <String, String>{
                  if (!draft.hasRole(anchor.id, 'FATHER')) 'FATHER': 'Bố',
                  if (!draft.hasRole(anchor.id, 'MOTHER')) 'MOTHER': 'Mẹ',
                  if (!draft.hasRole(anchor.id, 'FATHER') &&
                      !draft.hasRole(anchor.id, 'MOTHER'))
                    'PARENTS': 'Bố mẹ',
                }.entries)
                  ChoiceChip(
                    label: Text(option.value),
                    selected: type == option.key,
                    onSelected: (_) => setState(() {
                      type = option.key;
                      kind = null;
                      otherKind = null;
                      error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (type == 'PARENTS')
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Tạo hai hồ sơ trắng mới. Không tự thêm quan hệ vợ/chồng.',
              ),
            ),
          if (type != null && type != 'PARENTS') ...[
            const Text(
              'Hồ sơ được thêm',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Tạo hồ sơ trắng'),
                  selected: !existing,
                  onSelected: (_) => setState(() => existing = false),
                ),
                ChoiceChip(
                  label: const Text('Chọn người có sẵn'),
                  selected: existing,
                  onSelected: (_) => setState(() => existing = true),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (existing)
              OutlinedButton(
                onPressed: pick,
                child: Text(
                  selected == null
                      ? 'Chọn hồ sơ'
                      : personLabel(people.firstWhere((p) => p.id == selected)),
                ),
              ),
          ],
          if (type == 'CHILD') ...[
            DropdownButtonFormField<int>(
              key: ValueKey('partner-$type'),
              initialValue: partner ?? 0,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Nhánh con'),
              items: [
                DropdownMenuItem(
                  value: 0,
                  child: Text('Con của ${anchor.name}'),
                ),
                for (final id in spouses)
                  DropdownMenuItem(
                    value: id,
                    child: Text(
                      'Con chung với ${people.firstWhere((p) => p.id == id).name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => partner = v == 0 ? null : v),
            ),
            const SizedBox(height: 16),
            choice('Vai trò của người đang chọn', role, {
              'FATHER': 'Cha',
              'MOTHER': 'Mẹ',
            }, (v) => role = v),
          ],
          if (type != null && type != 'SPOUSE')
            choice(
              type == 'PARENTS' ? 'Loại quan hệ của bố' : 'Loại quan hệ cha/mẹ',
              kind,
              {'BIOLOGICAL': 'Ruột', 'ADOPTIVE': 'Nuôi', 'STEP': 'Kế'},
              (v) => kind = v,
            ),
          if (type == 'CHILD' && partner != null)
            choice('Vai trò của phối ngẫu', otherRole, {
              'FATHER': 'Cha',
              'MOTHER': 'Mẹ',
            }, (v) => otherRole = v),
          if (type == 'PARENTS' || (type == 'CHILD' && partner != null))
            choice(
              type == 'PARENTS'
                  ? 'Loại quan hệ của mẹ'
                  : 'Loại quan hệ của phối ngẫu',
              otherKind,
              {'BIOLOGICAL': 'Ruột', 'ADOPTIVE': 'Nuôi', 'STEP': 'Kế'},
              (v) => otherKind = v,
            ),
          const SizedBox(height: 16),
          ActionButton(label: 'Xem trước quan hệ', onPressed: submit),
        ],
      ),
    );
  }
}
