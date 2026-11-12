# Flutter MVP Gia Phả — 29/10/2026

Client Flutter Web/Android theo MVC đơn giản. Backend13/13endpoint đã có; frontend đã nối luồng API23. Ưu tiên thử trên Edge. [Kiến trúc mã](docs/frontend-architecture-and-code-guide.md), [API23](docs/mh08-api23-graph-draft.md), [UX sơ đồ](docs/tree-edit-directional-ux.md), [ảnh render](docs/screens.md).

Cập nhật 04/11: backend đã bổ sung sáu route ảnh Family/Person qua S3, migration004 và test backend→S3 thật đạt. Flutter **chưa có UI/luồng upload, thay, xóa ảnh**; CORS trình duyệt chưa kiểm. Xem [hợp đồng API ảnh](../backend/docs/image-api-backend.md) và [bước tiếp theo](../NEXT_STEPS.md).

## Phạm vi đã triển khai

| Mã màn | Hành vi | API |
|---|---|---|
| MH01/MH04 | Trang chủ và danh sách gia phả gần đây trên thiết bị | Localstore |
| MH02/MH14 | Tạo Family/người đầu tiên, nhận mã một lần | 01 |
| MH03 | Tham gia bằng Family Code | 11 |
| MH05 | Xem/sửa metadata | 02/03 |
| MH06/MH08 | Sơ đồ VIEW/EDIT, bản nháp người trắng/cạnh, commit | 16/23 |
| MH07 | Nâng EDIT, thay phiên nguyên tử | 12 |
| MH09 | Tìm/phân trang người server, thêm độc lập | 06/05 |
| MH10/MH13/MH15 | Xem, sửa ngay và xác nhận xóa người thật | 07/08/09 |
| MH11/MH12 và panel cha/mẹ | Tạo mới/chọn hồ sơ có sẵn, role/kind, preview | Local đến khi Lưu23 |

Mã màn dùng truy vết thiết kế; một số màn là chế độ/panel dùng chung, không phải15route độc lập. API10 là endpoint đọc cạnh bổ sung, cây dùng API16 có đủ dữ liệu.

MH09 đọc server, chưa gộp tempId vào danh sách. Người tạm chỉ trên cây/picker, không nhập metadata trước commit. MH13 ID thật gọi08 ngay, không đợi Lưu sơ đồ. Tạo05/sửa08/xóa09 thành công không bị Bỏ draft hoàn tác.

## Chạy ứng dụng

Yêu cầu Flutter/Dart tương thích `pubspec.yaml`, Android SDK và thiết bị/emulator Android. Phiên phát triển dùng Flutter 3.47.2, Dart 3.13.2.

1. Chạy MySQL và backend theo [backend README](../backend/README.md). Không dùng profile smoke cho luồng nghiệp vụ.
2. Từ thư mục `frontend`:

```powershell
flutter pub get
flutter devices
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

`10.0.2.2` dùng cho Android Emulator truy cập máy đang chạy backend. Với điện thoại thật, thay bằng IP LAN của máy chạy backend; hai máy cần truy cập được nhau và cổng 8080. `localhost` trên điện thoại chỉ chính điện thoại. Có thể dùng USB `adb reverse tcp:8080 tcp:8080` rồi chạy với `API_BASE_URL=http://127.0.0.1:8080`.

```powershell
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

APK ở `build/app/outputs/flutter-apk/app-debug.apk` nếu build thành công. Thay API_BASE_URL cần chạy/build lại. HTTP cleartext chỉ bật trong manifest debug. Release cần backend HTTPS và cấu hình ký phát hành riêng; bản này phục vụ phát triển.

Trong phiên Codex, cache chung gặp lỗi quyền đổi tên; đã dùng cache cục bộ được `.gitignore` bỏ qua:

```powershell
$env:PUB_CACHE = Join-Path $PWD '.tool-cache/pub'
New-Item -ItemType Directory -Force .tool-cache/tmp | Out-Null
$env:TEMP = Join-Path $PWD '.tool-cache/tmp'
$env:TMP = $env:TEMP
$env:DASH__SUPPRESS_ANALYTICS = 'true'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
flutter --suppress-analytics pub get
```

Người dùng chạy terminal bình thường có thể dùng cache mặc định. Không commit `.tool-cache`, `.dart_tool`, `build`, log hay `android/local.properties`.

Localstore 1.4.0 dùng bản vá cục bộ tại `packages/localstore`: thêm `await` cho ghi/xóa file để lỗi I/O truyền về controller. Giữ nguyên API, định dạng dữ liệu và LICENSE. Xem [chi tiết bản vá](packages/localstore/PATCH.md).

## State và lưu trữ

View gọi controller, controller gọi service/model. FamilyInfoScreen sở hữu GraphController chung cho ba tab và truyền vào các route Person. GraphDraft giữ baseline API16, người tạm và command. Overlay dựng nhóm cha mẹ, layout, rồi CustomPainter; không gọi HTTP khi pan/zoom.

Localstore chỉ giữ danh sách gần đây. Secure storage giữ phiên theo backend/Family, gồm token, permission, expiresAt và editExpiresAt. Mã cấp lần đầu chỉ ở bộ nhớ màn nhận mã; không ghi secrets vào log/tài liệu. Draft và displayOrder ở bộ nhớ, mất khi reload/đóng app.

ApiService có khóa ghi cùng Family, registry phiên mới và revision để làm mới dữ liệu. API12 cấp EDIT5h/phiên7ngày; về VIEW chỉ đổi UI. Không tự retry ghi. API23 chưa có receipt/idempotency; requestId không chống tạo trùng.

## Dùng sơ đồ

Bấm bút ở cụm bên phải để EDIT/MH07. Nút + trên thẻ mở cha/mẹ, trái/phải mở phối ngẫu, dưới mở con. Lựa chọn hợp lệ theo snapshot+draft, cần preview/xác nhận trước nối. Toolbar dọc cao hơn giữa mép phải; không nút zoom, dùng chuột/cử chỉ. Vừa màn hình cùng cụm. Chú giải màu/nét cố định dưới canvas.

Lưu sơ đồ gọi23; thành công kiểm tra Family/requestId/version/map rồi đóng draft và tải16. GET lỗi chỉ tải lại, không POST lại. 409/kết quả chưa rõ khóa ghi, giữ draft. Trước API05/03/09 và rời Family xử lý Lưu/Bỏ/Hủy.

## Kiểm thử và minh chứng

```powershell
flutter analyze --no-pub
$env:GENERATE_PREVIEWS = 'true'
$env:PREVIEW_FONT_PATH = 'C:/Windows/Fonts/arial.ttf'
flutter test --no-pub --reporter expanded
flutter build web --no-pub --no-wasm-dry-run
```

MockClient/MemoryStorage/widget test không thay E2E Edge/backend hoặc kiểm thử plugin trên Android. [Trạng thái29/10](../outputs/PROJECT-STATUS-2026-10-29.md) phân biệt mốc89/90test, các lần kiểm tra7test và preview cuối; không coi build trước tinh chỉnh là build mới. [Kế hoạch nghiệm thu](../NEXT_STEPS.md).

## Debug trên Edge (25/10/2026)

Ưu tiên chạy Web trước Android: xem [hướng dẫn Edge, CORS và hai terminal](docs/edge-debug.md). Backend cần profile web-debug; frontend chạy đúng localhost:5173, API localhost:8080. Có run-edge.ps1 và cấu hình F5 trong .vscode/launch.json.


## Debug trong Android Studio / IntelliJ

Chọn GiaPha - Flutter Web Debug, thiết bị Edge và nhấn Debug. Xem [hướng dẫn IDE và breakpoint](docs/ide-debug.md).
