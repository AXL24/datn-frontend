import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/family_controller.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_widgets.dart';
import 'family_codes_screen.dart';

class CreateFamilyScreen extends StatefulWidget {
  final ApiService api;
  final StorageService storage;
  const CreateFamilyScreen({
    super.key,
    required this.api,
    required this.storage,
  });
  @override
  State<CreateFamilyScreen> createState() => _CreateFamilyScreenState();
}

class _CreateFamilyScreenState extends State<CreateFamilyScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      description = TextEditingController(),
      person = TextEditingController(),
      year = TextEditingController();
  late final controller = FamilyController(widget.api, widget.storage);
  @override
  void dispose() {
    for (final c in [name, description, person, year]) {
      c.dispose();
    }
    controller.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final result = await controller.create(
      name: name.text,
      description: description.text.trim().isEmpty
          ? null
          : description.text.trim(),
      personName: person.text,
      birthYear: int.tryParse(year.text),
    );
    if (!mounted || result == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => FamilyCodesScreen(
          api: widget.api,
          storage: widget.storage,
          result: result,
          warning: controller.warning,
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
        title: 'Tạo gia phả',
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
            children: [
              const FamilyIllustration(height: 155),
              const Text(
                'Bắt đầu từ một người thân',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              Notice(controller.error),
              Surface(
                child: Column(
                  children: [
                    const SectionTitle(
                      'Thông tin gia phả',
                      Icons.menu_book_outlined,
                      subtitle: 'Một nơi để lưu lại câu chuyện gia đình.',
                    ),
                    TextFormField(
                      controller: name,
                      enabled: !controller.busy,
                      validator: requiredName,
                      maxLength: 150,
                      decoration: fieldDecoration(
                        'Tên gia phả *',
                        Icons.account_tree_outlined,
                        hint: 'Ví dụ: Gia phả nhà Nguyễn',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: description,
                      enabled: !controller.busy,
                      maxLines: 3,
                      maxLength: 10000,
                      decoration: fieldDecoration(
                        'Mô tả (không bắt buộc)',
                        Icons.notes_outlined,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Surface(
                child: Column(
                  children: [
                    const SectionTitle(
                      'Người đầu tiên',
                      Icons.person_outline,
                      subtitle: 'Bạn có thể bổ sung những người khác sau.',
                    ),
                    TextFormField(
                      controller: person,
                      enabled: !controller.busy,
                      validator: requiredName,
                      maxLength: 150,
                      decoration: fieldDecoration(
                        'Họ và tên *',
                        Icons.badge_outlined,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: year,
                      enabled: !controller.busy,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      validator: (s) =>
                          s == null ||
                              s.isEmpty ||
                              (int.tryParse(s) != null &&
                                  int.parse(s) >= 1 &&
                                  int.parse(s) <= 9999)
                          ? null
                          : 'Năm sinh từ 1 đến 9999.',
                      decoration: fieldDecoration(
                        'Năm sinh (không bắt buộc)',
                        Icons.calendar_today_outlined,
                        hint: 'Ví dụ: 1950',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              ActionButton(
                label: 'Tạo gia phả',
                icon: Icons.add,
                busy: controller.busy,
                onPressed: controller.outcomeUnknown ? null : submit,
              ),
              const SizedBox(height: 12),
              const Text(
                'Hai mã truy cập sẽ được cấp sau khi tạo thành công.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF667E73)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
