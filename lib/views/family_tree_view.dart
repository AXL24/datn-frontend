import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/graph_controller.dart';
import '../models/access_session.dart';
import '../models/person.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/graph_layout_service.dart';
import '../widgets/app_widgets.dart';
import '../widgets/person_node.dart';
import '../widgets/person_node_controls.dart';
import '../widgets/relationship_painter.dart';
import 'join_family_screen.dart';
import 'person_detail_screen.dart';
import 'graph_draft_actions.dart';
import 'add_relationship_screen.dart';

/// MH06 VIEW. Kept alive by the Family tab's IndexedStack.
class FamilyTreeView extends StatefulWidget {
  final GraphController? sharedGraph;
  final bool active;
  final ApiService api;
  final StorageService storage;
  final int familyId;
  final AccessSession? initialSession;
  const FamilyTreeView({
    super.key,
    this.sharedGraph,
    this.active = true,
    required this.api,
    required this.storage,
    required this.familyId,
    this.initialSession,
  });
  @override
  State<FamilyTreeView> createState() => _FamilyTreeViewState();
}

class _FamilyTreeViewState extends State<FamilyTreeView> {
  late final controller =
      widget.sharedGraph ??
      GraphController(
        widget.api,
        widget.storage,
        widget.familyId,
        initialSession: widget.initialSession,
      );
  final camera = TransformationController();
  Size viewport = Size.zero;
  GraphLayout? fittedLayout;
  Size fittedViewport = Size.zero;
  int? selectedId;
  double minScale = .05;

  @override
  void initState() {
    super.initState();
    if (controller.snapshot == null && !controller.dirty) controller.load();
  }

  @override
  void dispose() {
    camera.dispose();
    if (widget.sharedGraph == null) controller.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    if (!await resolveGraphDraft(context, controller) || !mounted) return;
    setState(() => selectedId = null);
    await controller.load();
  }

  Future<void> editMode() async {
    if (controller.editing) {
      if (!await resolveGraphDraft(context, controller) || !mounted) return;
      controller.editing = false;
      controller.rebuild();
    } else {
      if (!await ensureGraphEdit(context, controller) || !mounted) return;
      controller.editing = true;
      controller.rebuild();
    }
  }

  bool spouseOccupied(Person person, {required bool left}) {
    final x = controller.layout!.nodes[person.id]!.center.dx;
    return controller.draft!.spouses(person.id).any((id) {
      final sx = controller.layout!.nodes[id]!.center.dx;
      return left ? sx < x : sx >= x;
    });
  }

  Future<void> addRelationship(Person person, RelationshipEntry entry) async {
    if (controller.writeLocked ||
        !await ensureGraphEdit(context, controller) ||
        !mounted) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AddRelationshipScreen(
          graph: controller,
          anchor: person,
          entry: entry,
        ),
      ),
    );
  }

  Widget personCard(Person person, GraphLayout layout) {
    final canAdd = controller.editing && !controller.writeLocked;
    final card = PersonNode(
      key: ValueKey('person-node-${person.id}'),
      person: person,
      editing: controller.editing,
      selected: selectedId == person.id,
      onOpen: () => open(person),
      onRelationships: () => showRelationships(person),
    );
    return Positioned.fromRect(
      rect: controller.editing
          ? layout.nodes[person.id]!.inflate(22)
          : layout.nodes[person.id]!,
      child: !controller.editing
          ? card
          : PersonNodeControls(
              personId: person.id,
              onParents:
                  canAdd &&
                      (!controller.draft!.hasRole(person.id, 'FATHER') ||
                          !controller.draft!.hasRole(person.id, 'MOTHER'))
                  ? () => addRelationship(person, RelationshipEntry.parents)
                  : null,
              onLeftSpouse: canAdd && !spouseOccupied(person, left: true)
                  ? () => addRelationship(person, RelationshipEntry.leftSpouse)
                  : null,
              onRightSpouse: canAdd && !spouseOccupied(person, left: false)
                  ? () => addRelationship(person, RelationshipEntry.rightSpouse)
                  : null,
              onChild: canAdd
                  ? () => addRelationship(person, RelationshipEntry.child)
                  : null,
              child: card,
            ),
    );
  }

  Widget tool(
    String label,
    IconData icon,
    VoidCallback? onTap, {
    bool active = false,
    int? count,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: active ? forest : Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(15),
      child: IconButton(
        tooltip: label,
        onPressed: onTap,
        color: active ? Colors.white : forest,
        icon: count == null
            ? Icon(icon)
            : Badge(
                label: Text('$count'),
                isLabelVisible: count > 0,
                child: Icon(icon),
              ),
      ),
    ),
  );

  void showGuide() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sơ đồ gia phả',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${controller.snapshot!.persons.length} người · ${controller.snapshot!.relationships.length} quan hệ (gồm bản nháp nếu có)',
            ),
            const SizedBox(height: 16),
            const Text(
              'Chạm thẻ để xem hồ sơ. Nhấn giữ hoặc bấm Quan hệ để xem các mối quan hệ.',
            ),
            const ListTile(
              leading: Icon(Icons.vertical_align_top),
              title: Text('Nút trên: thêm bố, mẹ hoặc bố mẹ'),
            ),
            const ListTile(
              leading: Icon(Icons.swap_horiz),
              title: Text('Hai bên: thêm vợ/chồng vào hướng còn trống'),
            ),
            const ListTile(
              leading: Icon(Icons.vertical_align_bottom),
              title: Text('Nút dưới: thêm con hoặc con chung'),
            ),
            const Text(
              'Tím: vợ/chồng. Xanh: nhánh cha mẹ–con. Nét đứt: quan hệ chưa lưu. Loại cha/mẹ nằm trong mục Quan hệ.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Các nút + chỉ hiện ở chế độ sửa. Lưu sơ đồ mới ghi bản nháp. Tải lại trang sẽ mất phần chưa lưu.',
            ),
          ],
        ),
      ),
    ),
  );

  void showPending() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Các thao tác chưa lưu',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                if (!controller.dirty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Chưa có thao tác mới.'),
                  ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c
                          in controller.draft?.commands ??
                              <Map<String, dynamic>>[])
                        ListTile(
                          title: Text(switch (c['type']) {
                            'ADD_PARENT' => 'Thêm cha/mẹ',
                            'ADD_PARENTS' => 'Thêm bố mẹ',
                            'ADD_CHILD' => 'Thêm con',
                            _ => 'Thêm vợ/chồng',
                          }),
                          subtitle: Text(
                            controller.draft!
                                .references(c)
                                .map((id) => id < 0 ? 'tmp-${-id}' : '#$id')
                                .join(' → '),
                          ),
                          trailing: IconButton(
                            tooltip: 'Hủy thao tác',
                            icon: const Icon(Icons.close),
                            onPressed: controller.writeLocked
                                ? null
                                : () {
                                    final problem = controller.draft!
                                        .removeCommand(c['commandId']);
                                    controller.error = problem;
                                    controller.rebuild();
                                  },
                          ),
                        ),
                    ],
                  ),
                ),
                Notice(controller.error),
                TextButton(
                  onPressed: controller.committing
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await resolveGraphDraft(this.context, controller);
                        },
                  child: const Text('Lưu / Bỏ / Hủy'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Đóng'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void fit(GraphLayout layout, Size size) {
    if (size.isEmpty) return;
    final available = Size(
      math.max(1, size.width - 72),
      math.max(1, size.height - 60),
    );
    final scale = math.min(
      1.0,
      math.min(
        available.width / layout.size.width,
        available.height / layout.size.height,
      ),
    );
    camera.value = Matrix4.identity()
      ..translateByDouble(
        (available.width - layout.size.width * scale) / 2,
        (available.height - layout.size.height * scale) / 2,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  Future<void> open(Person person) async {
    if (controller.committing) return;
    if (person.id < 0) {
      final remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Hồ sơ trắng tmp-${-person.id}'),
          content: Text(
            'Lưu sơ đồ trước để bổ sung thông tin hồ sơ.\n\nXóa cục bộ sẽ hủy các lệnh liên quan: ${controller.draft!.commandsFor(person.id).join(', ')}. Không xóa dữ liệu đã lưu.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Đóng'),
            ),
            TextButton(
              onPressed: controller.writeLocked
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Xóa hồ sơ tạm'),
            ),
          ],
        ),
      );
      if (remove == true && mounted) {
        controller.error = controller.draft!.removeTemporary(person.id);
        controller.rebuild();
      }
      return;
    }
    final before = widget.api.revision(widget.familyId);
    setState(() => selectedId = person.id);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PersonDetailScreen(
          api: widget.api,
          storage: widget.storage,
          familyId: widget.familyId,
          personId: person.id,
          initialSession: controller.session,
          fromTree: true,
          graph: controller,
        ),
      ),
    );
    // Person writes can change cards and edges. Keep camera, reload the snapshot.
    if (mounted &&
        !controller.dirty &&
        !controller.blocked &&
        before != widget.api.revision(widget.familyId)) {
      await controller.load();
      // Prevent auto-fit from replacing the user's camera when data is refreshed.
      fittedLayout = controller.layout;
      if (mounted) setState(() => selectedId = null);
    }
  }

  void showRelationships(Person person) {
    setState(() => selectedId = person.id);
    final tree = controller.snapshot!;
    final byId = {for (final p in tree.persons) p.id: p};
    final edges = tree.relationships
        .where(
          (r) => r.sourcePersonId == person.id || r.targetPersonId == person.id,
        )
        .toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(person.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (edges.isEmpty) const Text('Hồ sơ chưa có quan hệ.'),
            for (final r in edges)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  r.isSpouse
                      ? Icons.favorite_border
                      : Icons.account_tree_outlined,
                ),
                title: Text(
                  '${byId[r.sourcePersonId]!.name} — ${byId[r.targetPersonId]!.name}',
                ),
                subtitle: Text(
                  r.isSpouse
                      ? r.label
                      : '${byId[r.sourcePersonId]!.name}: ${r.label} (${byId[r.targetPersonId]!.name})',
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.busy) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.error != null && controller.snapshot == null) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Notice(controller.error),
            if (controller.needsJoin)
              ActionButton(
                label: 'Nhập lại mã gia phả',
                icon: Icons.key_outlined,
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => JoinFamilyScreen(
                      api: widget.api,
                      storage: widget.storage,
                      expectedFamilyId: widget.familyId,
                    ),
                  ),
                ),
              )
            else
              ActionButton(
                label: 'Thử tải lại',
                icon: Icons.refresh,
                onPressed: reload,
              ),
          ],
        );
      }
      final tree = controller.snapshot, layout = controller.layout;
      if (tree == null || layout == null) return const SizedBox.shrink();
      return Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (widget.active) viewport = constraints.biggest;
                minScale = math.min(
                  .05,
                  math.min(
                    viewport.width / layout.size.width,
                    viewport.height / layout.size.height,
                  ),
                );
                if (widget.active &&
                    (fittedLayout != layout || fittedViewport != viewport)) {
                  fittedLayout = layout;
                  fittedViewport = viewport;
                  final requestedSize = viewport;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted &&
                        widget.active &&
                        controller.layout == layout &&
                        viewport == requestedSize) {
                      fit(layout, requestedSize);
                    }
                  });
                }
                return Stack(
                  children: [
                    Positioned.fill(
                      child: tree.persons.isEmpty
                          ? const Center(
                              child: Text('Gia phả chưa có thành viên.'),
                            )
                          : InteractiveViewer(
                              key: const ValueKey('tree-canvas'),
                              transformationController: camera,
                              constrained: false,
                              alignment: Alignment.topLeft,
                              boundaryMargin: const EdgeInsets.all(1000),
                              minScale: minScale,
                              maxScale: 3,
                              child: SizedBox(
                                width: layout.size.width,
                                height: layout.size.height,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: RepaintBoundary(
                                        child: CustomPaint(
                                          painter: RelationshipPainter(
                                            layout,
                                            selectedId,
                                          ),
                                        ),
                                      ),
                                    ),
                                    for (final person in tree.persons)
                                      personCard(person, layout),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    if (controller.error != null || layout.hasParentCycle)
                      Positioned(
                        top: 8,
                        left: 8,
                        right: 72,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: viewport.height * .3,
                          ),
                          child: SingleChildScrollView(
                            child: Notice(
                              controller.error ?? 'Dữ liệu cha mẹ có vòng lặp. Cần kiểm tra dữ liệu.',
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 12,
                      top: 12,
                      bottom: 12,
                      width: 48,
                      child: Align(
                        alignment: const Alignment(0, -0.25),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              tool(
                                controller.editing
                                    ? 'Về xem'
                                    : 'Chỉnh sửa sơ đồ',
                                controller.editing
                                    ? Icons.visibility_outlined
                                    : Icons.edit_outlined,
                                controller.committing ? null : editMode,
                                active: controller.editing,
                              ),
                              if (controller.editing) ...[
                                tool(
                                  controller.committing
                                      ? 'Đang lưu…'
                                      : 'Lưu sơ đồ',
                                  Icons.save_outlined,
                                  controller.writeLocked || !controller.dirty
                                      ? null
                                      : () => saveGraph(context, controller),
                                  active:
                                      controller.dirty && !controller.blocked,
                                ),
                                tool(
                                  'Bản nháp (${controller.draft?.commands.length ?? 0})',
                                  Icons.list_alt_outlined,
                                  controller.committing ? null : showPending,
                                  count: controller.draft?.commands.length ?? 0,
                                ),
                              ],
                              tool(
                                'Làm mới sơ đồ',
                                Icons.refresh,
                                controller.committing ? null : reload,
                              ),
                              tool(
                                'Hướng dẫn sơ đồ',
                                Icons.help_outline,
                                showGuide,
                              ),
                              tool(
                                'Vừa màn hình',
                                Icons.center_focus_strong,
                                () => fit(layout, viewport),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 12,
                      right: 76,
                      child: Row(
                        children: [
                          tool(
                            'Quay lại danh sách gia phả',
                            Icons.arrow_back,
                            controller.committing
                                ? null
                                : () => Navigator.maybePop(context),
                          ),
                          if (controller.editing)
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: 8,
                                  bottom: 8,
                                ),
                                child: Material(
                                  color: mint,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 7,
                                    ),
                                    child: Text(
                                      controller.blocked
                                          ? 'Cần đối chiếu'
                                          : (controller.dirty
                                                ? '${controller.draft!.commands.length} thao tác chưa lưu'
                                                : 'Đang chỉnh sửa'),
                                      style: const TextStyle(
                                        color: forest,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const _TreeLegend(),
        ],
      );
    },
  );
}

class _TreeLegend extends StatelessWidget {
  const _TreeLegend();

  Widget item(String label, Color color, {bool dashed = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 20,
        child: Row(
          children: [
            for (var i = 0; i < (dashed ? 3 : 1); i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(child: Container(height: 2, color: color)),
            ],
          ],
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 11, color: ink)),
    ],
  );

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('tree-edge-legend'),
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: const BoxDecoration(
      color: Color(0xFFF4F9F5),
      border: Border(top: BorderSide(color: Color(0xFFDFEAE3))),
    ),
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 6,
      children: [
        item('Vợ/chồng', const Color(0xFF9B599A)),
        item('Cha mẹ → con', forest),
        item('Nét đứt: chưa lưu', ink, dashed: true),
      ],
    ),
  );
}
