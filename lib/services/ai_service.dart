/// AI 助手服务：OpenAI 兼容 chat completions（支持任意 baseUrl），
/// 结合游玩数据生成智能总结与作品推荐。
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

class AiConfig {
  final String baseUrl;
  final String apiKey;
  final String model;
  const AiConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  bool get ready => baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty && model.trim().isNotEmpty;

  /// 端点：允许用户填到 /v1 为止，自动补 /chat/completions。
  String get endpoint {
    var b = baseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    return '$b/chat/completions';
  }
}

class AiResult {
  final bool ok;
  final String content;
  final String message;
  const AiResult(this.ok, this.content, this.message);
}

/// 推荐条目（AI 返回 JSON 解析而来）。
class AiRecommendation {
  final String title;
  final String reason;
  final List<String> tags;
  AiRecommendation({required this.title, this.reason = '', this.tags = const []});

  static AiRecommendation fromMap(Map<String, dynamic> m) => AiRecommendation(
        title: (m['title'] ?? m['name'] ?? '').toString().trim(),
        reason: (m['reason'] ?? m['comment'] ?? '').toString().trim(),
        tags: [
          for (final t in (m['tags'] as List?) ?? [])
            if (t.toString().trim().isNotEmpty) t.toString().trim(),
        ],
      );
}

class AiService {
  final String? proxy;
  Dio? _dioProxied;
  Dio? _dioDirect;

  AiService({this.proxy});

  Dio _directDio() =>
      _dioDirect ??= Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 120),
      ));

  Dio _proxiedDio() {
    // HttpClient 只创建一次（原实现每次调用都重新赋值 adapter，
    // 等于每次请求新建连接池并丢弃旧的）
    return _dioProxied ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 120),
    ))
      ..httpClientAdapter = (IOHttpClientAdapter()
        ..createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (uri) =>
              'PROXY ${proxy!.replaceFirst(RegExp(r'^https?://'), '')}';
          return client;
        });
  }

  /// 候选通道：非本地优先代理；本地端点先直连，
  /// 连接层失败时降级走代理（兼容 TUN/系统钩子劫持 loopback 的环境）。
  List<Dio> _candidates(AiConfig config) {
    final host = Uri.tryParse(config.baseUrl)?.host ?? '';
    final isLocal = host == '127.0.0.1' ||
        host == 'localhost' ||
        host.endsWith('.local');
    if (isLocal) {
      return proxy == null ? [_directDio()] : [_directDio(), _proxiedDio()];
    }
    // 远端端点：配了代理就先走代理，但**保留直连兜底** ——
    // 系统代理常是残留配置（Clash 已退出），只走代理会直接失败
    return proxy == null ? [_directDio()] : [_proxiedDio(), _directDio()];
  }

  /// 调用 chat completions。[temperature] 默认 0.8；
/// [maxTokens] 默认 4000（推理模型会先消耗推理额度，给少了正文会为空）。
  Future<AiResult> chat({
    required AiConfig config,
    required String system,
    required String user,
    double temperature = 0.8,
    int maxTokens = 4000,
  }) async {
    if (!config.ready) {
      return const AiResult(false, '', '请先在「设置 → AI」填写 Base URL、API Key 与模型名称');
    }
    final options = Options(headers: {
      'Authorization': 'Bearer ${config.apiKey}',
      'Content-Type': 'application/json',
    });
    final payload = {
      'model': config.model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'temperature': temperature,
      'max_tokens': maxTokens,
    };
    Response? response;
    DioException? lastConnectionError;
    for (final dio in _candidates(config)) {
      try {
        response = await dio.post(config.endpoint,
            options: options, data: payload);
        break;
      } on DioException catch (e) {
        if (e.response == null) {
          lastConnectionError = e; // 连接层失败：尝试下一通道
          continue;
        }
        return _mapError(e);
      }
    }
    if (response == null) {
      return AiResult(
          false,
          '',
          lastConnectionError == null
              ? '未知错误'
              : '连接失败：${lastConnectionError.type.name}（本地端点被安全软件/代理劫持时可改用 LAN 地址）');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    final choices = (data['choices'] as List?) ?? [];
    if (choices.isEmpty) {
      return AiResult(false, '', 'AI 返回为空（${data['error'] ?? '无 choices'}）');
    }
    final first = Map<String, dynamic>.from(choices.first as Map);
    final message = Map<String, dynamic>.from((first['message'] ?? {}) as Map);
    var content = (message['content'] ?? '').toString().trim();
    // 推理模型（deepseek-flash / deepseek-reasoner 等）会先输出
    // reasoning_content；若 token 上限被推理过程吃光，content 会是空串
    final reasoning = (message['reasoning_content'] ?? '').toString().trim();
    final finish = (first['finish_reason'] ?? '').toString();
    if (content.isEmpty && reasoning.isNotEmpty) {
      // 有推理内容但正文为空：多半是被 max_tokens 截断
      return AiResult(true, reasoning,
          finish == 'length'
              ? '已被 token 上限截断（当前模型为推理模型，请在设置中调大「最大回复长度」）'
              : '已返回推理内容');
    }
    if (content.isEmpty) {
      return AiResult(
          false,
          '',
          finish == 'length'
              ? 'AI 在 token 上限内未产出正文：当前模型会先消耗推理额度，请调大「最大回复长度」'
              : 'AI 返回内容为空');
    }
    return AiResult(true, content, 'ok');
  }

  AiResult _mapError(DioException e) {
    final code = e.response?.statusCode;
    if (code == 401) {
      return const AiResult(false, '', '鉴权失败：请检查 API Key');
    }
    final body = e.response?.data;
    String detail = '';
    if (body is Map && body['error'] is Map) {
      detail = (Map.from(body['error'] as Map)['message'] ?? '').toString();
    }
    return AiResult(false, '', '请求失败（HTTP $code）${detail.isEmpty ? '' : '：$detail'}');
  }

  /// 解析推荐 JSON（容忍 ```json 围栏与前后杂文）。
  List<AiRecommendation> parseRecommendations(String raw) {
    var text = raw.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', multiLine: true);
    final m = fence.firstMatch(text);
    if (m != null) text = m.group(1)!.trim();
    // 截取最外层 JSON 数组
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start == -1 || end <= start) return [];
    text = text.substring(start, end + 1);
    try {
      final list = jsonDecode(text) as List;
      return [
        for (final e in list)
          if (e is Map)
            AiRecommendation.fromMap(Map<String, dynamic>.from(e))
      ].where((r) => r.title.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }
}
