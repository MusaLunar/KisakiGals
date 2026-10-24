/// GitHub Releases 检查更新服务。
///
/// 通过 GitHub REST API 查询 `MusaLunar/KisakiGals` 的最新 Release / Tag，
/// 比较语义化版本号（支持 `v1.1.0`、`1.0.1`、`0.9.1-beta` 等格式），
/// 并提取 Windows 安装包/压缩包下载链接与更新日志。
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../core/constants.dart';

class UpdateCheckResult {
  final bool ok;
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String releaseTitle;
  final String releaseNotes;
  final String htmlUrl;
  final String? downloadUrl;
  final String? publishedAt;
  final String message;

  const UpdateCheckResult({
    required this.ok,
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    this.releaseTitle = '',
    this.releaseNotes = '',
    this.htmlUrl = '',
    this.downloadUrl,
    this.publishedAt,
    required this.message,
  });
}

class GithubUpdateChecker {
  static const _owner = 'MusaLunar';
  static const _repo = 'KisakiGals';
  static const _latestReleaseUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';
  static const _releasesListUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases?per_page=5';
  static const _tagsListUrl =
      'https://api.github.com/repos/$_owner/$_repo/tags?per_page=5';

  final String? proxy;

  GithubUpdateChecker({this.proxy});

  Dio _buildDio({required bool useProxy}) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'MusaLunar/${AppInfo.name}/${AppInfo.version}',
        'X-GitHub-Api-Version': '2022-11-28',
      },
      validateStatus: (s) => s != null && s < 500,
    ));
    if (useProxy && proxy != null && proxy!.trim().isNotEmpty) {
      dio.httpClientAdapter = IOHttpClientAdapter()
        ..createHttpClient = () {
          final client = HttpClient();
          client.findProxy =
              (uri) => 'PROXY ${proxy!.replaceFirst(RegExp(r'^https?://'), '')}';
          return client;
        };
    }
    return dio;
  }

  /// 检查是否有新版本。若配置了代理且代理握手失败，自动回退直连重试一次。
  Future<UpdateCheckResult> check({
    String currentVersion = AppInfo.version,
  }) async {
    final hasProxy = proxy != null && proxy!.trim().isNotEmpty;
    try {
      return await _checkWithDio(_buildDio(useProxy: hasProxy), currentVersion);
    } catch (e) {
      if (hasProxy) {
        try {
          return await _checkWithDio(_buildDio(useProxy: false), currentVersion);
        } catch (e2) {
          return _errorResult(currentVersion, e2);
        }
      }
      return _errorResult(currentVersion, e);
    }
  }

  Future<UpdateCheckResult> _checkWithDio(
      Dio dio, String currentVersion) async {
    try {
      // 1. 优先请求 /releases/latest（正式版）
      final r = await dio.get(_latestReleaseUrl);
      if (r.statusCode == 200 && r.data is Map) {
        return _parseReleaseMap(
            Map<String, dynamic>.from(r.data as Map), currentVersion);
      }

      // 2. 若仓库仅发布了 Pre-release 或尚未标记 latest，回退查询 /releases 列表首项
      if (r.statusCode == 404) {
        final listResp = await dio.get(_releasesListUrl);
        if (listResp.statusCode == 200 &&
            listResp.data is List &&
            (listResp.data as List).isNotEmpty) {
          final first = (listResp.data as List).first;
          if (first is Map) {
            return _parseReleaseMap(
                Map<String, dynamic>.from(first), currentVersion);
          }
        }

        // 3. 若尚未创建 Release，回退查询 Git Tags
        final tagResp = await dio.get(_tagsListUrl);
        if (tagResp.statusCode == 200 && tagResp.data is List) {
          final tags = tagResp.data as List;
          if (tags.isEmpty) {
            return UpdateCheckResult(
              ok: true,
              hasUpdate: false,
              currentVersion: currentVersion,
              latestVersion: currentVersion,
              htmlUrl: '${AppInfo.repository}/releases',
              message: '当前已是最新版本 v$currentVersion',
            );
          }
          final firstTag = Map<String, dynamic>.from(tags.first as Map);
          final tagName = cleanVersion('${firstTag['name'] ?? ''}');
          final hasNew = compareVersions(tagName, currentVersion) > 0;
          return UpdateCheckResult(
            ok: true,
            hasUpdate: hasNew,
            currentVersion: currentVersion,
            latestVersion: tagName.isEmpty ? currentVersion : tagName,
            releaseTitle: 'v$tagName',
            htmlUrl: '${AppInfo.repository}/releases',
            message: hasNew
                ? '发现新版本 v$tagName（当前 v$currentVersion）'
                : '当前已是最新版本 v$currentVersion',
          );
        }
      }

      if (r.statusCode == 403 || r.statusCode == 429) {
        return UpdateCheckResult(
          ok: false,
          hasUpdate: false,
          currentVersion: currentVersion,
          latestVersion: currentVersion,
          htmlUrl: '${AppInfo.repository}/releases',
          message: 'GitHub API 请求受限（HTTP ${r.statusCode}），请稍后再试',
        );
      }

      return UpdateCheckResult(
        ok: false,
        hasUpdate: false,
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        htmlUrl: '${AppInfo.repository}/releases',
        message: '检查更新失败（HTTP ${r.statusCode}）',
      );
    } finally {
      dio.close(force: true);
    }
  }

  UpdateCheckResult _parseReleaseMap(
      Map<String, dynamic> m, String currentVersion) {
    final rawTag = (m['tag_name'] ?? m['name'] ?? '').toString().trim();
    final latest = cleanVersion(rawTag);
    final title = (m['name'] ?? rawTag).toString().trim();
    final body = (m['body'] ?? '').toString().trim();
    final htmlUrl =
        (m['html_url'] ?? '${AppInfo.repository}/releases').toString().trim();
    final publishedAt = (m['published_at'] ?? '').toString().trim();

    String? downloadUrl;
    final assets = (m['assets'] as List?) ?? const [];
    for (final a in assets) {
      if (a is! Map) continue;
      final am = Map<String, dynamic>.from(a);
      final name = (am['name'] ?? '').toString().toLowerCase();
      final url = (am['browser_download_url'] ?? '').toString().trim();
      if (url.isEmpty) continue;
      if (name.endsWith('.exe') ||
          name.endsWith('.zip') ||
          name.endsWith('.7z') ||
          name.endsWith('.msix')) {
        downloadUrl = url;
        if (name.contains('setup') ||
            name.contains('installer') ||
            name.endsWith('.exe')) {
          break;
        }
      }
    }

    if (latest.isEmpty) {
      return UpdateCheckResult(
        ok: true,
        hasUpdate: false,
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        htmlUrl: htmlUrl,
        message: '当前已是最新版本 v$currentVersion',
      );
    }

    final hasNew = compareVersions(latest, currentVersion) > 0;
    return UpdateCheckResult(
      ok: true,
      hasUpdate: hasNew,
      currentVersion: currentVersion,
      latestVersion: latest,
      releaseTitle: title.isEmpty ? 'v$latest' : title,
      releaseNotes: body,
      htmlUrl: htmlUrl,
      downloadUrl: downloadUrl,
      publishedAt: publishedAt.length >= 10
          ? publishedAt.substring(0, 10)
          : publishedAt,
      message: hasNew
          ? '发现新版本 v$latest（当前 v$currentVersion）'
          : '当前已是最新版本 v$currentVersion',
    );
  }

  UpdateCheckResult _errorResult(String currentVersion, Object e) {
    final s = e.toString().toLowerCase();
    String msg = '无法连接 GitHub 检查更新，请检查网络或代理设置';
    if (s.contains('timeout') || s.contains('timed out')) {
      msg = '连接 GitHub 超时，请检查网络或代理设置';
    }
    return UpdateCheckResult(
      ok: false,
      hasUpdate: false,
      currentVersion: currentVersion,
      latestVersion: currentVersion,
      htmlUrl: '${AppInfo.repository}/releases',
      message: msg,
    );
  }

  /// 去掉前缀 `v`/`V` 及构建号 `+...`。
  static String cleanVersion(String raw) {
    var s = raw.trim();
    s = s.replaceFirst(RegExp(r'^[vV]\s*'), '');
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    return s.trim();
  }

  /// 比较两个语义化版本号：
  /// `> 0` 表示 `a > b`；`== 0` 表示相等；`< 0` 表示 `a < b`。
  /// 正式版高于同主次修订号的预发布版（如 `1.1.0 > 1.1.0-beta`）。
  static int compareVersions(String a, String b) {
    final ca = cleanVersion(a);
    final cb = cleanVersion(b);
    if (ca == cb) return 0;

    final aParts = ca.split('-');
    final bParts = cb.split('-');
    final aNums = aParts.first
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'\D'), '')) ?? 0)
        .toList();
    final bNums = bParts.first
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'\D'), '')) ?? 0)
        .toList();

    final maxLen = aNums.length > bNums.length ? aNums.length : bNums.length;
    for (var i = 0; i < maxLen; i++) {
      final na = i < aNums.length ? aNums[i] : 0;
      final nb = i < bNums.length ? bNums[i] : 0;
      if (na != nb) return na.compareTo(nb);
    }

    // 数字段完全相同时：无后缀（正式版） > 带预发布后缀（如 -beta / -alpha）
    final aPre = aParts.length > 1 ? aParts.sublist(1).join('-') : '';
    final bPre = bParts.length > 1 ? bParts.sublist(1).join('-') : '';
    if (aPre.isEmpty && bPre.isNotEmpty) return 1;
    if (aPre.isNotEmpty && bPre.isEmpty) return -1;
    return aPre.compareTo(bPre);
  }
}
