import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/family_controller.dart';
import '../models/access_session.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_widgets.dart';
import 'family_info_screen.dart';

class FamilyCodesScreen extends StatefulWidget {
  final ApiService api;
  final StorageService storage;
  final CreatedFamily result;
  final String? warning;
  const FamilyCodesScreen({
    super.key,
    required this.api,
    required this.storage,
    required this.result,
    this.warning,
  });
  @override
  State<FamilyCodesScreen> createState() => _FamilyCodesScreenState();
}

class _FamilyCodesScreenState extends State<FamilyCodesScreen> {
  late final controller = FamilyController(widget.api, widget.storage)
    ..warning = widget.warning;
  bool confirmed = false, saving = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hãy lưu hai mã và xác nhận trước khi tiếp tục.'),
          ),
        );
      }
    },
    child: PageShell(
      title: 'Đã tạo gia phả',
      back: false,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
          children: [
            const FamilyIllustration(height: 180),
            const Icon(Icons.check_circle, color: forest, size: 32),
            const SizedBox(height: 10),
            Text(
              widget.result.family.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Lưu hai mã dưới đây trước khi tiếp tục.\nMã chỉ được hiển thị ở lần tạo này.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF667E73), height: 1.5),
            ),
            const SizedBox(height: 22),
            Notice(controller.warning, warning: true),
            if (controller.warning != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setState(() => saving = true);
                          await controller.remember(widget.result);
                          if (mounted) setState(() => saving = false);
                        },
                  child: Text(
                    saving
                        ? 'Đang lưu trên thiết bị…'
                        : 'Thử lưu phiên trên thiết bị',
                  ),
                ),
              ),
            _CodeCard(
              label: 'Family Code',
              description: 'Chia sẻ cho người được xem.',
              code: widget.result.familyCode,
              icon: Icons.groups_outlined,
            ),
            const SizedBox(height: 12),
            _CodeCard(
              label: 'Edit Code',
              description: 'Chỉ gửi cho người được chỉnh sửa.',
              code: widget.result.editCode,
              icon: Icons.edit_outlined,
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Tôi đã lưu cả hai mã',
                style: TextStyle(fontSize: 14),
              ),
              value: confirmed,
              onChanged: (v) => setState(() => confirmed = v ?? false),
            ),
            ActionButton(
              label: 'Vào gia phả',
              onPressed: !confirmed || saving
                  ? null
                  : () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => FamilyInfoScreen(
                          api: widget.api,
                          storage: widget.storage,
                          familyId: widget.result.family.id,
                          initialSession: widget.result.session,
                          initialWarning: controller.warning,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CodeCard extends StatefulWidget {
  final String label, description, code;
  final IconData icon;
  const _CodeCard({
    required this.label,
    required this.description,
    required this.code,
    required this.icon,
  });
  @override
  State<_CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends State<_CodeCard> {
  bool visible = false;
  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(widget.label, widget.icon, subtitle: widget.description),
        SelectableText(
          visible ? widget.code : '•••• •••• ••••',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: ink,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          children: [
            TextButton.icon(
              onPressed: () => setState(() => visible = !visible),
              icon: Icon(
                visible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
              ),
              label: Text(visible ? 'Ẩn mã' : 'Hiện mã'),
            ),
            TextButton.icon(
              onPressed: () async {
                try {
                  await Clipboard.setData(ClipboardData(text: widget.code));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Đã sao chép ${widget.label}.')),
                    );
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Chưa sao chép được. Hãy hiện mã và lưu thủ công.',
                        ),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Sao chép'),
            ),
          ],
        ),
      ],
    ),
  );
}
