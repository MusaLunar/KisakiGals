/// 游玩时长监控的 Win32 基础：进程枚举 + 前台窗口检测。
/// 使用 dart:ffi 结构体（由 FFI 自动处理 x64 对齐）。
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _user32 = DynamicLibrary.open('user32.dll');

final _createSnapshot = _kernel32
    .lookupFunction<Pointer<Void> Function(Uint32, Uint32),
        Pointer<Void> Function(int, int)>('CreateToolhelp32Snapshot');
final _process32First = _kernel32
    .lookupFunction<Int32 Function(Pointer<Void>, Pointer<PROCESSENTRY32W>),
        int Function(
            Pointer<Void>, Pointer<PROCESSENTRY32W>)>('Process32FirstW');
final _process32Next = _kernel32
    .lookupFunction<Int32 Function(Pointer<Void>, Pointer<PROCESSENTRY32W>),
        int Function(
            Pointer<Void>, Pointer<PROCESSENTRY32W>)>('Process32NextW');
final _closeHandle = _kernel32
    .lookupFunction<IntPtr Function(Pointer<Void>), int Function(Pointer<Void>)>(
        'CloseHandle');
final _getForegroundWindow = _user32
    .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'GetForegroundWindow');
final _getWindowThreadProcessId =
    _user32.lookupFunction<Uint32 Function(Pointer<Void>, Pointer<Uint32>),
        int Function(Pointer<Void>, Pointer<Uint32>)>(
        'GetWindowThreadProcessId');

const int _th32csSnapProcess = 0x2;

final class PROCESSENTRY32W extends Struct {
  @Uint32()
  external int dwSize;
  @Uint32()
  external int cntUsage;
  @Uint32()
  external int th32ProcessID;
  @UintPtr()
  external int th32DefaultHeapID;
  @Uint32()
  external int th32ModuleID;
  @Uint32()
  external int cntThreads;
  @Uint32()
  external int th32ParentProcessID;
  @Int32()
  external int pcPriClassBase;
  @Uint32()
  external int dwFlags;
  @Array(260)
  external Array<Uint16> szExeFile;
}

class ProcInfo {
  final int pid;
  final int ppid;
  final String exeFile; // 仅文件名（不含路径）
  const ProcInfo(this.pid, this.ppid, this.exeFile);
}

/// 枚举系统全部进程。
List<ProcInfo> enumerateProcesses() {
  final snapshot = _createSnapshot(_th32csSnapProcess, 0);
  if (snapshot == Pointer.fromAddress(0)) return const [];
  final entry = malloc<PROCESSENTRY32W>();
  try {
    entry.ref.dwSize = sizeOf<PROCESSENTRY32W>();
    final result = <ProcInfo>[];
    if (_process32First(snapshot, entry) != 0) {
      _read(entry.ref, result);
      while (_process32Next(snapshot, entry) != 0) {
        _read(entry.ref, result);
      }
    }
    return result;
  } finally {
    malloc.free(entry);
    _closeHandle(snapshot);
  }
}

void _read(PROCESSENTRY32W e, List<ProcInfo> out) {
  final units = e.szExeFile;
  final name = String.fromCharCodes(
    List<int>.generate(260, (i) => units[i]).takeWhile((c) => c != 0),
  );
  out.add(ProcInfo(e.th32ProcessID, e.th32ParentProcessID, name));
}

/// 前台窗口所属进程 PID；无前台窗口返回 0。
int foregroundPid() {
  final hwnd = _getForegroundWindow();
  if (hwnd == Pointer.fromAddress(0)) return 0;
  final pidPtr = malloc<Uint32>();
  try {
    _getWindowThreadProcessId(hwnd, pidPtr);
    return pidPtr.value;
  } finally {
    malloc.free(pidPtr);
  }
}
