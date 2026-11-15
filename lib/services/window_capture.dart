/// Win32 游戏窗口截图采集与纯 Dart PNG 编码器。
///
/// 通过 `user32.dll` / `gdi32.dll` 捕获指定 PID 所属游戏窗口的客户区画面，
/// 并在后台 Isolate 通过 `dart:io` 的 `ZLibCodec` 编码为标准 PNG 文件保存。
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'process_monitor.dart';

final _user32 = DynamicLibrary.open('user32.dll');
final _gdi32 = DynamicLibrary.open('gdi32.dll');

final _getForegroundWindow = _user32
    .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'GetForegroundWindow');
final _getTopWindow = _user32.lookupFunction<
    Pointer<Void> Function(Pointer<Void>),
    Pointer<Void> Function(Pointer<Void>)>('GetTopWindow');
final _getWindow = _user32.lookupFunction<
    Pointer<Void> Function(Pointer<Void>, Uint32),
    Pointer<Void> Function(Pointer<Void>, int)>('GetWindow');
final _getWindowThreadProcessId = _user32.lookupFunction<
    Uint32 Function(Pointer<Void>, Pointer<Uint32>),
    int Function(Pointer<Void>, Pointer<Uint32>)>('GetWindowThreadProcessId');
final _isWindowVisible = _user32.lookupFunction<Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('IsWindowVisible');
final _isIconic = _user32.lookupFunction<Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('IsIconic');
final _getClientRect = _user32.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<_RECT>),
    int Function(Pointer<Void>, Pointer<_RECT>)>('GetClientRect');
final _getWindowRect = _user32.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<_RECT>),
    int Function(Pointer<Void>, Pointer<_RECT>)>('GetWindowRect');
final _clientToScreen = _user32.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<_POINT>),
    int Function(Pointer<Void>, Pointer<_POINT>)>('ClientToScreen');
final _printWindow = _user32.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Void>, Uint32),
    int Function(Pointer<Void>, Pointer<Void>, int)>('PrintWindow');
final _getDC = _user32.lookupFunction<Pointer<Void> Function(Pointer<Void>),
    Pointer<Void> Function(Pointer<Void>)>('GetDC');
final _releaseDC = _user32.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Void>),
    int Function(Pointer<Void>, Pointer<Void>)>('ReleaseDC');
final _getAsyncKeyState = _user32.lookupFunction<Int16 Function(Int32),
    int Function(int)>('GetAsyncKeyState');

final _createCompatibleDC = _gdi32.lookupFunction<
    Pointer<Void> Function(Pointer<Void>),
    Pointer<Void> Function(Pointer<Void>)>('CreateCompatibleDC');
final _deleteDC = _gdi32.lookupFunction<Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('DeleteDC');
final _selectObject = _gdi32.lookupFunction<
    Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
    Pointer<Void> Function(Pointer<Void>, Pointer<Void>)>('SelectObject');
final _deleteObject = _gdi32.lookupFunction<Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('DeleteObject');
final _bitBlt = _gdi32.lookupFunction<
    Int32 Function(Pointer<Void>, Int32, Int32, Int32, Int32, Pointer<Void>,
        Int32, Int32, Uint32),
    int Function(Pointer<Void>, int, int, int, int, Pointer<Void>, int, int,
        int)>('BitBlt');
final _createDIBSection = _gdi32.lookupFunction<
    Pointer<Void> Function(Pointer<Void>, Pointer<_BITMAPINFO>, Uint32,
        Pointer<Pointer<Void>>, Pointer<Void>, Uint32),
    Pointer<Void> Function(Pointer<Void>, Pointer<_BITMAPINFO>, int,
        Pointer<Pointer<Void>>, Pointer<Void>, int)>('CreateDIBSection');

const int _gwHwndNext = 2;
const int _pwClientOnly = 1;
const int _pwRenderFullContent = 2;
const int _srccopy = 0x00CC0020;

final class _RECT extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

final class _POINT extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

final class _BITMAPINFO extends Struct {
  @Uint32()
  external int biSize;
  @Int32()
  external int biWidth;
  @Int32()
  external int biHeight;
  @Uint16()
  external int biPlanes;
  @Uint16()
  external int biBitCount;
  @Uint32()
  external int biCompression;
  @Uint32()
  external int biSizeImage;
  @Int32()
  external int biXPelsPerMeter;
  @Int32()
  external int biYPelsPerMeter;
  @Uint32()
  external int biClrUsed;
  @Uint32()
  external int biClrImportant;
  @Uint32()
  external int bmiColors;
}

class WindowCaptureService {
  /// 设置页可选的游玩路径全局截图按键。
  static const List<({String id, String label})> hotkeyChoices = [
    (id: 'F12', label: 'F12 (默认)'),
    (id: 'F11', label: 'F11'),
    (id: 'F9', label: 'F9'),
    (id: 'F8', label: 'F8'),
    (id: 'PrintScreen', label: 'PrtSc'),
    (id: 'disabled', label: '关闭快捷键'),
  ];

  static const Map<String, int> _vkMap = {
    'F1': 0x70,
    'F2': 0x71,
    'F3': 0x72,
    'F4': 0x73,
    'F5': 0x74,
    'F6': 0x75,
    'F7': 0x76,
    'F8': 0x77,
    'F9': 0x78,
    'F10': 0x79,
    'F11': 0x7A,
    'F12': 0x7B,
    'PRINTSCREEN': 0x2C,
    'PRTSC': 0x2C,
    'SCROLLLOCK': 0x91,
    'PAUSE': 0x13,
    'INSERT': 0x2D,
  };

  /// 将键名（如 `'F12'` / `'PrintScreen'`）解析为 Win32 Virtual-Key code。
  static int? virtualKeyForName(String name) {
    final trimmed = name.trim().toUpperCase();
    if (trimmed.isEmpty || trimmed == 'DISABLED' || trimmed == 'NONE') {
      return null;
    }
    return _vkMap[trimmed];
  }

  /// 检查指定 Win32 虚拟键当前是否处于按下状态。
  static bool isVirtualKeyDown(int vk) {
    if (!Platform.isWindows) return false;
    final state = _getAsyncKeyState(vk);
    return (state & 0x8000) != 0;
  }

  /// 查找属于 [pids] 集合的最前端可见非最小化游戏窗口句柄。
  static Pointer<Void>? findGameWindow(Set<int> pids) {
    if (!Platform.isWindows || pids.isEmpty) return null;

    final fg = _getForegroundWindow();
    if (fg != nullptr && _matchesVisibleGameWindow(fg, pids)) {
      return fg;
    }

    var hwnd = _getTopWindow(nullptr);
    var guard = 0;
    while (hwnd != nullptr && guard < 1500) {
      if (_matchesVisibleGameWindow(hwnd, pids)) {
        return hwnd;
      }
      hwnd = _getWindow(hwnd, _gwHwndNext);
      guard++;
    }
    return null;
  }

  static int _windowPid(Pointer<Void> hwnd) {
    final outPid = calloc<Uint32>();
    try {
      _getWindowThreadProcessId(hwnd, outPid);
      return outPid.value;
    } finally {
      calloc.free(outPid);
    }
  }

  static bool _matchesVisibleGameWindow(Pointer<Void> hwnd, Set<int> pids) {
    if (hwnd == nullptr) return false;
    final pid = _windowPid(hwnd);
    if (!pids.contains(pid)) return false;
    if (_isWindowVisible(hwnd) == 0 || _isIconic(hwnd) != 0) return false;
    final rc = calloc<_RECT>();
    try {
      if (_getClientRect(hwnd, rc) == 0) return false;
      final w = rc.ref.right - rc.ref.left;
      final h = rc.ref.bottom - rc.ref.top;
      return w >= 120 && h >= 80;
    } finally {
      calloc.free(rc);
    }
  }

  /// 从 [candidatePids] 中查找游戏窗口并截取画面保存到 [outputPath]（PNG）。
  /// 成功返回写入后的文件路径，找不到窗口或采集失败返回 `null`。
  static Future<String?> captureGameWindowToFile({
    required Set<int> candidatePids,
    required String outputPath,
  }) async {
    if (!Platform.isWindows) return null;

    var pids = candidatePids;
    if (pids.isEmpty) {
      final fg = foregroundPid();
      if (fg > 0) pids = {fg};
    }

    final hwnd = findGameWindow(pids);
    if (hwnd == null) return null;

    final raw = _captureHwndBgra(hwnd);
    if (raw == null) return null;

    final pngBytes = await Isolate.run(
      () => encodeBgraToPng(raw.bytes, raw.width, raw.height),
    );
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(pngBytes, flush: true);
    return file.path;
  }

  static ({Uint8List bytes, int width, int height})? _captureHwndBgra(
    Pointer<Void> hwnd,
  ) {
    final clientRc = calloc<_RECT>();
    final windowRc = calloc<_RECT>();
    final origin = calloc<_POINT>();
    final bmi = calloc<_BITMAPINFO>();
    final ppvBits = calloc<Pointer<Void>>();

    Pointer<Void> screenDc = nullptr;
    Pointer<Void> memDc = nullptr;
    Pointer<Void> hBitmap = nullptr;
    Pointer<Void> oldObj = nullptr;

    try {
      var useClient = true;
      var w = 0;
      var h = 0;
      if (_getClientRect(hwnd, clientRc) != 0) {
        w = clientRc.ref.right - clientRc.ref.left;
        h = clientRc.ref.bottom - clientRc.ref.top;
      }
      if (w < 120 || h < 80) {
        useClient = false;
        if (_getWindowRect(hwnd, windowRc) == 0) return null;
        w = windowRc.ref.right - windowRc.ref.left;
        h = windowRc.ref.bottom - windowRc.ref.top;
      }
      if (w <= 0 || h <= 0 || w > 7680 || h > 4320) return null;

      screenDc = _getDC(nullptr);
      if (screenDc == nullptr) return null;
      memDc = _createCompatibleDC(screenDc);
      if (memDc == nullptr) return null;

      bmi.ref.biSize = sizeOf<_BITMAPINFO>() - 4; // sizeof(BITMAPINFOHEADER) == 40
      bmi.ref.biWidth = w;
      bmi.ref.biHeight = -h; // top-down DIB
      bmi.ref.biPlanes = 1;
      bmi.ref.biBitCount = 32;
      bmi.ref.biCompression = 0; // BI_RGB
      bmi.ref.biSizeImage = w * h * 4;

      hBitmap = _createDIBSection(memDc, bmi, 0, ppvBits, nullptr, 0);
      if (hBitmap == nullptr || ppvBits.value == nullptr) return null;
      oldObj = _selectObject(memDc, hBitmap);

      final byteLen = w * h * 4;
      final pixelPtr = ppvBits.value.cast<Uint8>();
      var captured = false;

      // 优先 PrintWindow(PW_CLIENTONLY | PW_RENDERFULLCONTENT) 支持 DWM/DX/WebView2 内容
      final pwFlags =
          useClient ? (_pwClientOnly | _pwRenderFullContent) : _pwRenderFullContent;
      if (_printWindow(hwnd, memDc, pwFlags) != 0) {
        final sample = pixelPtr.asTypedList(byteLen);
        if (!_looksBlankOrBlack(sample, w, h)) {
          captured = true;
        }
      }

      // 回退 PrintWindow(PW_RENDERFULLCONTENT)
      if (!captured && useClient) {
        if (_printWindow(hwnd, memDc, _pwRenderFullContent) != 0) {
          final sample = pixelPtr.asTypedList(byteLen);
          if (!_looksBlankOrBlack(sample, w, h)) {
            captured = true;
          }
        }
      }

      // 回退：若目标窗口或屏幕区域在前台可见，使用 BitBlt 抓屏区域
      if (!captured) {
        origin.ref.x = 0;
        origin.ref.y = 0;
        if (useClient && _clientToScreen(hwnd, origin) != 0) {
          if (_bitBlt(memDc, 0, 0, w, h, screenDc, origin.ref.x, origin.ref.y,
                  _srccopy) !=
              0) {
            captured = true;
          }
        } else if (_getWindowRect(hwnd, windowRc) != 0) {
          if (_bitBlt(memDc, 0, 0, w, h, screenDc, windowRc.ref.left,
                  windowRc.ref.top, _srccopy) !=
              0) {
            captured = true;
          }
        }
      }

      if (!captured) return null;
      final copy = Uint8List.fromList(pixelPtr.asTypedList(byteLen));
      return (bytes: copy, width: w, height: h);
    } finally {
      if (memDc != nullptr && oldObj != nullptr) {
        _selectObject(memDc, oldObj);
      }
      if (hBitmap != nullptr) {
        _deleteObject(hBitmap);
      }
      if (memDc != nullptr) {
        _deleteDC(memDc);
      }
      if (screenDc != nullptr) {
        _releaseDC(nullptr, screenDc);
      }
      calloc.free(clientRc);
      calloc.free(windowRc);
      calloc.free(origin);
      calloc.free(bmi);
      calloc.free(ppvBits);
    }
  }

  static bool _looksBlankOrBlack(Uint8List bgra, int width, int height) {
    final stepX = (width ~/ 12).clamp(1, width);
    final stepY = (height ~/ 12).clamp(1, height);
    for (var y = stepY ~/ 2; y < height; y += stepY) {
      final rowOffset = y * width * 4;
      for (var x = stepX ~/ 2; x < width; x += stepX) {
        final i = rowOffset + x * 4;
        if (bgra[i] > 6 || bgra[i + 1] > 6 || bgra[i + 2] > 6) {
          return false;
        }
      }
    }
    return true;
  }
}

/// 纯 Dart BGRA -> RGBA 标准 PNG 编码（可在后台 Isolate 执行，零外部依赖）。
///
/// 强制输出不透明 Alpha (255)，避免 Win32 GDI/PrintWindow 保留位为 0 导致透明黑屏。
Uint8List encodeBgraToPng(Uint8List bgra, int width, int height) {
  if (width <= 0 || height <= 0) {
    throw ArgumentError('Invalid image size: ${width}x$height');
  }
  final expectedLen = width * height * 4;
  if (bgra.length < expectedLen) {
    throw ArgumentError(
        'BGRA buffer length ${bgra.length} < expected $expectedLen');
  }

  final stride = width * 4;
  final raw = Uint8List(height * (1 + stride));
  var outIdx = 0;
  var inIdx = 0;
  for (var y = 0; y < height; y++) {
    raw[outIdx++] = 0; // PNG filter type 0 (None)
    for (var x = 0; x < width; x++) {
      final b = bgra[inIdx];
      final g = bgra[inIdx + 1];
      final r = bgra[inIdx + 2];
      inIdx += 4;
      raw[outIdx++] = r;
      raw[outIdx++] = g;
      raw[outIdx++] = b;
      raw[outIdx++] = 255;
    }
  }

  final compressed = Uint8List.fromList(ZLibCodec(level: 3).encode(raw));

  final ihdr = Uint8List(13);
  final ihdrView = ByteData.sublistView(ihdr);
  ihdrView.setUint32(0, width, Endian.big);
  ihdrView.setUint32(4, height, Endian.big);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // color type: RGBA
  ihdr[10] = 0; // compression
  ihdr[11] = 0; // filter
  ihdr[12] = 0; // interlace

  final out = BytesBuilder(copy: false);
  out.add(const [137, 80, 78, 71, 13, 10, 26, 10]); // PNG signature
  _writeChunk(out, const [73, 72, 68, 82], ihdr); // IHDR
  _writeChunk(out, const [73, 68, 65, 84], compressed); // IDAT
  _writeChunk(out, const [73, 69, 78, 68], const []); // IEND
  return out.takeBytes();
}

void _writeChunk(BytesBuilder out, List<int> type4, List<int> data) {
  final header = Uint8List(4);
  ByteData.sublistView(header).setUint32(0, data.length, Endian.big);
  out.add(header);
  out.add(type4);
  if (data.isNotEmpty) {
    out.add(data);
  }
  final crc = _crc32(type4, data);
  final crcBytes = Uint8List(4);
  ByteData.sublistView(crcBytes).setUint32(0, crc, Endian.big);
  out.add(crcBytes);
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
  }
  return c;
}, growable: false);

int _crc32(List<int> type4, List<int> data) {
  var c = 0xffffffff;
  for (final b in type4) {
    c = _crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
  }
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
  }
  return c ^ 0xffffffff;
}
