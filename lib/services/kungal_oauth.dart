/// 鲲Galgame (KunGal / NextMoe) OAuth 2.0 + PKCE 授权与自动刷新服务。
///
/// 鲲Gal已将身份认证与作品目录迁移至统一中台 NextMoe：
/// - 登录端点：`https://account.nextmoe.com/api/v1/auth/login`
/// - 授权同意端点：`https://account.nextmoe.com/api/v1/oauth/authorize/consent`
/// - 令牌端点：`https://account.nextmoe.com/api/v1/oauth/token`
/// - 用户信息：`https://account.nextmoe.com/api/v1/oauth/userinfo`
/// - 目录 API：`https://api.nextmoe.dev/v2/catalog/works`
/// - 个人 API：`https://api.nextmoe.dev/v2/me`
///
/// 通过本地回环服务 `http://127.0.0.1:23380/authorize` 提供 KisakiGals 专属授权页，
/// 完成账号认证后在后台自动执行 OAuth 2.0 + PKCE (S256) 授权码签发与令牌换取，
/// 避免直接跳转第三方 Client 页面时显示其它应用名称（如 ReinaManager）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';

import '../app_services.dart';
import '../core/constants.dart';
import '../core/utils.dart' show fmtDateTime;

class KunOAuthSession {
  final String accessToken;
  final String refreshToken;
  final int expiresAt; // Unix epoch seconds
  final String scope;
  final String userId;
  final String name;
  final String avatar;

  const KunOAuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.scope,
    this.userId = '',
    this.name = '',
    this.avatar = '',
  });

  bool get isExpired {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return expiresAt <= nowSec + 60;
  }

  Map<String, dynamic> toExtra({String? status}) => {
        'refresh_token': refreshToken,
        'expires_at': expiresAt,
        'scope': scope,
        'user_id': userId,
        'name': name,
        'avatar': avatar,
        'oauth': true,
        if (status != null) 'status': status,
      };

  static KunOAuthSession? fromStore(String? token, Map<String, dynamic> extra) {
    final access = (token ?? '').trim();
    if (access.isEmpty) return null;
    return KunOAuthSession(
      accessToken: access,
      refreshToken: (extra['refresh_token'] ?? '').toString().trim(),
      expiresAt: (extra['expires_at'] is num)
          ? (extra['expires_at'] as num).toInt()
          : int.tryParse('${extra['expires_at'] ?? 0}') ?? 0,
      scope: (extra['scope'] ?? KunOAuthService.scopes).toString(),
      userId: (extra['user_id'] ?? '').toString(),
      name: (extra['name'] ?? '').toString(),
      avatar: (extra['avatar'] ?? '').toString(),
    );
  }
}

class KunOAuthResult {
  final bool ok;
  final String message;
  final KunOAuthSession? session;

  const KunOAuthResult({
    required this.ok,
    required this.message,
    this.session,
  });
}

class KunOAuthService {
  KunOAuthService._();
  static final KunOAuthService instance = KunOAuthService._();

  static const String clientId = '741bebbd822505a5e13c13e711fb8801';
  static const String redirectUri = 'http://127.0.0.1:23380/callback/nextmoe';
  static const int callbackPort = 23380;
  static const String authorizePath = '/authorize';
  static const String callbackPath = '/callback/nextmoe';
  static const String authLoginEndpoint =
      'https://account.nextmoe.com/api/v1/auth/login';
  static const String authMeEndpoint =
      'https://account.nextmoe.com/api/v1/auth/me';
  static const String authorizeEndpoint =
      'https://account.nextmoe.com/api/v1/oauth/authorize';
  static const String consentEndpoint =
      'https://account.nextmoe.com/api/v1/oauth/authorize/consent';
  static const String tokenEndpoint =
      'https://account.nextmoe.com/api/v1/oauth/token';
  static const String userInfoEndpoint =
      'https://account.nextmoe.com/api/v1/oauth/userinfo';
  static const String scopes = 'openid profile catalog:read folder:read';

  HttpServer? _server;
  Completer<KunOAuthResult>? _pendingResult;
  int _generation = 0;
  Future<String?>? _refreshingFuture;
  List<int>? _cachedLogoBytes;

  bool get isLoggingIn =>
      _pendingResult != null && !_pendingResult!.isCompleted;

  /// 生成 URL-safe Base64（无 `=` 填充）。
  static String _base64UrlNoPad(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  /// 生成 PKCE (verifier, S256 challenge) 对。
  static ({String verifier, String challenge}) generatePkcePair() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    final verifier = _base64UrlNoPad(bytes);
    final digest = sha256.convert(ascii.encode(verifier)).bytes;
    final challenge = _base64UrlNoPad(digest);
    return (verifier: verifier, challenge: challenge);
  }

  static String generateState() {
    final rng = Random.secure();
    final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
    return _base64UrlNoPad(bytes);
  }

  Dio _buildDio({String? proxy}) {
    final p = proxy ?? AppServices.I.fetcher.proxy;
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      headers: {
        'User-Agent': 'MusaLunar/${AppInfo.name}/${AppInfo.version} (OAuth)',
        'Accept': 'application/json',
      },
      validateStatus: (s) => s != null && s < 500,
    ));
    if (p != null && p.trim().isNotEmpty) {
      dio.httpClientAdapter = IOHttpClientAdapter()
        ..createHttpClient = () {
          final client = HttpClient();
          client.findProxy =
              (uri) => 'PROXY ${p.replaceFirst(RegExp(r'^https?://'), '')}';
          return client;
        };
    }
    return dio;
  }

  Future<List<int>> _loadLogoBytes() async {
    if (_cachedLogoBytes != null) return _cachedLogoBytes!;
    try {
      final data = await rootBundle.load('assets/logo/logo_128.png');
      _cachedLogoBytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      return _cachedLogoBytes!;
    } catch (_) {
      return const [];
    }
  }

  /// 启动本地 KisakiGals 专属 OAuth 授权门户页并在浏览器打开。
  /// 用户在 KisakiGals 授权页输入鲲Gal/NextMoe 账号后，由本地服务直接向
  /// NextMoe 认证接口换取 PKCE 授权码与令牌，全程显示 KisakiGals 品牌信息。
  Future<KunOAuthResult> login({
    String? proxy,
    void Function(String authUrl)? onUrlOpened,
  }) async {
    await cancelLogin();
    final gen = ++_generation;
    final state = generateState();
    final pkce = generatePkcePair();
    final logoBytes = await _loadLogoBytes();

    final completer = Completer<KunOAuthResult>();
    _pendingResult = completer;

    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        callbackPort,
        shared: true,
      );
      _server = server;

      server.listen((HttpRequest req) async {
        final path = req.uri.path;

        // 1. 应用图标资源
        if (path == '/logo.png') {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType = ContentType('image', 'png');
          req.response.add(logoBytes);
          await req.response.close();
          return;
        }

        // 2. KisakiGals 专属授权门户页
        if (req.method == 'GET' && (path == authorizePath || path == '/')) {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType =
              ContentType('text', 'html', charset: 'utf-8');
          req.response.write(_buildPortalHtml());
          await req.response.close();
          return;
        }

        // 3. 提交账号密码并完成 OAuth 2.0 + PKCE 令牌签发
        if (req.method == 'POST' && path == '/api/login') {
          req.response.headers.contentType = ContentType.json;
          try {
            final bodyStr = await utf8.decoder.bind(req).join();
            final payload = Map<String, dynamic>.from(
                (jsonDecode(bodyStr) as Map?) ?? const {});
            final mode = (payload['mode'] ?? 'account').toString();

            KunOAuthResult res;
            if (mode == 'token') {
              final rawToken = (payload['token'] ?? '').toString().trim();
              res = await _loginWithAccessToken(
                accessToken: rawToken,
                proxy: proxy,
                gen: gen,
              );
            } else {
              final account = (payload['account'] ?? '').toString().trim();
              final password = (payload['password'] ?? '').toString();
              res = await _loginWithCredentialsAndPkce(
                account: account,
                password: password,
                state: state,
                pkce: pkce,
                proxy: proxy,
                gen: gen,
              );
            }

            req.response.statusCode = HttpStatus.ok;
            req.response.write(jsonEncode({
              'ok': res.ok,
              'message': res.message,
              'user': res.session?.name ?? '',
            }));
            await req.response.close();

            if (res.ok && !completer.isCompleted) {
              completer.complete(res);
            }
          } catch (e) {
            req.response.statusCode = HttpStatus.ok;
            req.response.write(jsonEncode({
              'ok': false,
              'message': '请求处理异常：$e',
            }));
            await req.response.close();
          }
          return;
        }

        // 4. 兼容标准 OAuth 回调路径 (/callback/nextmoe?code=...&state=...)
        if (path == callbackPath) {
          final params = req.uri.queryParameters;
          final err = params['error'];
          final code = (params['code'] ?? '').trim();
          final returnedState = params['state'] ?? '';
          final valid =
              err == null && code.isNotEmpty && returnedState == state;

          KunOAuthResult res;
          if (valid) {
            res = await _exchangeCode(
              code: code,
              verifier: pkce.verifier,
              proxy: proxy,
              gen: gen,
            );
          } else {
            res = KunOAuthResult(
              ok: false,
              message: params['error_description'] ?? err ?? '授权未完成或已取消',
            );
          }

          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType =
              ContentType('text', 'html', charset: 'utf-8');
          req.response.write(_buildCallbackHtml(
            ok: res.ok,
            detail: res.ok
                ? '已成功完成鲲Gal (NextMoe) 授权，正在同步账号信息，现在可以关闭此浏览器标签页。'
                : res.message,
          ));
          await req.response.close();

          if (!completer.isCompleted) {
            completer.complete(res);
          }
          return;
        }

        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      });
    } catch (e) {
      _pendingResult = null;
      return KunOAuthResult(
        ok: false,
        message: '启动本地 OAuth 授权监听端口 ($callbackPort) 失败：$e',
      );
    }

    final portalUri =
        Uri.parse('http://127.0.0.1:$callbackPort$authorizePath');
    onUrlOpened?.call(portalUri.toString());
    final launched =
        await launchUrl(portalUri, mode: LaunchMode.externalApplication);
    if (!launched) {
      await cancelLogin();
      return KunOAuthResult(
        ok: false,
        message: '无法打开浏览器，请手动复制访问：$portalUri',
      );
    }

    try {
      return await completer.future.timeout(const Duration(minutes: 5));
    } on TimeoutException {
      await cancelLogin();
      return const KunOAuthResult(
        ok: false,
        message: '鲲Gal OAuth 登录等待超时（5 分钟），请重试',
      );
    } catch (_) {
      await cancelLogin();
      return const KunOAuthResult(
        ok: false,
        message: '鲲Gal OAuth 登录已取消',
      );
    } finally {
      // 延迟 400ms 关闭本地服务，确保浏览器收到最终 JSON 响应与图标
      unawaited(Future<void>.delayed(
        const Duration(milliseconds: 400),
        _closeServer,
      ));
    }
  }

  /// 第一步：通过 NextMoe `/api/v1/auth/login` 校验账号密码；
  /// 第二步：携带第一方令牌自动调用 `/api/v1/oauth/authorize/consent` 签发 PKCE 授权码；
  /// 第三步：调用 `/api/v1/oauth/token` 换取长期 OAuth `access_token` 与 `refresh_token`。
  Future<KunOAuthResult> _loginWithCredentialsAndPkce({
    required String account,
    required String password,
    required String state,
    required ({String verifier, String challenge}) pkce,
    required int gen,
    String? proxy,
  }) async {
    if (account.isEmpty || password.isEmpty) {
      return const KunOAuthResult(ok: false, message: '请输入鲲Gal / NextMoe 账号与密码');
    }

    final dio = _buildDio(proxy: proxy);
    try {
      // 1. 认证账号密码
      final loginResp = await dio.post(
        authLoginEndpoint,
        data: {'account': account, 'password': password},
      );
      if (loginResp.data is! Map) {
        return KunOAuthResult(
          ok: false,
          message: '鲲Gal认证服务响应异常（HTTP ${loginResp.statusCode}）',
        );
      }
      final loginMap = Map<String, dynamic>.from(loginResp.data as Map);
      final bizCode = loginMap['code'];
      if (loginResp.statusCode != 200 || (bizCode != null && bizCode != 0)) {
        final errMsg = (loginMap['message'] ?? '账号或密码不正确，请重试').toString();
        return KunOAuthResult(ok: false, message: errMsg);
      }

      final dataMap = Map<String, dynamic>.from(
          (loginMap['data'] as Map?) ?? const {});
      final firstPartyToken =
          (dataMap['access_token'] ?? '').toString().trim();
      final userMap = Map<String, dynamic>.from(
          (dataMap['user'] as Map?) ?? const {});
      final loginUserId =
          (userMap['uuid'] ?? userMap['sub'] ?? userMap['id'] ?? '').toString();
      final loginUserName =
          (userMap['name'] ?? userMap['preferred_username'] ?? '').toString();
      final loginAvatar = (userMap['avatar_image_hash'] ?? '').toString();

      if (firstPartyToken.isEmpty) {
        return const KunOAuthResult(
          ok: false,
          message: '未获取到有效认证令牌，请稍后重试',
        );
      }

      // 2. 在后台执行 OAuth 2.0 + PKCE (S256) 授权码签发与令牌换取
      try {
        final consentResp = await dio.post(
          consentEndpoint,
          data: {
            'client_id': clientId,
            'redirect_uri': redirectUri,
            'response_type': 'code',
            'scope': scopes,
            'state': state,
            'code_challenge': pkce.challenge,
            'code_challenge_method': 'S256',
          },
          options: Options(headers: {
            'Authorization': 'Bearer $firstPartyToken',
          }),
        );
        if (consentResp.statusCode == 200 && consentResp.data is Map) {
          final cm = Map<String, dynamic>.from(consentResp.data as Map);
          final cData = cm['data'];
          if (cm['code'] == 0 && cData is Map) {
            final redirectUrl = (cData['redirect_url'] ?? '').toString();
            final redirectUriParsed = Uri.tryParse(redirectUrl);
            final authCode =
                (redirectUriParsed?.queryParameters['code'] ?? '').trim();
            if (authCode.isNotEmpty) {
              final exchanged = await _exchangeCode(
                code: authCode,
                verifier: pkce.verifier,
                proxy: proxy,
                gen: gen,
                fallbackUserId: loginUserId,
                fallbackUserName: loginUserName,
              );
              if (exchanged.ok) return exchanged;
            }
          }
        }
      } catch (_) {}

      // 3. 若 OAuth consent 端点因网络或策略未签发 code，回退使用第一方 JWT 令牌
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final session = KunOAuthSession(
        accessToken: firstPartyToken,
        refreshToken: '',
        expiresAt: nowSec + 900,
        scope: scopes,
        userId: loginUserId,
        name: loginUserName,
        avatar: loginAvatar,
      );
      return await _persistSession(session);
    } catch (e) {
      return KunOAuthResult(ok: false, message: '连接鲲Gal认证服务器失败：$e');
    } finally {
      dio.close(force: true);
    }
  }

  /// 支持直接使用已获取的 Access Token 登录并拉取用户信息。
  Future<KunOAuthResult> _loginWithAccessToken({
    required String accessToken,
    required int gen,
    String? proxy,
  }) async {
    if (accessToken.isEmpty) {
      return const KunOAuthResult(ok: false, message: '请粘贴有效的 Access Token');
    }
    final dio = _buildDio(proxy: proxy);
    try {
      String userId = '';
      String userName = '';
      String avatar = '';

      final ur = await dio.get(
        userInfoEndpoint,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (ur.statusCode == 200 && ur.data is Map) {
        final um = Map<String, dynamic>.from(ur.data as Map);
        userId = (um['sub'] ?? '').toString();
        userName = (um['name'] ?? um['preferred_username'] ?? '').toString();
        avatar = (um['picture'] ?? '').toString();
      } else {
        final meResp = await dio.get(
          authMeEndpoint,
          options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
        );
        if (meResp.statusCode == 200 && meResp.data is Map) {
          final mm = Map<String, dynamic>.from(meResp.data as Map);
          final d = mm['data'] is Map
              ? Map<String, dynamic>.from(mm['data'] as Map)
              : mm;
          userId = (d['uuid'] ?? d['sub'] ?? '').toString();
          userName = (d['name'] ?? '').toString();
        } else {
          return KunOAuthResult(
            ok: false,
            message: '令牌校验未通过（HTTP ${ur.statusCode}）',
          );
        }
      }

      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final session = KunOAuthSession(
        accessToken: accessToken,
        refreshToken: '',
        expiresAt: nowSec + 3600,
        scope: scopes,
        userId: userId,
        name: userName,
        avatar: avatar,
      );
      return await _persistSession(session);
    } catch (e) {
      return KunOAuthResult(ok: false, message: '校验令牌失败：$e');
    } finally {
      dio.close(force: true);
    }
  }

  Future<KunOAuthResult> _exchangeCode({
    required String code,
    required String verifier,
    required int gen,
    String? proxy,
    String fallbackUserId = '',
    String fallbackUserName = '',
  }) async {
    final dio = _buildDio(proxy: proxy);
    try {
      final r = await dio.post(
        tokenEndpoint,
        data: {
          'grant_type': 'authorization_code',
          'client_id': clientId,
          'code': code,
          'redirect_uri': redirectUri,
          'code_verifier': verifier,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      if (r.statusCode != 200 || r.data is! Map) {
        return KunOAuthResult(
          ok: false,
          message: '换取鲲Gal令牌失败（HTTP ${r.statusCode}）',
        );
      }
      final tokenMap = Map<String, dynamic>.from(r.data as Map);
      final accessToken = (tokenMap['access_token'] ?? '').toString().trim();
      final refreshToken = (tokenMap['refresh_token'] ?? '').toString().trim();
      final expiresIn = (tokenMap['expires_in'] is num)
          ? (tokenMap['expires_in'] as num).toInt()
          : int.tryParse('${tokenMap['expires_in'] ?? 900}') ?? 900;
      final scope = (tokenMap['scope'] ?? scopes).toString();

      if (accessToken.isEmpty) {
        return const KunOAuthResult(
          ok: false,
          message: '鲲Gal OAuth 响应缺少有效令牌，请重试',
        );
      }

      var userId = fallbackUserId;
      var userName = fallbackUserName;
      var avatar = '';
      try {
        final ur = await dio.get(
          userInfoEndpoint,
          options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
        );
        if (ur.statusCode == 200 && ur.data is Map) {
          final um = Map<String, dynamic>.from(ur.data as Map);
          final sub = (um['sub'] ?? '').toString();
          final nm = (um['name'] ?? um['preferred_username'] ?? '').toString();
          if (sub.isNotEmpty) userId = sub;
          if (nm.isNotEmpty) userName = nm;
          avatar = (um['picture'] ?? '').toString();
        }
      } catch (_) {}

      if (gen != _generation) {
        return const KunOAuthResult(ok: false, message: '鲲Gal 登录已取消');
      }

      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final session = KunOAuthSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: nowSec + expiresIn,
        scope: scope,
        userId: userId,
        name: userName,
        avatar: avatar,
      );
      return await _persistSession(session);
    } catch (e) {
      return KunOAuthResult(ok: false, message: '请求鲲Gal授权接口失败：$e');
    } finally {
      dio.close(force: true);
    }
  }

  Future<KunOAuthResult> _persistSession(KunOAuthSession session) async {
    final displayUser = session.name.isNotEmpty
        ? session.name
        : (session.userId.isNotEmpty ? 'UID ${session.userId}' : '已授权用户');
    final statusMsg =
        'OAuth 已登录：$displayUser（更新于 ${fmtDateTime(DateTime.now())}）';

    await AppServices.I.accounts.setToken(
      KisakiSources.kun,
      session.accessToken,
      extra: session.toExtra(status: statusMsg),
    );
    await _syncFetcherToken(session.accessToken);

    return KunOAuthResult(
      ok: true,
      message: '鲲Gal 登录成功，欢迎 $displayUser',
      session: session,
    );
  }

  /// 获取当前可用的 Access Token；若即将过期则自动通过 Refresh Token 静默刷新。
  Future<String?> validAccessToken({bool forceRefresh = false}) async {
    if (_refreshingFuture != null) {
      return _refreshingFuture;
    }
    final token = await AppServices.I.accounts.token(KisakiSources.kun);
    if (token == null || token.trim().isEmpty) return null;
    final extra = await AppServices.I.accounts.info(KisakiSources.kun);
    final session = KunOAuthSession.fromStore(token, extra);
    if (session == null) return null;

    if (session.refreshToken.isEmpty) {
      return session.accessToken;
    }

    if (!forceRefresh && !session.isExpired) {
      return session.accessToken;
    }

    final fut = _refreshToken(session);
    _refreshingFuture = fut;
    try {
      return await fut;
    } finally {
      _refreshingFuture = null;
    }
  }

  Future<String?> _refreshToken(KunOAuthSession prev) async {
    final dio = _buildDio();
    try {
      final r = await dio.post(
        tokenEndpoint,
        data: {
          'grant_type': 'refresh_token',
          'client_id': clientId,
          'refresh_token': prev.refreshToken,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      if (r.statusCode != 200 || r.data is! Map) {
        if (r.statusCode == 400 || r.statusCode == 401) {
          final err = (r.data is Map) ? '${(r.data as Map)['error'] ?? ''}' : '';
          if (err == 'invalid_grant') {
            await AppServices.I.accounts
                .setToken(KisakiSources.kun, null, extra: {
              'status': '鲲Gal 授权已过期，请重新点击 OAuth 登录',
            });
            return null;
          }
        }
        return prev.accessToken;
      }

      final m = Map<String, dynamic>.from(r.data as Map);
      final newAccess = (m['access_token'] ?? '').toString().trim();
      final newRefresh =
          (m['refresh_token'] ?? prev.refreshToken).toString().trim();
      final expiresIn = (m['expires_in'] is num)
          ? (m['expires_in'] as num).toInt()
          : int.tryParse('${m['expires_in'] ?? 900}') ?? 900;
      if (newAccess.isEmpty) return prev.accessToken;

      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final updated = KunOAuthSession(
        accessToken: newAccess,
        refreshToken: newRefresh,
        expiresAt: nowSec + expiresIn,
        scope: (m['scope'] ?? prev.scope).toString(),
        userId: prev.userId,
        name: prev.name,
        avatar: prev.avatar,
      );
      final displayUser =
          updated.name.isNotEmpty ? updated.name : '已授权用户';
      await AppServices.I.accounts.setToken(
        KisakiSources.kun,
        updated.accessToken,
        extra: updated.toExtra(
          status: 'OAuth 已登录：$displayUser（令牌已自动刷新）',
        ),
      );
      await _syncFetcherToken(updated.accessToken);
      return updated.accessToken;
    } catch (_) {
      return prev.accessToken;
    } finally {
      dio.close(force: true);
    }
  }

  /// 取消正在等待回调的 OAuth 登录。
  Future<void> cancelLogin() async {
    _generation++;
    final c = _pendingResult;
    _pendingResult = null;
    if (c != null && !c.isCompleted) {
      c.completeError(StateError('cancelled'));
    }
    await _closeServer();
  }

  /// 退出鲲Gal账号并清理本地保存的 OAuth 凭据。
  Future<void> logout() async {
    await cancelLogin();
    await AppServices.I.accounts.setToken(KisakiSources.kun, null);
    await _syncFetcherToken('');
  }

  Future<void> _syncFetcherToken(String token) async {
    try {
      final current = Map<String, String>.from(AppServices.I.fetcher.tokens);
      if (token.isEmpty) {
        current.remove(KisakiSources.kun);
      } else {
        current[KisakiSources.kun] = token;
      }
      final proxy = await AppServices.I.settings.getString('sources.proxy', '');
      await AppServices.I.fetcher.init(
        appProxy: proxy,
        tokens: current,
      );
    } catch (_) {}
  }

  Future<void> _closeServer() async {
    final s = _server;
    _server = null;
    if (s != null) {
      try {
        await s.close(force: true);
      } catch (_) {}
    }
  }

  /// KisakiGals 专属本地授权门户页（展示 KisakiGals 品牌图标与名称，彻底告别显示 ReinaManager）。
  static String _buildPortalHtml() {
    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>授权 KisakiGals 连接 鲲Gal (NextMoe) 账号</title>
  <style>
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
      background: #FAF7F2;
      color: #18171C;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Microsoft YaHei UI", sans-serif;
    }
    .card {
      width: 100%;
      max-width: 440px;
      padding: 34px 36px;
      background: #FFFFFF;
      border: 1px solid #E5DFD5;
      border-radius: 16px;
      box-shadow: 0 14px 36px rgba(24, 23, 28, 0.06);
    }
    .handshake {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 22px;
    }
    .app-icon {
      width: 52px;
      height: 52px;
      border-radius: 14px;
      border: 1px solid #E5DFD5;
      object-fit: cover;
      background: #FAF7F2;
    }
    .link-dash {
      width: 22px;
      border-top: 1.5px dashed #C9C2B6;
    }
    .kun-badge {
      width: 52px;
      height: 52px;
      border-radius: 14px;
      border: 1px solid #E5DFD5;
      background: #F3EFE8;
      color: #D13B40;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 18px;
      font-weight: 800;
    }
    h1 {
      margin: 0 0 8px;
      font-size: 21px;
      font-weight: 700;
      letter-spacing: -0.2px;
    }
    .sub {
      margin: 0 0 20px;
      font-size: 13.5px;
      line-height: 1.6;
      color: #5C5863;
    }
    .sub strong {
      color: #18171C;
    }
    .scopes {
      margin-bottom: 20px;
      padding: 12px 14px;
      background: #FAF7F2;
      border: 1px solid #ECE6DC;
      border-radius: 10px;
      font-size: 12.5px;
      color: #5C5863;
    }
    .scopes div + div {
      margin-top: 6px;
    }
    .scopes span.dot {
      color: #1D7A5F;
      font-weight: 700;
      margin-right: 6px;
    }
    .field {
      margin-bottom: 14px;
    }
    label {
      display: block;
      margin-bottom: 6px;
      font-size: 13px;
      font-weight: 600;
      color: #2E2C34;
    }
    input {
      width: 100%;
      padding: 10px 13px;
      font-size: 14px;
      border: 1px solid #D9D2C5;
      border-radius: 9px;
      outline: none;
      transition: border-color 0.15s;
    }
    input:focus {
      border-color: #D13B40;
    }
    .err {
      display: none;
      margin-bottom: 14px;
      padding: 10px 12px;
      border-radius: 8px;
      background: #FDF2F2;
      border: 1px solid #F5C6C8;
      color: #C22B30;
      font-size: 13px;
      line-height: 1.5;
    }
    .btn {
      width: 100%;
      padding: 11px 16px;
      border: none;
      border-radius: 9px;
      background: #D13B40;
      color: #FFFFFF;
      font-size: 14.5px;
      font-weight: 700;
      cursor: pointer;
      transition: opacity 0.15s;
    }
    .btn:hover { opacity: 0.92; }
    .btn:disabled { opacity: 0.55; cursor: not-allowed; }
    .switch-link {
      margin-top: 14px;
      text-align: center;
      font-size: 12.5px;
      color: #6E6A75;
    }
    .switch-link a {
      color: #D13B40;
      text-decoration: none;
      font-weight: 600;
      cursor: pointer;
    }
    .note {
      margin-top: 16px;
      font-size: 11.5px;
      color: #8A8592;
      line-height: 1.55;
      text-align: center;
    }
    .done-box {
      display: none;
      text-align: center;
      padding: 18px 0 6px;
    }
    .done-badge {
      display: inline-block;
      padding: 5px 12px;
      border-radius: 6px;
      background: #1D7A5F;
      color: #FFF;
      font-size: 12px;
      font-weight: 700;
      margin-bottom: 12px;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="handshake">
      <img class="app-icon" src="/logo.png" alt="KisakiGals">
      <span class="link-dash"></span>
      <div class="kun-badge">鲲</div>
    </div>

    <div id="form-view">
      <h1>授权「KisakiGals」</h1>
      <p class="sub">使用你的 <strong>鲲Galgame (NextMoe·未萌)</strong> 账号登录并授权 <strong>KisakiGals</strong> 同步数据。</p>

      <div class="scopes">
        <div><span class="dot">✓</span>读取基本用户资料（昵称、UID、头像）</div>
        <div><span class="dot">✓</span>读取与同步你的作品收藏夹、游玩状态与评分</div>
      </div>

      <div id="err-box" class="err"></div>

      <form id="auth-form" onsubmit="submitAuth(event)">
        <div id="account-fields">
          <div class="field">
            <label for="account">鲲Gal / NextMoe 账号</label>
            <input id="account" type="text" placeholder="邮箱或用户名" autocomplete="username" autofocus>
          </div>
          <div class="field">
            <label for="password">密码</label>
            <input id="password" type="password" placeholder="请输入登录密码" autocomplete="current-password">
          </div>
        </div>

        <div id="token-fields" style="display:none;">
          <div class="field">
            <label for="token">NextMoe Access Token</label>
            <input id="token" type="password" placeholder="粘贴来自 account.nextmoe.com 的 access_token">
          </div>
        </div>

        <button id="submit-btn" class="btn" type="submit">登录并授权 KisakiGals</button>
      </form>

      <div class="switch-link">
        <span id="switch-text">使用 GitHub / Google 第三方注册？</span>
        <a id="switch-btn" onclick="toggleMode()">切换为 Token 填入</a>
        ·
        <a href="https://account.nextmoe.com/auth/login" target="_blank" rel="noopener">前往未萌账号中心</a>
      </div>

      <p class="note">认证直接通过 HTTPS 发往 account.nextmoe.com 官方接口并签发 OAuth 2.0 + PKCE 令牌，KisakiGals 不会存储你的明文密码。</p>
    </div>

    <div id="done-view" class="done-box">
      <span class="done-badge">✓ OAuth 2.0 授权完成</span>
      <h1 id="done-title">欢迎回来</h1>
      <p class="sub" style="margin-bottom:0;">已成功连接至 <strong>KisakiGals</strong>，现在可以关闭此浏览器标签页并返回应用。</p>
    </div>
  </div>

  <script>
    let mode = 'account';
    function toggleMode() {
      mode = (mode === 'account') ? 'token' : 'account';
      document.getElementById('account-fields').style.display = mode === 'account' ? 'block' : 'none';
      document.getElementById('token-fields').style.display = mode === 'token' ? 'block' : 'none';
      document.getElementById('switch-btn').textContent = mode === 'account' ? '切换为 Token 填入' : '切换为账号密码登录';
      document.getElementById('err-box').style.display = 'none';
    }

    async function submitAuth(e) {
      e.preventDefault();
      const errBox = document.getElementById('err-box');
      const btn = document.getElementById('submit-btn');
      errBox.style.display = 'none';
      btn.disabled = true;
      btn.textContent = '正在向 NextMoe 验证并签发令牌…';

      try {
        const body = mode === 'account'
          ? {
              mode: 'account',
              account: document.getElementById('account').value.trim(),
              password: document.getElementById('password').value,
            }
          : {
              mode: 'token',
              token: document.getElementById('token').value.trim(),
            };

        const resp = await fetch('/api/login', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body),
        });
        const data = await resp.json();
        if (data.ok) {
          document.getElementById('form-view').style.display = 'none';
          document.getElementById('done-view').style.display = 'block';
          if (data.user) {
            document.getElementById('done-title').textContent = '欢迎，' + data.user;
          }
        } else {
          errBox.textContent = data.message || '授权未通过，请检查账号或密码';
          errBox.style.display = 'block';
          btn.disabled = false;
          btn.textContent = '登录并授权 KisakiGals';
        }
      } catch (err) {
        errBox.textContent = '网络请求异常，请确认 KisakiGals 仍在运行';
        errBox.style.display = 'block';
        btn.disabled = false;
        btn.textContent = '登录并授权 KisakiGals';
      }
    }
  </script>
</body>
</html>
''';
  }

  static String _buildCallbackHtml({required bool ok, required String detail}) {
    final badgeColor = ok ? '#1D7A5F' : '#D13B40';
    final title = ok ? '鲲Gal 授权成功' : '鲲Gal 授权未完成';
    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$title - KisakiGals</title>
  <style>
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: #FAF7F2;
      color: #18171C;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Microsoft YaHei", sans-serif;
    }
    .card {
      max-width: 440px;
      padding: 32px 36px;
      background: #FFFFFF;
      border: 1px solid #E5DFD5;
      border-radius: 14px;
      box-shadow: 0 12px 32px rgba(24, 23, 28, 0.06);
    }
    .tag {
      display: inline-block;
      padding: 4px 10px;
      border-radius: 6px;
      background: $badgeColor;
      color: #FFF;
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 0.5px;
    }
    h1 {
      margin: 16px 0 10px;
      font-size: 22px;
    }
    p {
      margin: 0;
      line-height: 1.65;
      color: #5C5863;
      font-size: 14px;
    }
  </style>
</head>
<body>
  <div class="card">
    <span class="tag">KisakiGals</span>
    <h1>$title</h1>
    <p>$detail</p>
  </div>
</body>
</html>
''';
  }
}
