import 'package:flutter/material.dart';

import '../controllers/family_controller.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_widgets.dart';
import 'family_info_screen.dart';

class JoinFamilyScreen extends StatefulWidget {
  final ApiService api;
  final StorageService storage;
  final int? expectedFamilyId;
  const JoinFamilyScreen({
    super.key,
    required this.api,
    required this.storage,
    this.expectedFamilyId,
  });
  @override
  State<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends State<JoinFamilyScreen> {
  final form = GlobalKey<FormState>();
  final code = TextEditingController();
  late final controller = FamilyController(widget.api, widget.storage);
  @override
  void dispose() {
    code.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final result = await controller.join(
      code.text,
      expectedFamilyId: widget.expectedFamilyId,
    );
    if (!mounted || result == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => FamilyInfoScreen(
          api: widget.api,
          storage: widget.storage,
          familyId: result.family.id,
          initialSession: result.session,
          initialWarning: controller.warning,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => PopScope(
      canPop: !controller.busy,
      child: PageShell(
        title: 'Tham gia gia phả',
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
            children: [
              const FamilyIllustration(height: 240),
              const Text(
                'Kết nối với gia đình',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Nhập mã gia phả được người thân chia sẻ\nđể cùng xem câu chuyện của gia đình.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF667E73), height: 1.5),
              ),
              const SizedBox(height: 28),
              Notice(controller.error),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(
                      'Family Code',
                      Icons.key_outlined,
                      subtitle: 'Mã này cấp quyền xem gia phả.',
                    ),
                    TextFormField(
                      controller: code,
                      enabled: !controller.busy,
                      autocorrect: false,
                      enableSuggestions: false,
                      maxLength: 255,
                      validator: (s) => s == null || s.trim().isEmpty
                          ? 'Vui lòng nhập mã gia phả.'
                          : null,
                      decoration: fieldDecoration(
                        'Mã gia phả',
                        Icons.qr_code_2,
                        hint: 'GP_…',
                      ),
                    ),
                    const SizedBox(height: 16),
                    ActionButton(
                      label: 'Mở gia phả',
                      icon: Icons.lock_open_outlined,
                      busy: controller.busy,
                      onPressed: submit,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: controller.busy
                    ? null
                    : () => Navigator.pop(context),
                child: const Text('Quay lại'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
