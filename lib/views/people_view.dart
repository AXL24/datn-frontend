import 'package:flutter/material.dart';

import '../controllers/person_controller.dart';
import '../controllers/graph_controller.dart';
import 'graph_draft_actions.dart';
import '../models/access_session.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_widgets.dart';
import '../widgets/person_widgets.dart';
import 'person_detail_screen.dart';
import 'join_family_screen.dart';
import 'edit_code_screen.dart';
import 'person_edit_screen.dart';
import '../models/person.dart';

/// MH09 body hosted by the Family screen, keeping the same bottom navigation.
class PeopleView extends StatefulWidget {
  final GraphController? graph;
  final ApiService api;
  final StorageService storage;
  final int familyId;
  final AccessSession? initialSession;
  const PeopleView({
    super.key,
    this.graph,
    required this.api,
    required this.storage,
    required this.familyId,
    this.initialSession,
  });
  @override
  State<PeopleView> createState() => _PeopleViewState();
}

class _PeopleViewState extends State<PeopleView> {
  late final controller = PersonController(
    widget.api,
    widget.storage,
    widget.familyId,
    initialSession: widget.initialSession,
  );
  final search = TextEditingController();
  bool adding = false;
  String? addError;
  Future<void> addPerson() async {
    if (adding || controller.busy || controller.session == null) return;
    setState(() {
      adding = true;
      addError = null;
    });
    try {
      if (!await resolveGraphDraft(context, widget.graph) || !mounted) return;
      var session = widget.api.resolveSession(controller.session!);
      if (!session.canReadAt(DateTime.now())) {
        throw const ApiException(
          'Phiên đã hết hạn. Hãy nhập lại Family Code.',
          status: 401,
        );
      }
      if (!session.canEditAt(DateTime.now())) {
        final unlocked = await Navigator.push<EditCodeResult>(
          context,
          MaterialPageRoute(
            builder: (_) => EditCodeScreen(
              api: widget.api,
              storage: widget.storage,
              familyId: widget.familyId,
              session: session,
              purpose: 'thêm thành viên độc lập',
            ),
          ),
        );
        if (!mounted || unlocked == null) return;
        session = unlocked.session;
        controller.session = session;
        if (!unlocked.savedOnDevice) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Phiên chỉnh sửa đang dùng trong bộ nhớ, chưa lưu được trên thiết bị.',
              ),
            ),
          );
        }
      }
      // Read the baseline before a new form exists. Never refresh it over unsaved input.
      final family = await widget.api.getFamily(widget.familyId, session);
      if (!mounted) return;
      final created = await Navigator.push<Person>(
        context,
        MaterialPageRoute(
          builder: (_) => PersonEditScreen.create(
            api: widget.api,
            storage: widget.storage,
            session: session,
            baseVersion: family.version,
          ),
        ),
      );
      if (!mounted) return;
      if (created != null) {
        widget.graph?.invalidateClean();
        search.clear();
        await controller.loadPeople(q: '', targetPage: 0);
        if (!mounted) return;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => PersonDetailScreen(
              api: widget.api,
              storage: widget.storage,
              familyId: widget.familyId,
              personId: created.id,
              graph: widget.graph,
              initialSession: widget.api.resolveSession(session),
            ),
          ),
        );
      }
      if (mounted) await controller.loadPeople();
    } on ApiException catch (e) {
      if (mounted) setState(() => addError = e.message);
      if (e.status == 401 && mounted) await controller.loadPeople();
    } finally {
      if (mounted) setState(() => adding = false);
    }
  }

  @override
  void initState() {
    super.initState();
    controller.loadPeople();
  }

  @override
  void dispose() {
    search.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> submit() {
    FocusScope.of(context).unfocus();
    return controller.loadPeople(q: search.text);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => RefreshIndicator(
      onRefresh: () => controller.loadPeople(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Những người thân yêu',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ),
              OutlinedButton(
                onPressed:
                    adding || controller.busy || controller.session == null
                    ? null
                    : addPerson,
                child: Text(adding ? 'Đang mở…' : '+ Thêm'),
              ),
            ],
          ),
          Notice(addError),
          const SizedBox(height: 8),
          const Text(
            'Xem hồ sơ và tìm thành viên trong gia phả.',
            style: TextStyle(color: Color(0xFF667E73)),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: search,
            maxLength: 150,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => submit(),
            decoration: InputDecoration(
              labelText: 'Tìm theo tên',
              hintText: 'Nhập tên thành viên',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Xóa tìm kiếm',
                icon: const Icon(Icons.close),
                onPressed: () {
                  search.clear();
                  controller.loadPeople(q: '');
                },
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: submit,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Tìm kiếm'),
            ),
          ),
          const SizedBox(height: 18),
          if (controller.busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
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
          else if (controller.error != null)
            ActionButton(
              label: 'Thử tải lại',
              icon: Icons.refresh,
              onPressed: () => controller.loadPeople(),
            ),
          if (controller.people case final data?) ...[
            Text(
              '${data.totalElements} thành viên${controller.query.trim().isEmpty ? '' : ' phù hợp'}',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: forest,
              ),
            ),
            const SizedBox(height: 12),
            if (data.content.isEmpty)
              Surface(
                child: Column(
                  children: [
                    const Icon(Icons.people_outline, size: 44, color: forest),
                    const SizedBox(height: 12),
                    Text(
                      data.totalElements > 0
                          ? 'Trang này không còn thành viên. Hãy về trang trước hoặc tải lại.'
                          : controller.query.trim().isNotEmpty
                          ? 'Không có thành viên khớp tên tìm kiếm.'
                          : 'Gia phả chưa có thành viên.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ...data.content.map(
              (person) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    leading: PersonAvatar(person),
                    title: Text(
                      person.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Sinh: ${person.birthLabel}\n${person.lifeStatus == 'DECEASED'
                          ? 'Đã mất: ${person.deathLabel}'
                          : person.lifeStatus == 'ALIVE'
                          ? 'Còn sống'
                          : 'Chưa rõ tình trạng'}',
                      style: const TextStyle(fontSize: 12, height: 1.5),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PersonDetailScreen(
                            api: widget.api,
                            storage: widget.storage,
                            familyId: widget.familyId,
                            personId: person.id,
                            graph: widget.graph,
                            initialSession: controller.session,
                          ),
                        ),
                      );
                      if (mounted) await controller.loadPeople();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  tooltip: 'Trang trước',
                  onPressed: data.page > 0
                      ? () => controller.loadPeople(targetPage: data.page - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    data.totalPages == 0
                        ? 'Chưa có trang dữ liệu'
                        : data.page >= data.totalPages
                        ? 'Trang không còn dữ liệu'
                        : 'Trang ${data.page + 1} / ${data.totalPages}',
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: 'Trang sau',
                  onPressed: data.page + 1 < data.totalPages
                      ? () => controller.loadPeople(targetPage: data.page + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: () => controller.loadPeople(targetPage: 0),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Tải lại từ trang đầu'),
            ),
          ],
        ],
      ),
    ),
  );
}
