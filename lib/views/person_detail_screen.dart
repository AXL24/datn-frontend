import 'package:flutter/material.dart';

import '../controllers/person_controller.dart';
import '../controllers/graph_controller.dart';
import '../models/access_session.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_widgets.dart';
import '../widgets/person_widgets.dart';
import 'edit_code_screen.dart';
import 'person_edit_screen.dart';

class PersonDetailScreen extends StatefulWidget {
  final GraphController? graph;
  final ApiService api;
  final StorageService storage;
  final int familyId, personId;
  final bool fromTree;
  final AccessSession? initialSession;
  const PersonDetailScreen({
    super.key,
    this.graph,
    required this.api,
    required this.storage,
    required this.familyId,
    required this.personId,
    this.initialSession,
    this.fromTree = false,
  });
  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  late final controller = PersonController(
    widget.api,
    widget.storage,
    widget.familyId,
    initialSession: widget.initialSession,
  );
  @override
  void initState() {
    super.initState();
    reload();
  }

  bool opening = false;
  Future<void> reload() => controller.loadPerson(widget.personId);
  Future<void> edit() async {
    if (opening || controller.person == null || controller.session == null) {
      return;
    }
    if (widget.graph?.blocked == true || widget.graph?.committing == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cần giải quyết bản nháp sơ đồ trước khi sửa hồ sơ.'),
        ),
      );
      return;
    }
    opening = true;
    try {
      var session = widget.api.resolveSession(controller.session!);
      if (!session.canEditAt(DateTime.now())) {
        final result = await Navigator.push<EditCodeResult>(
          context,
          MaterialPageRoute(
            builder: (_) => EditCodeScreen(
              api: widget.api,
              storage: widget.storage,
              familyId: widget.familyId,
              session: session,
              purpose: 'chỉnh sửa hồ sơ',
            ),
          ),
        );
        if (!mounted || result == null) return;
        session = result.session;
        controller.session = session;
        if (!result.savedOnDevice) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Phiên mới chưa lưu được trên thiết bị; đang dùng trong bộ nhớ.',
              ),
            ),
          );
        }
      }
      if (widget.graph?.dirty == true &&
          !widget.graph!.draft!.baseline.persons.any(
            (p) => p.id == widget.personId,
          )) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Hồ sơ này chưa có trong nền bản nháp. Hãy Lưu hoặc Bỏ bản nháp trước khi sửa.',
              ),
            ),
          );
        }
        return;
      }
      // Fresh API07 baseline is obtained before starting any form, never over a dirty form.
      await reload();
      if (!mounted || controller.person == null) return;
      final deleted = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PersonEditScreen(
            api: widget.api,
            storage: widget.storage,
            person: widget.graph?.dirty == true
                ? widget.graph!.draft!.personWithVersion(widget.personId)
                : controller.person!,
            graph: widget.graph,
            session: session,
          ),
        ),
      );
      if (!mounted) return;
      if (deleted == true) {
        Navigator.pop(context);
        return;
      }
      await reload();
    } finally {
      opening = false;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageShell(
    title: 'Chi tiết hồ sơ',
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: controller.busy || controller.person == null
                    ? null
                    : edit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Chỉnh sửa'),
              ),
            ),
            if (controller.busy)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
            Notice(controller.error),
            if (controller.error != null) ...[
              if (!controller.needsJoin && controller.errorStatus != 404)
                ActionButton(label: 'Thử tải lại', onPressed: reload),
              const SizedBox(height: 10),
              ActionButton(
                label: widget.fromTree
                    ? 'Về sơ đồ gia phả'
                    : controller.needsJoin
                    ? 'Về thành viên để nhập lại mã'
                    : 'Về danh sách thành viên',
                icon: Icons.arrow_back,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
            if (controller.person case final person?) ...[
              const SizedBox(height: 10),
              Center(child: PersonAvatar(person, radius: 52)),
              const SizedBox(height: 18),
              Text(
                person.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Chip(
                  label: Text(
                    person.lifeStatus == 'UNKNOWN'
                        ? 'Chưa rõ tình trạng'
                        : person.lifeStatusLabel,
                  ),
                  backgroundColor: mint,
                  side: BorderSide.none,
                ),
              ),
              const SizedBox(height: 22),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProfileField(
                      'Họ và tên',
                      person.name,
                      Icons.badge_outlined,
                    ),
                    const Divider(),
                    ProfileField(
                      'Giới tính',
                      person.genderLabel,
                      Icons.person_outline,
                    ),
                    const Divider(),
                    ProfileField(
                      'Ngày / năm sinh',
                      person.birthLabel,
                      Icons.cake_outlined,
                    ),
                    const Divider(),
                    ProfileField(
                      'Ngày / năm mất',
                      person.deathLabel,
                      Icons.event_outlined,
                    ),
                    const Divider(),
                    ProfileField(
                      'Thông tin bổ sung',
                      person.note?.trim().isNotEmpty == true
                          ? person.note!
                          : 'Chưa có thông tin',
                      Icons.notes_outlined,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: reload,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Làm mới hồ sơ'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
