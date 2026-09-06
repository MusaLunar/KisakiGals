// dart run tool/screenshot.dart <vm_service_uri> <out.png>
import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  final uri = args[0];
  final out = args[1];
  final vm = await vmServiceConnectUri(uri.replaceAll('http://', 'ws://'));
  final inst = await vm.callMethod('_flutter.screenshot');
  final b64 = (inst.json?['screenshot'] as String?) ?? '';
  if (b64.isEmpty) {
    stderr.writeln('no screenshot in response');
    exit(1);
  }
  await File(out).writeAsBytes(base64Decode(b64));
  stdout.writeln('saved $out (${b64.length} b64 chars)');
  await vm.dispose();
}
