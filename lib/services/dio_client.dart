import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api.dart';
import 'logger.dart';
import 'qitian_crypto.dart';
import 'secure_crypto.dart';

/// 封装 Dio HTTP 客户端
/// 说明：认证使用 Token + Version 头，响应若 isEncrypt 则需要 AES 解密。
/// token 使用内存缓存 + secure storage 双写，secure storage 失败不阻断登录。
class DioClient {
  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _tokenKey = 'auth_token';
  String? _memToken; // 内存 token 缓存
  DateTime? _lastUnauthorizedAt;

  /// 登录态失效回调（HTTP 401 或业务 status 401），由 AuthProvider 注册：
  /// 清理会话并提示“账号可能在其他设备登录”。
  static void Function(String message)? onUnauthorized;

  /// 401 静默重登：AuthProvider 注册，用保存的密码重登并返回新 token；
  /// 返回 null 则走 onUnauthorized 弹窗
  static Future<String?> Function()? reloginProvider;

  DioClient._internal();
  static final DioClient _instance = DioClient._internal();
  factory DioClient() => _instance;

  Dio get dio => _dio;

  void init() {
    _dio = Dio(BaseOptions(
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      headers: {
        'Accept-Charset': 'UTF-8',
        'Version': ApiConfig.version,
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome Mobile Safari/537.36',
        'Accept-Encoding': 'gzip',
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // 打印请求信息
        logger.debug('HTTP', '╔═══════════════════════════════════════════════');
        logger.debug('HTTP', '║ [REQUEST] ${options.method} ${options.baseUrl}${options.path}');
        logger.debug('HTTP', '║ Headers:');
        options.headers.forEach((key, value) {
          logger.debug('HTTP', '║   $key: $value');
        });
        if (options.data != null) {
          logger.debug('HTTP', '║ Body: ${options.data}');
        }

        // 认证 token 优先内存，其次 secure storage
        var token = _memToken;
        if (token == null) {
          try {
            token = await _storage.read(key: _tokenKey);
            _memToken = token;
          } catch (_) {}
        }
        if (token != null && token.isNotEmpty) {
          options.headers['Token'] = token;
        }

        // 若已协商会话 AES key，附带 bk 头（供带 bn 的 isEncrypt 接口使用）
        if (SecureCrypto.hasKey) {
          final bk = SecureCrypto.buildBk();
          options.headers['bk'] = bk;
          logger.debug('HTTP', '║ [CRYPTO] bk: $bk');
        }

        // 打印可能的加密头
        if (options.headers.containsKey('bn')) {
          logger.debug('HTTP', '║ [CRYPTO] bn: ${options.headers['bn']}');
        }
        if (options.headers.containsKey('bp')) {
          logger.debug('HTTP', '║ [CRYPTO] bp: ${options.headers['bp']}');
        }
        logger.debug('HTTP', '╚═══════════════════════════════════════════════');

        handler.next(options);
      },

      onResponse: (response, handler) async {
        logger.debug('HTTP', '╔═════���═════════════════════════════════════════');
        logger.debug('HTTP', '║ [RESPONSE] ${response.requestOptions.method} ${response.requestOptions.uri}');
        logger.debug('HTTP', '║ Status Code: ${response.statusCode}');
        logger.debug('HTTP', '║ Headers:');
        response.headers.forEach((key, values) {
          logger.debug('HTTP', '║   $key: $values');
        });

        // 保存原始响应体
        var rawData = response.data;
        logger.debug('HTTP', '║ Raw Response Body: $rawData');

        // 兼容响应为 String 的情况（Dio 未解析为 JSON）
        if (response.data is String) {
          final s = response.data as String;
          try {
            final decoded = jsonDecode(s);
            if (decoded is Map || decoded is List) response.data = decoded;
          } catch (_) {}
        }

        // 解密响应体：data.isEncrypt == true -> AES 解密 content
        try {
          final data = response.data;
          if (data is Map && data['status'] == 401) {
            _fireUnauthorized(data['message']?.toString() ?? '');
          }
          if (data is Map && data['data'] is Map) {
            final inner = data['data'] as Map;
            if (inner['isEncrypt'] == true && inner['content'] != null) {
              final content = inner['content'].toString();
              String decrypted;
              if (inner['bn'] != null) {
                // 带 bn(iv) -> 会话 AES key + GCM
                decrypted = SecureCrypto.aesGcmDecrypt(content, inner['bn'].toString());
                logger.debug('HTTP', '║ [CRYPTO] GCM Decrypted content: $decrypted');
              } else {
                // 无 bn -> 固定 AES key + ECB
                decrypted = QitianCrypto.aesEcbDecryptBase64(content);
                logger.debug('HTTP', '║ [CRYPTO] ECB Decrypted content: $decrypted');
              }
              inner['content'] = decrypted;
              try {
                inner['decryptedData'] = (jsonDecode(decrypted) as Map).cast<String, dynamic>();
                logger.debug('HTTP', '║ [CRYPTO] Decrypted Data: ${inner['decryptedData']}');
              } catch (_) {}
            }
          }
        } catch (e) {
          logger.warn('HTTP', '║ 响应解密失败: $e');
        }
        logger.debug('HTTP', '╚═══════════════════════════════════════════════');
        handler.next(response);
      },

      onError: (error, handler) async {
        final code = error.response?.statusCode;
        final path = error.requestOptions.path;
        // 401 静默重登：用保存的密码重登拿新 token 后重放请求
        if (code == 401 &&
            error.requestOptions.extra['__retried'] != true &&
            reloginProvider != null) {
          logger.warn('HTTP', '401, 尝试静默重登后重放: $path');
          String? newToken;
          try {
            newToken = await reloginProvider!();
          } catch (e) {
            logger.warn('HTTP', '静默重登异常: $e');
          }
          if (newToken != null && newToken.isNotEmpty) {
            final opts = error.requestOptions;
            opts.extra['__retried'] = true;
            opts.headers['Token'] = newToken;
            try {
              final resp = await _dio.fetch(opts);
              logger.debug('HTTP', '静默重登后重试成功: $path');
              return handler.resolve(resp);
            } catch (e) {
              logger.warn('HTTP', '重放仍失败: $e');
            }
          }
        }
        if (code == 401) {
          _fireUnauthorized(error.response?.data is Map
              ? (error.response!.data['message']?.toString() ?? '')
              : '');
        }
        logger.warn('HTTP', '✗ ${error.response?.statusCode} ${error.requestOptions.path}: ${error.message}');
        handler.next(error);
      },
    ));
  }

  /// 登录态失效（5秒去重）：清除 token 并通知 UI 层提示
  void _fireUnauthorized(String message) {
    final now = DateTime.now();
    if (_lastUnauthorizedAt != null && now.difference(_lastUnauthorizedAt!) < const Duration(seconds: 5)) {
      return;
    }
    _lastUnauthorizedAt = now;
    logger.warn('HTTP', '登录态失效: $message');
    clearToken();
    onUnauthorized?.call(message);
  }

  /// 登录（表单）并保存 token
  Future<String?> login(String userCode, String password) async {
    final resp = await _dio.post(
      '${ApiConfig.baseUser}${ApiConfig.login}',
      data: {'userCode': userCode, 'password': QitianCrypto.encryptPassword(password)},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final body = resp.data;
    logger.debug('HTTP', '← login body: ${body.toString()}  type=${body.runtimeType}');
    Map<String, dynamic>? parsed;
    if (body is Map) {
      parsed = Map<String, dynamic>.from(body);
    } else if (body is String) {
      try {
        parsed = (jsonDecode(body) as Map).cast<String, dynamic>();
      } catch (_) {}
    }
    if (parsed != null && parsed['status'] == 200 && parsed['data'] != null) {
      final d = parsed['data'] as Map;
      final token = d['token']?.toString();
      if (token != null && token.isNotEmpty) {
        try {
          await saveToken(token);
        } catch (e) {
          logger.warn('HTTP', '登录 token 持久化失败(忽略): $e');
        }
        logger.debug('HTTP', '← login token 提取成功: ${token.substring(0, 10)}...');
        try {
          await negotiateKey();
        } catch (e) {
          logger.warn('HTTP', '会话密钥协商失败(忽略): $e');
        }
        return token;
      }
      logger.warn('HTTP', '← login data.token 为空: data=$d');
    } else {
      logger.warn('HTTP', '← login 响应结构异常: body=$body type=${body.runtimeType}');
    }
    return null;
  }

  bool _isNegotiating = false;
  Completer<void>? _negotiationCompleter;

  /// 确保会话级 AES key 有效（冷启动后重新协商）
  Future<void> _ensureSessionKey() async {
    if (SecureCrypto.hasKey) return;
    if (_isNegotiating) {
      await _negotiationCompleter?.future;
      return;
    }
    _isNegotiating = true;
    _negotiationCompleter = Completer<void>();
    try {
      await negotiateKey();
      _negotiationCompleter?.complete();
    } catch (e) {
      _negotiationCompleter?.completeError(e);
      rethrow;
    } finally {
      _isNegotiating = false;
    }
  }

  /// 协商会话级 AES key（原 App: POST szone-my/user，空 body，头 bk）
  Future<void> negotiateKey() async {
    SecureCrypto.generateSessionKey();
    final bk = SecureCrypto.buildBk();
    logger.debug('HTTP', '→ 协商会话密钥 bk=${bk.substring(0, 12)}...');
    final resp = await _dio.post(
      '${ApiConfig.baseUser}/user',
      data: <String, dynamic>{},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'bk': bk},
      ),
    );
    final body = resp.data;
    logger.debug('HTTP', '← 会话密钥协商响应: ${body?.toString()} type=${body.runtimeType}');
  }

  /// 获取用户信息（响应 AES 加密，解密后返回 Map）
  Future<Map<String, dynamic>?> getUserInfoRaw() async {
    try {
      final resp = await _dio.get('${ApiConfig.baseUser}${ApiConfig.userInfo}');
      final body = resp.data;
      if (body is Map && body['status'] == 200 && body['data'] is Map) {
        final data = body['data'] as Map;
        Map<String, dynamic>? result;
        if (data['decryptedData'] is Map) {
          result = (data['decryptedData'] as Map).cast<String, dynamic>();
        } else {
          final content = data['content']?.toString();
          if (content != null && content.isNotEmpty) {
            final decoded = jsonDecode(content);
            result = (decoded as Map).cast<String, dynamic>();
          }
        }
        if (result != null) {
          logger.debug('HTTP', '← GetUserInfo 字段: ${result.keys.toList()}');
        }
        return result;
      }
      return null;
    } catch (e) {
      logger.error('HTTP', '获取用户信息失败', e);
      return null;
    }
  }

  Future<void> saveToken(String token) async {
    _memToken = token;
    try {
      await _storage.write(key: _tokenKey, value: token);
    } catch (_) {}
  }

  Future<String?> getToken() async {
    if (_memToken != null) return _memToken;
    String? token;
    try {
      token = await _storage.read(key: _tokenKey);
      _memToken = token;
    } catch (_) {}
    return token;
  }

  Future<void> clearToken() async {
    _memToken = null;
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {}
  }

  // ===== 业务接口 =====
  // 统一取响应 data 对象：解密后返回 data 主体（Map/List）
  dynamic _dataOf(dynamic body) {
    if (body is Map && body['data'] != null) {
      final data = body['data'];
      if (data is Map) {
        if (data['decryptedData'] != null) return data['decryptedData'];
        if (data['content'] != null && data['isEncrypt'] == true) {
          final decrypted = QitianCrypto.aesEcbDecryptBase64(data['content'].toString());
          try {
            return (jsonDecode(decrypted) as Map).cast<String, dynamic>();
          } catch (_) {
            return decrypted;
          }
        }
        return data;
      }
      return data;
    }
    if (body is Map && body['isEncrypt'] != null) {
      if (body['decryptedData'] != null) return body['decryptedData'];
      if (body['content'] != null && body['isEncrypt'] == true) {
        final decrypted = QitianCrypto.aesEcbDecryptBase64(body['content'].toString());
        try {
          return (jsonDecode(decrypted) as Map).cast<String, dynamic>();
        } catch (_) {
          return decrypted;
        }
      }
      return body;
    }
    return body;
  }

  /// 考试列表 (AES-ECB): GET getClaimExams
  Future<Map<String, dynamic>?> getClaimExams({
    int startIndex = 0, int rows = 20,
    required String schoolGuid, required String grade,
  }) async {
    try {
      final resp = await _dio.get('${ApiConfig.baseScore}${ApiConfig.examGetClaimExams}', queryParameters: {
        'startIndex': startIndex, 'rows': rows, 'schoolGuid': schoolGuid, 'grade': grade,
      });
      final d = _dataOf(resp.data);
      return d is Map ? d.cast<String, dynamic>() : null;
    } catch (e) {
      logger.error('HTTP', 'getClaimExams 失败', e);
      return null;
    }
  }

  /// 未认领考试数 (AES-ECB): GET getExamCount
  Future<Map<String, dynamic>?> getExamCount({
    required String studentName, required String schoolGuid, required String grade,
  }) async {
    try {
      final resp = await _dio.get('${ApiConfig.baseScore}${ApiConfig.examGetExamCount}', queryParameters: {
        'studentName': studentName, 'schoolGuid': schoolGuid, 'grade': grade,
      });
      final d = _dataOf(resp.data);
      return d is Map ? d.cast<String, dynamic>() : null;
    } catch (e) {
      logger.error('HTTP', 'getExamCount 失败', e);
      return null;
    }
  }

  /// 首页宫格导航: GET UNavigation/list (明文)
  Future<List<String>?> getNavigation({
    required String grade, required String schoolGuid,
    required String ruCode, required String cityCode, required String currentGrade,
  }) async {
    try {
      final resp = await _dio.get('${ApiConfig.baseIndex}${ApiConfig.navigationList}', queryParameters: {
        'grade': grade, 'schoolGuid': schoolGuid, 'ruCode': ruCode,
        'cityCode': cityCode, 'currentGrade': currentGrade,
      });
      final d = _dataOf(resp.data);
      if (d is Map) {
        final navs = d['navigations'];
        if (navs is List) return navs.map((e) => e.toString()).toList();
      }
      return null;
    } catch (e) {
      logger.error('HTTP', 'getNavigation 失败', e);
      return null;
    }
  }

  /// 首页板块: GET UPlate/plates (明文)
  Future<List<dynamic>?> getPlates({required String grade, required String currentGrade}) async {
    try {
      final resp = await _dio.get('${ApiConfig.baseIndex}${ApiConfig.plateList}', queryParameters: {
        'grade': grade, 'currentGrade': currentGrade,
      });
      final d = _dataOf(resp.data);
      return d is Map ? (d['list'] as List?)?.toList() : null;
    } catch (e) {
      logger.error('HTTP', 'getPlates 失败', e);
      return null;
    }
  }

  /// 首页广告: GET uad/getAdInfo (明文)
  Future<List<dynamic>?> getAdInfo({
    required String positionCode, required String cityCode, required String ruCode,
    required String grade, required String schoolGuid, required String currentGrade,
  }) async {
    try {
      final resp = await _dio.get('${ApiConfig.baseIndex}${ApiConfig.getAdInfo}', queryParameters: {
        'positionCode': positionCode, 'cityCode': cityCode, 'ruCode': ruCode,
        'grade': grade, 'schoolGuid': schoolGuid, 'currentGrade': currentGrade,
      });
      final d = _dataOf(resp.data);
      return d is Map ? (d['list'] as List?)?.toList() : null;
    } catch (e) {
      logger.error('HTTP', 'getAdInfo 失败', e);
      return null;
    }
  }

  /// 学情数据: GET userInfo/statisticalRefresh (明文)
  Future<Map<String, dynamic>?> getStatistical() async {
    try {
      final resp = await _dio.get('${ApiConfig.baseUser}${ApiConfig.userInfoStatistical}');
      final d = _dataOf(resp.data);
      return d is Map ? d.cast<String, dynamic>() : null;
    } catch (e) {
      logger.error('HTTP', 'getStatistical 失败', e);
      return null;
    }
  }

  /// 消息Top: POST Message/Top (明文)
  Future<Map<String, dynamic>?> getMessageTop() async {
    try {
      final resp = await _dio.post('${ApiConfig.baseUser}${ApiConfig.messageTop}',
          options: Options(contentType: Headers.formUrlEncodedContentType));
      final d = _dataOf(resp.data);
      return d is Map ? d.cast<String, dynamic>() : null;
    } catch (e) {
      logger.error('HTTP', 'getMessageTop 失败', e);
      return null;
    }
  }

  /// 编辑昵称: POST UserInfo/UpdateUserInfo (form nickName)
  Future<Map<String, dynamic>?> updateNickname(String nickName) async {
    try {
      final resp = await _dio.post('${ApiConfig.baseUser}${ApiConfig.userInfoUpdate}',
          data: {'nickName': nickName},
          options: Options(contentType: Headers.formUrlEncodedContentType));
      final d = _dataOf(resp.data);
      return d is Map ? d.cast<String, dynamic>() : null;
    } catch (e) {
      logger.error('HTTP', 'updateNickname 失败', e);
      return null;
    }
  }

  /// 成绩详情 (请求侧 GCM 加密): POST Question/ScoreReport
  Future<Map<String, dynamic>?> getScoreReport({
    required String examGuid,
    required String schoolGuid,
    required String grade,
    required String ruCode,
    String km = '总分',
  }) async {
    try {
      await _ensureSessionKey();

      final iv = SecureCrypto.generateIv();
      final ivBytes = base64.decode(iv);

      final pairs = [
        'examGuid=$examGuid',
        'schoolGuid=$schoolGuid',
        'grade=$grade',
        'schoolRuCode=$ruCode',
        'km=$km',
      ];
      logger.debug('HTTP', 'ScoreReport bp 明文: ${pairs.join(';')}');
      final bp = SecureCrypto.aesGcmEncrypt(pairs.join(';'), ivBytes);

      final resp = await _dio.post(
        '${ApiConfig.baseScore}${ApiConfig.questionScoreReport}',
        options: Options(headers: {
          'bn': iv,
          'bp': bp,
        }),
      );
      final d = _dataOf(resp.data);
      logger.debug('HTTP', 'ScoreReport 解析后: $d');
      if (d is Map) {
        logger.debug('HTTP', 'ScoreReport 解密字段: ${d.keys.toList()}');
      }
      return d is Map ? d.cast<String, dynamic>() : null;
    } catch (e) {
      logger.error('HTTP', 'getScoreReport 失败', e);
      return null;
    }
  }

  /// 获取单科列表 (请求侧 GCM 加密): POST Question/Subjects
  /// 官方 JS 实参: {examGuid, schoolGuid, grade:currentGrade, schoolRuCode:ruCode}
  /// 返回完整结构 {list:[...], exam_info:{...}}
  Future<Map<String, dynamic>?> getSubjects({
    required String examGuid,
    required String schoolGuid,
    required String grade,
    required String ruCode,
  }) async {
    try {
      await _ensureSessionKey();

      final iv = SecureCrypto.generateIv();
      final ivBytes = base64.decode(iv);

      final pairs = [
        'examGuid=$examGuid',
        'schoolGuid=$schoolGuid',
        'grade=$grade',
        'schoolRuCode=$ruCode',
      ];
      logger.debug('HTTP', 'Subjects bp 明文: ${pairs.join(';')}');
      final bp = SecureCrypto.aesGcmEncrypt(pairs.join(';'), ivBytes);

      final resp = await _dio.post(
        '${ApiConfig.baseScore}${ApiConfig.questionSubjects}',
        options: Options(headers: {
          'bn': iv,
          'bp': bp,
        }),
      );
      final d = _dataOf(resp.data);
      logger.debug('HTTP', 'Subjects 解析后: $d');
      return d is Map ? d.cast<String, dynamic>() : null;
    } catch (e) {
      logger.error('HTTP', 'getSubjects 失败', e);
      return null;
    }
  }
}
