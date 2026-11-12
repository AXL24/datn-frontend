import 'package:flutter/material.dart';

import '../controllers/graph_controller.dart';
import '../widgets/app_widgets.dart';
import 'edit_code_screen.dart';

Future<bool> ensureGraphEdit(
  BuildContext context,
  GraphController graph,
) async {
  if (graph.busy || graph.committing || graph.blocked) return false;
  var session = graph.session;
  session ??=
      graph.initialSession ?? await graph.storage.getSession(graph.familyId);
  if (!context.mounted || session == null) return false;
  session = graph.api.resolveSession(session);
  if (!session.canReadAt(DateTime.now())) {
    graph.error = 'Phiên truy cập hết hạn. Giữ bản nháp để đối chiếu, mở lại gia phả bằng Family Code.';
    graph.rebuild();
    return false;
  }
  graph.session = session;
  if (!graph.needsEdit && session.canEditAt(DateTime.now())) return true;
  final result = await Navigator.push<EditCodeResult>(
    context,
    MaterialPageRoute(
      builder: (_) => EditCodeScreen(
        api: graph.api,
        storage: graph.storage,
        familyId: graph.familyId,
        session: session!,
        purpose: 'chỉnh sửa sơ đồ',
      ),
    ),
  );
  if (!context.mounted || result == null) return false;
  graph.session = result.session;
  graph.needsEdit = false;
  if (!result.savedOnDevice) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Phiên mới đang dùng trong bộ nhớ, chưa lưu được trên thiết bị.',
        ),
      ),
    );
  }
  return true;
}

Future<bool> saveGraph(BuildContext context, GraphController graph) async {
  if (!await ensureGraphEdit(context, graph) || !context.mounted) return false;
  return graph.commit();
}

Future<bool> resolveGraphDraft(
  BuildContext context,
  GraphController? graph,
) async {
  if (graph == null) return true;
  if (graph.busy || graph.committing) return false;
  if (!graph.dirty && !graph.blocked) return true;
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Bản nháp sơ đồ chưa lưu'),
      content: Text(
        graph.blocked
            ? 'Cần đối chiếu dữ liệu trước khi tiếp tục. Bỏ chỉ bỏ bản nháp cục bộ, không hoàn tác thao tác đã được máy chủ xử lý.'
            : 'Lưu sơ đồ trước khi tiếp tục, bỏ phần quan hệ chưa lưu, hoặc hủy thao tác đang định thực hiện.',
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
        FilledButton(
          onPressed: graph.blocked
              ? null
              : () => Navigator.pop(context, 'save'),
          child: const Text('Lưu'),
        ),
      ],
    ),
  );
  if (!context.mounted) return false;
  if (choice == 'discard') return graph.discardAndReload();
  if (choice == 'save') {
    final saved = await saveGraph(context, graph);
    // Do not continue a dependent write when post-commit refresh failed.
    return saved && graph.snapshot != null && graph.error == null;
  }
  return false;
}

class DraftBanner extends StatelessWidget {
  final GraphController graph;
  const DraftBanner({super.key, required this.graph});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: graph,
    builder: (context, _) => !graph.dirty && !graph.blocked
        ? const SizedBox.shrink()
        : Container(
            color: mint,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              'Bản nháp sơ đồ: ${graph.draft?.commands.length ?? 0} thao tác chưa lưu${graph.blocked ? ' · Cần đối chiếu' : ''}.',
              style: const TextStyle(color: forest),
            ),
          ),
  );
}
