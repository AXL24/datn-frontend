import 'package:flutter/material.dart';

import '../controllers/family_controller.dart';
import '../controllers/graph_controller.dart';
import 'graph_draft_actions.dart';
import '../models/access_session.dart';
import '../models/family.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_widgets.dart';
import 'edit_code_screen.dart';
import 'join_family_screen.dart';
import 'people_view.dart';
import 'family_tree_view.dart';

class FamilyInfoScreen extends StatefulWidget {
  final ApiService api;
  final StorageService storage;
  final int familyId;
  final AccessSession? initialSession;
  final String? initialWarning;
  const FamilyInfoScreen({
    super.key,
    required this.api,
    required this.storage,
    required this.familyId,
    this.initialSession,
    this.initialWarning,
  });
  @override
  State<FamilyInfoScreen> createState() => _FamilyInfoScreenState();
}

class _FamilyInfoScreenState extends State<FamilyInfoScreen> {
  late final controller = FamilyController(widget.api, widget.storage);
  late final graph = GraphController(
    widget.api,
    widget.storage,
    widget.familyId,
    initialSession: widget.initialSession,
  );
  bool allowPop = false;
  final editForm = GlobalKey<FormState>();
  final name = TextEditingController();
  final description = TextEditingController();
  int selectedTab = 0, editVersion = 0;
  bool membersOpened = false, treeOpened = false;
  bool editing = false, conflict = false, editRejected = false;
  String? editWarning;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() => controller.open(
    widget.familyId,
    initialSession: controller.session ?? widget.initialSession,
  );

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    graph.dispose();
    controller.dispose();
    super.dispose();
  }

  bool get dirty {
    final family = controller.family;
    if (family == null) return false;
    final oldDescription = family.description ?? '';
    return name.text != family.name || description.text != oldDescription;
  }

  Future<bool> discardEdit() async {
    if (!editing) return true;
    if (dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Bỏ thay đổi?'),
          content: const Text('Tên và mô tả chưa lưu sẽ bị bỏ.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Tiếp tục sửa'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Bỏ thay đổi'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return false;
    }
    setState(() {
      editing = false;
      conflict = false;
      editWarning = null;
      editRejected = false;
    });
    return true;
  }

  void startEditing(Family family) {
    name.text = family.name;
    description.text = family.description ?? '';
    setState(() {
      editVersion = family.version;
      editing = true;
      conflict = false;
      editRejected = false;
      editWarning = null;
    });
  }

  Future<void> requestEditing() async {
    final hadDraft = graph.dirty || graph.blocked;
    if (!await resolveGraphDraft(context, graph) || !mounted) return;
    if (hadDraft) await reload();
    if (!mounted) return;
    final family = controller.family;
    final session = controller.session == null
        ? null
        : widget.api.resolveSession(controller.session!);
    if (family == null || session == null || controller.busy) return;
    if (session.canEditAt(DateTime.now())) {
      startEditing(family);
      return;
    }
    await unlockEdit(preserveForm: false);
  }

  Future<void> unlockEdit({required bool preserveForm}) async {
    final session = controller.session == null
        ? null
        : widget.api.resolveSession(controller.session!);
    if (session == null || !session.canReadAt(DateTime.now())) {
      if (preserveForm) {
        setState(
          () => editWarning = 'Phiên truy cập đã hết hạn. Nội dung đang nhập chưa được lưu; hãy giữ lại trước khi mở lại gia phả.',
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => JoinFamilyScreen(
              api: widget.api,
              storage: widget.storage,
              expectedFamilyId: widget.familyId,
            ),
          ),
        );
      }
      return;
    }
    final result = await Navigator.of(context).push<EditCodeResult>(
      MaterialPageRoute(
        builder: (_) => EditCodeScreen(
          api: widget.api,
          storage: widget.storage,
          familyId: widget.familyId,
          session: session,
        ),
      ),
    );
    if (!mounted || result == null) return;
    controller.adoptSession(result.session);
    setState(() {
      // API12 invalidates the old token retained by already-open tab controllers.
      treeOpened = false;
      membersOpened = false;
      editRejected = false;
      if (!result.savedOnDevice) {
        editWarning = 'Đã mở quyền sửa nhưng chưa lưu được phiên trên thiết bị. Nếu đóng ứng dụng, hãy nhập lại mã.';
      }
    });
    await reload();
    if (!mounted || controller.family == null) return;
    if (preserveForm) {
      if (controller.family!.version != editVersion) {
        setState(() {
          conflict = true;
          editWarning = 'Thông tin gia phả đã thay đổi. Hãy đối chiếu bản mới trước khi bắt đầu lưu lại.';
        });
      }
    } else {
      startEditing(controller.family!);
      if (!result.savedOnDevice) {
        setState(
          () => editWarning = 'Đã mở quyền sửa nhưng chưa lưu được phiên trên thiết bị. Nếu đóng ứng dụng, hãy nhập lại mã.',
        );
      }
    }
  }

  Future<void> save() async {
    if (!editing ||
        controller.busy ||
        conflict ||
        !editForm.currentState!.validate()) {
      return;
    }
    final session = controller.session == null
        ? null
        : widget.api.resolveSession(controller.session!);
    if (session == null || !session.canReadAt(DateTime.now())) {
      setState(
        () => editWarning =
            'Phiên truy cập đã hết hạn. Nội dung đang nhập chưa được lưu.',
      );
      return;
    }
    if (!session.canEditAt(DateTime.now()) || editRejected) {
      await unlockEdit(preserveForm: true);
      return; // A new token never silently replays the pending PUT.
    }
    final result = await controller.saveMetadata(
      name: name.text,
      description: description.text.trim().isEmpty ? null : description.text,
      baseVersion: editVersion,
    );
    if (!mounted) return;
    if (result != null) {
      setState(() {
        editing = false;
        conflict = false;
        editWarning = null;
      });
    } else if (controller.outcomeUnknown) {
      setState(() => conflict = true);
    } else if (controller.error?.contains('Quyền chỉnh sửa') == true) {
      setState(() => editRejected = true);
    } else if (controller.error?.contains('đã thay đổi') == true) {
      setState(() => conflict = true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || graph.committing) return;
      if (await discardEdit() &&
          context.mounted &&
          await resolveGraphDraft(context, graph) &&
          context.mounted) {
        setState(() => allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    },
    child: PageShell(
      showAppBar: selectedTab != 1,
      maxWidth: selectedTab == 1 ? double.infinity : 540,
      title: ['Thông tin gia phả', 'Sơ đồ gia phả', 'Thành viên'][selectedTab],
      bottom: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (i) async {
          if (graph.committing) return;
          if (!await discardEdit() || !mounted) return;
          if (i == 0) await reload();
          if (i == 1 &&
              !graph.dirty &&
              !graph.blocked &&
              (graph.snapshot == null ||
                  graph.loadedRevision !=
                      widget.api.revision(widget.familyId))) {
            await graph.load();
          }
          if (!mounted) return;
          setState(() {
            selectedTab = i;
            if (i == 2) membersOpened = true;
            if (i == 1) treeOpened = true;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            label: 'Thông tin',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_tree_outlined),
            label: 'Sơ đồ',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            label: 'Thành viên',
          ),
        ],
      ),
      child: Column(
        children: [
          if (selectedTab != 1) DraftBanner(graph: graph),
          Expanded(
            child: IndexedStack(
              index: selectedTab,
              children: [
                information(),
                if (treeOpened)
                  FamilyTreeView(
                    key: ValueKey('tree-${widget.familyId}'),
                    sharedGraph: graph,
                    active: selectedTab == 1,
                    api: widget.api,
                    storage: widget.storage,
                    familyId: widget.familyId,
                    initialSession: controller.session ?? widget.initialSession,
                  )
                else
                  const SizedBox.shrink(),
                if (membersOpened)
                  PeopleView(
                    graph: graph,
                    key: ValueKey(
                      'people-${widget.api.revision(widget.familyId)}',
                    ),
                    api: widget.api,
                    storage: widget.storage,
                    familyId: widget.familyId,
                    initialSession: controller.session ?? widget.initialSession,
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget information() => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => RefreshIndicator(
      onRefresh: editing ? () async {} : reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
        children: [
          const FamilyIllustration(height: 210),
          if (controller.busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          Notice(controller.error),
          Notice(controller.warning ?? widget.initialWarning, warning: true),
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
          else if (controller.error != null && !controller.busy && !editing)
            ActionButton(
              label: 'Thử tải lại',
              icon: Icons.refresh,
              onPressed: reload,
            ),
          if (controller.family case final family?) ...[
            if (!editing) ...[
              Text(
                family.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Chip(
                  avatar: const Icon(
                    Icons.verified_user_outlined,
                    size: 17,
                    color: forest,
                  ),
                  label: Text(
                    controller.session?.canEditAt(DateTime.now()) == true
                        ? 'Phiên có quyền chỉnh sửa'
                        : 'Quyền xem gia phả',
                  ),
                  backgroundColor: mint,
                  side: BorderSide.none,
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: controller.busy ? null : requestEditing,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Chỉnh sửa'),
              ),
              const SizedBox(height: 8),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(
                      'Câu chuyện gia đình',
                      Icons.menu_book_outlined,
                    ),
                    Text(
                      family.description?.isNotEmpty == true
                          ? family.description!
                          : 'Gia phả chưa có mô tả.',
                      style: const TextStyle(color: ink, height: 1.6),
                    ),
                    const SizedBox(height: 22),
                    const Divider(),
                    const SizedBox(height: 10),
                    _InfoRow(
                      Icons.groups_outlined,
                      'Số thành viên',
                      family.personCount.toString(),
                    ),
                    _InfoRow(
                      Icons.calendar_today_outlined,
                      'Ngày tạo',
                      displayDate(family.createdAt),
                    ),
                    _InfoRow(
                      Icons.update,
                      'Cập nhật gần nhất',
                      displayDate(family.updatedAt),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              TextButton.icon(
                onPressed: controller.busy ? null : reload,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Làm mới thông tin'),
              ),
            ] else ...[
              editFields(),
            ],
          ],
        ],
      ),
    ),
  );

  Widget editFields() => Form(
    key: editForm,
    child: Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('Chỉnh sửa gia phả', Icons.edit_outlined),
          Notice(editWarning, warning: true),
          TextFormField(
            controller: name,
            enabled: !controller.busy,
            maxLength: 150,
            validator: requiredName,
            decoration: fieldDecoration('Tên gia phả', Icons.family_restroom),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: description,
            enabled: !controller.busy,
            maxLength: 10000,
            minLines: 3,
            maxLines: 5,
            decoration: fieldDecoration('Mô tả', Icons.notes_outlined),
          ),
          const SizedBox(height: 20),
          if (conflict)
            OutlinedButton.icon(
              onPressed: () async {
                if (await discardEdit()) await reload();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Bỏ thay đổi và tải bản mới'),
            )
          else
            ActionButton(
              label: 'Lưu',
              icon: Icons.save_outlined,
              busy: controller.busy,
              onPressed: save,
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: controller.busy ? null : () => discardEdit(),
            child: const Text('Hủy'),
          ),
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Icon(icon, size: 20, color: forest),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xFF667E73))),
        ),
        Text(
          value,
          style: const TextStyle(color: ink, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
