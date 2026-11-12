import 'package:flutter/material.dart';

import '../controllers/person_edit_controller.dart';
import '../widgets/app_widgets.dart';

/// MH15. A successful DELETE is terminal; subsequent failures must never replay it.
class DeletePersonScreen extends StatelessWidget {
  final PersonEditController controller;
  const DeletePersonScreen({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => PopScope(
      canPop: !controller.busy,
      child: PageShell(
        title: 'Xác nhận xóa hồ sơ',
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 40),
            const Icon(Icons.delete_outline, color: Colors.red, size: 72),
            const SizedBox(height: 24),
            Text(
              'Xóa ${controller.baseline.name}?',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const Surface(
              child: Text(
                'Hồ sơ và toàn bộ quan hệ liên quan trực tiếp sẽ bị xóa. Những người thân khác và gia phả vẫn được giữ lại, kể cả khi đây là người cuối cùng.\n\nThao tác đã xóa không thể hoàn tác bằng Hủy hoặc Bỏ thay đổi.',
              ),
            ),
            const SizedBox(height: 24),
            Notice(controller.error),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed:
                  controller.busy || controller.blocked || controller.needsEdit
                  ? null
                  : () async {
                      final removed = await controller.remove();
                      if (context.mounted && removed) {
                        Navigator.pop(context, true);
                      }
                    },
              icon: const Icon(Icons.delete_outline),
              label: Text(controller.busy ? 'Đang xóa…' : 'Xóa hồ sơ'),
            ),
            OutlinedButton(
              onPressed: controller.busy
                  ? null
                  : () => Navigator.pop(context, false),
              child: const Text('Quay lại'),
            ),
            if (controller.blocked)
              const Text(
                'Chưa thể gửi lại lệnh xóa. Quay lại và đối chiếu hồ sơ trước khi bắt đầu thao tác mới.',
              ),
          ],
        ),
      ),
    ),
  );
}
