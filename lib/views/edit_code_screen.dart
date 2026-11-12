import 'package:flutter/material.dart';

import '../models/access_session.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_widgets.dart';

class EditCodeResult {
  final AccessSession session;
  final bool savedOnDevice;
  const EditCodeResult(this.session, this.savedOnDevice);
}

/// MH07: unlock one current Family and return the replacement session.
class EditCodeScreen extends StatefulWidget {
  final ApiService api;
  final StorageService storage;
  final int familyId;
  final AccessSession session;
  final String purpose;
  const EditCodeScreen({
    super.key,
    required this.api,
    required this.storage,
    required this.familyId,
    required this.session,
    this.purpose = 'chỉnh sửa thông tin gia phả',
  });
  @override
  State<EditCodeScreen> createState() => _EditCodeScreenState();
}

class _EditCodeScreenState extends State<EditCodeScreen> {
  final form = GlobalKey<FormState>();
  final code = TextEditingController();
  bool busy = false, outcomeUnknown = false, obscured = true;
  String? error;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || outcomeUnknown || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = await widget.api.unlockEdit(
        widget.familyId,
        widget.session,
        code.text,
      );
      bool saved = true;
      try {
        await widget.storage.saveSession(next);
      } catch (_) {
        saved = false;
      }
      if (!mounted) return;
      Navigator.of(context).pop(EditCodeResult(next, saved));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        outcomeUnknown = e.outcomeUnknown;
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: PageShell(
      title: 'Nhập mã chỉnh sửa',
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 38, 22, 30),
          children: [
            const FamilyIllustration(height: 130),
            const SizedBox(height: 28),
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.key_rounded, color: forest, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Bạn đang muốn ${widget.purpose}. Nhập Edit Code của gia phả này.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: ink, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  Notice(error),
                  TextFormField(
                    controller: code,
                    enabled: !busy && !outcomeUnknown,
                    obscureText: obscured,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLength: 255,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => submit(),
                    validator: (s) => s == null || s.trim().isEmpty
                        ? 'Vui lòng nhập mã chỉnh sửa.'
                        : null,
                    decoration:
                        fieldDecoration(
                          'Edit Code',
                          Icons.lock_outline,
                          hint: 'ED_…',
                        ).copyWith(
                          suffixIcon: IconButton(
                            tooltip: obscured ? 'Hiện mã' : 'Ẩn mã',
                            onPressed: () =>
                                setState(() => obscured = !obscured),
                            icon: Icon(
                              obscured
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                  ),
                  const SizedBox(height: 8),
                  ActionButton(
                    label: 'Xác nhận',
                    icon: Icons.lock_open_outlined,
                    busy: busy,
                    onPressed: outcomeUnknown ? null : submit,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: busy ? null : () => Navigator.pop(context),
                    child: const Text('Quay lại'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Liên hệ người đang giữ mã chỉnh sửa nếu bạn chưa có mã.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF667E73)),
            ),
          ],
        ),
      ),
    ),
  );
}
