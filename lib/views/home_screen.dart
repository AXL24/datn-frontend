import 'package:flutter/material.dart';

import '../controllers/family_controller.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_widgets.dart';
import 'create_family_screen.dart';
import 'join_family_screen.dart';
import 'family_info_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiService api;
  final StorageService storage;
  const HomeScreen({super.key, required this.api, required this.storage});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final controller = FamilyController(widget.api, widget.storage);
  @override
  void initState() {
    super.initState();
    controller.loadRecents();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> go(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) await controller.loadRecents();
  }

  @override
  Widget build(BuildContext context) => PageShell(
    title: 'Cây Gia Phả',
    back: false,
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => RefreshIndicator(
        onRefresh: controller.loadRecents,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
          children: [
            const Text(
              'LƯU GIỮ CỘI NGUỒN',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
                color: forest,
              ),
            ),
            const FamilyIllustration(height: 210),
            const Text(
              'Câu chuyện gia đình,\nqua từng thế hệ.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 29,
                height: 1.2,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ghi lại những người thân yêu và cùng nhau\ngìn giữ ký ức của gia đình.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF667E73), height: 1.5),
            ),
            const SizedBox(height: 26),
            ActionButton(
              label: 'Tạo gia phả mới',
              icon: Icons.add_circle_outline,
              onPressed: () => go(
                CreateFamilyScreen(api: widget.api, storage: widget.storage),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
                onPressed: () => go(
                  JoinFamilyScreen(api: widget.api, storage: widget.storage),
                ),
                icon: const Icon(Icons.key_outlined),
                label: const Text('Nhập mã gia phả'),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Gia phả đã mở',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tải lại danh sách',
                  onPressed: controller.busy ? null : controller.loadRecents,
                  icon: const Icon(Icons.refresh, size: 21),
                ),
              ],
            ),
            Notice(controller.error),
            if (controller.busy) const LinearProgressIndicator(),
            if (!controller.busy && controller.recents.isEmpty)
              const Surface(
                child: Text(
                  'Chưa có gia phả nào. Tạo mới hoặc nhập mã được chia sẻ để bắt đầu.',
                  style: TextStyle(color: Color(0xFF667E73), height: 1.5),
                ),
              ),
            ...controller.recents.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: const CircleAvatar(
                      backgroundColor: mint,
                      child: Icon(Icons.account_tree_outlined, color: forest),
                    ),
                    title: Text(
                      f.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Mở gần nhất: ${displayDate(f.lastOpenedAt)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () => go(
                      FamilyInfoScreen(
                        api: widget.api,
                        storage: widget.storage,
                        familyId: f.id,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Bỏ khỏi thiết bị',
                      icon: const Icon(Icons.more_horiz),
                      onPressed: controller.busy
                          ? null
                          : () async {
                              final remove = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Bỏ khỏi thiết bị?'),
                                  content: const Text(
                                    'Xóa mục đã lưu và phiên trên thiết bị này. Gia phả trên máy chủ vẫn được giữ nguyên.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Hủy'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Bỏ khỏi thiết bị'),
                                    ),
                                  ],
                                ),
                              );
                              if (remove == true) await controller.remove(f.id);
                            },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Bắt đầu cùng gia đình'),
                  content: const Text(
                    'Tạo gia phả để nhận hai mã. Chia sẻ Family Code cho người được xem; chỉ gửi Edit Code cho người được sửa. Mã chỉnh sửa cần được cất giữ cẩn thận.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Đã hiểu'),
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.help_outline, size: 18),
              label: const Text('Hướng dẫn & trợ giúp'),
            ),
          ],
        ),
      ),
    ),
  );
}
