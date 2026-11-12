import 'package:flutter/material.dart';

import '../controllers/person_edit_controller.dart';
import '../controllers/graph_controller.dart';
import 'graph_draft_actions.dart';
import '../models/person.dart';
import '../models/access_session.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_widgets.dart';
import '../widgets/person_widgets.dart';
import 'delete_person_screen.dart';
import 'edit_code_screen.dart';

class PersonEditScreen extends StatefulWidget {
  final GraphController? graph;
  final ApiService api;
  final StorageService storage;
  final Person? person;
  final int? createVersion;
  final AccessSession session;
  const PersonEditScreen({
    super.key,
    this.graph,
    required this.api,
    required this.storage,
    required this.person,
    required this.session,
  }) : createVersion = null;
  const PersonEditScreen.create({
    super.key,
    required this.api,
    required this.storage,
    required this.session,
    required int baseVersion,
  }) : graph = null,
       person = null,
       createVersion = baseVersion;
  @override
  State<PersonEditScreen> createState() => _PersonEditScreenState();
}

class _PersonEditScreenState extends State<PersonEditScreen> {
  late final c = widget.person == null
      ? PersonEditController.create(
          widget.api,
          widget.session,
          widget.createVersion!,
        )
      : PersonEditController(
          widget.api,
          widget.session,
          widget.person!,
          graph: widget.graph,
        );
  final form = GlobalKey<FormState>();
  int formRevision = 0;
  bool leaving = false, actionBusy = false;
  Future<void> runAction(Future<void> Function() action) async {
    if (actionBusy || c.busy) return;
    setState(() => actionBusy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  String? warning;
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<bool> ensureEdit() async {
    c.session = widget.api.resolveSession(c.session);
    if (!c.needsEdit && c.session.canEditAt(DateTime.now())) return true;
    if (!c.session.canReadAt(DateTime.now())) {
      setState(
        () => warning = 'Phiên truy cập đã hết hạn. Giữ lại nội dung đang sửa và mở lại gia phả bằng Family Code.',
      );
      return false;
    }
    final result = await Navigator.push<EditCodeResult>(
      context,
      MaterialPageRoute(
        builder: (_) => EditCodeScreen(
          api: widget.api,
          storage: widget.storage,
          familyId: widget.session.familyId,
          session: c.session,
          purpose: c.creating ? 'thêm thành viên độc lập' : 'chỉnh sửa hồ sơ',
        ),
      ),
    );
    if (!mounted || result == null) return false;
    setState(() {
      c.session = result.session;
      c.needsEdit = false;
      warning = result.savedOnDevice ? null : 'Phiên mới đang dùng trong bộ nhớ nhưng chưa lưu được trên thiết bị.';
    });
    // Keep the original Family baseline. API08/09 will validate it again.
    return true;
  }

  Future<bool> save() async {
    if (!form.currentState!.validate() || !await ensureEdit()) return false;
    final ok = await c.save();
    if (mounted && ok && c.creating) {
      setState(() => leaving = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, c.baseline);
      });
      return true;
    }
    if (mounted && ok) {
      setState(() => formRevision++);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã lưu hồ sơ.')));
    }
    return ok;
  }

  Future<String?> dirtyChoice() => showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Hồ sơ có thay đổi chưa lưu'),
      content: Text(
        c.creating
            ? 'Bỏ thông tin đang nhập? Việc này không gửi yêu cầu tạo/xóa và không hoàn tác yêu cầu đã được máy chủ xử lý.'
            : 'Lưu thông tin trước khi tiếp tục, hoặc bỏ phần đang sửa. Lưu thành công sẽ được ghi ngay vào gia phả.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: const Text('Hủy'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'discard'),
          child: const Text('Bỏ'),
        ),
        if (!c.creating)
          FilledButton(
            onPressed: c.blocked ? null : () => Navigator.pop(context, 'save'),
            child: const Text('Lưu'),
          ),
      ],
    ),
  );
  Future<bool> resolveDirty() async {
    if (!c.dirty) return true;
    final choice = await dirtyChoice();
    if (!mounted) return false;
    if (choice == 'save') return save();
    if (choice == 'discard') {
      setState(() {
        c.discard();
        formRevision++;
      });
      return true;
    }
    return false;
  }

  Future<void> leave() async {
    if (c.busy || !await resolveDirty() || !mounted) return;
    setState(() => leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, c.creating ? null : false);
    });
  }

  Future<void> remove() async {
    if (c.busy || c.blocked || !await resolveDirty() || !mounted) return;
    final hadDraft =
        widget.graph?.dirty == true || widget.graph?.blocked == true;
    if (!await resolveGraphDraft(context, widget.graph) || !mounted) return;
    if (hadDraft &&
        widget.graph?.draft != null &&
        !widget.graph!.draft!.baseline.persons.any(
          (p) => p.id == c.baseline.id,
        )) {
      setState(() {
        c.blocked = true;
        c.error =
            'Hồ sơ không còn tồn tại sau khi đối chiếu. Không gửi yêu cầu xóa.';
      });
      return;
    }
    if (hadDraft && widget.graph?.draft != null) {
      c.useResolvedBaseline(
        widget.graph!.draft!.personWithVersion(c.baseline.id),
      );
    }
    if (!await ensureEdit() || !mounted) return;
    if (!await c.verifyBeforeDelete() || !mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DeletePersonScreen(controller: c)),
    );
    if (!mounted) return;
    if (result == true) {
      setState(() => leaving = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    }
  }

  Widget text(
    String key,
    String label, {
    int? max,
    int lines = 1,
    bool year = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      initialValue: c.details[key]?.toString() ?? '',
      decoration: InputDecoration(labelText: label),
      maxLength: max,
      maxLines: lines,
      keyboardType: year ? TextInputType.number : null,
      validator: key == 'displayName' && c.creating
          ? (v) => v == null || v.trim().isEmpty
                ? 'Vui lòng nhập họ tên thành viên.'
                : null
          : year
          ? (v) =>
                v!.isNotEmpty &&
                    (int.tryParse(v) == null ||
                        int.parse(v) < 1 ||
                        int.parse(v) > 9999)
                ? 'Năm từ 1 đến 9999'
                : null
          : null,
      onChanged: (v) => c.change(
        key,
        v.trim().isEmpty
            ? null
            : year
            ? (int.tryParse(v) ?? -1)
            : v,
      ),
    ),
  );
  Widget select(String key, String label, Map<String, String> items) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      initialValue: c.details[key] as String,
      decoration: InputDecoration(labelText: label),
      items: items.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: (v) => c.change(key, v),
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => PopScope(
      canPop: leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !actionBusy) runAction(leave);
      },
      child: PageShell(
        title: c.creating ? 'Thêm thành viên' : 'Chỉnh sửa hồ sơ',
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            if (c.creating)
              const Center(
                child: CircleAvatar(
                  radius: 46,
                  backgroundColor: mint,
                  child: Icon(Icons.person_add_alt_1, size: 44, color: forest),
                ),
              )
            else
              Center(child: PersonAvatar(c.baseline, radius: 46)),
            const SizedBox(height: 16),
            Text(
              c.creating ? 'Thành viên mới' : c.baseline.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (c.creating)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Tạo hồ sơ độc lập trong gia phả. Chưa nối quan hệ với người khác.',
                ),
              ),
            Notice(warning),
            Notice(c.error),
            if (c.baseVersion == null)
              const Notice(
                'Backend chưa trả familyVersion; chưa thể lưu hoặc xóa.',
              ),
            Form(
              key: form,
              child: AbsorbPointer(
                absorbing: c.busy || actionBusy,
                child: Column(
                  key: ValueKey(formRevision),
                  children: [
                    text('displayName', 'Họ và tên', max: 150),
                    select('gender', 'Giới tính', {
                      'UNKNOWN': 'Chưa rõ',
                      'MALE': 'Nam',
                      'FEMALE': 'Nữ',
                      'OTHER': 'Khác',
                    }),
                    select('lifeStatus', 'Tình trạng', {
                      'UNKNOWN': 'Chưa rõ',
                      'ALIVE': 'Còn sống',
                      'DECEASED': 'Đã mất',
                    }),
                    const SizedBox(height: 16),
                    const Text(
                      'Mỗi mốc chỉ nhập ngày đầy đủ hoặc năm. Để trống nếu chưa biết.',
                    ),
                    text('birthDate', 'Ngày sinh (YYYY-MM-DD)'),
                    text('birthYear', 'Hoặc năm sinh', year: true),
                    text('deathDate', 'Ngày mất (YYYY-MM-DD)'),
                    text('deathYear', 'Hoặc năm mất', year: true),
                    text('note', 'Thông tin bổ sung', max: 10000, lines: 3),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ActionButton(
              label: c.creating ? 'Tạo thành viên' : 'Lưu hồ sơ',
              busy: c.busy,
              onPressed: c.blocked || c.baseVersion == null || actionBusy
                  ? null
                  : () => runAction(() async {
                      await save();
                    }),
            ),
            const SizedBox(height: 10),
            if (!c.creating)
              OutlinedButton.icon(
                onPressed:
                    c.busy || actionBusy || c.blocked || c.baseVersion == null
                    ? null
                    : () => runAction(remove),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text(
                  'Xóa hồ sơ',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            TextButton(
              onPressed: c.busy || actionBusy ? null : () => runAction(leave),
              child: Text(c.creating ? 'Hủy' : 'Quay lại hồ sơ'),
            ),
            if (c.blocked)
              Text(
                c.creating
                    ? 'Giữ nội dung để đối chiếu. Chọn Hủy rồi Bỏ để về danh sách kiểm tra trước khi quyết định tạo mới. Không tự gửi lại lệnh tạo.'
                    : 'Giữ nguyên thông tin đang nhập để đối chiếu. Muốn bắt đầu lại, hãy quay lại hồ sơ, xác nhận Bỏ rồi tải lại. Không tự gửi lại lệnh ghi.',
              ),
          ],
        ),
      ),
    ),
  );
}
