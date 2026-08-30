import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_navigator.dart';
import '../models/saved_account.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/dio_client.dart';
import '../services/exam_service.dart';
import '../services/logger.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final ExamService _examService = ExamService();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  static const String _savedAccountsKey = 'saved_accounts_v1';
  List<SavedAccount> _savedAccounts = [];
  bool _handlingAuthExpired = false;
  bool _switching = false;
  int _generation = 0; // 会话代际: 切换/登出时+1, 用于丢弃迟到的旧账号刷新结果
  DateTime? _lastSwitchAt; // 切换冷却: 服务端对登录频率有限制, 频繁切换可能被临时限流
  static const Duration _switchCooldown = Duration(seconds: 30);
  UserModel? _user;
  bool _isLoading = false;
  bool _isInitialized = false;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user?.isLoggedIn ?? false;
  bool get isInitialized => _isInitialized;
  List<SavedAccount> get savedAccounts => _savedAccounts;
  bool get switching => _switching;

  /// 从 SharedPreferences 恢复业务上下文
  Future<void> _restoreContext() async {
    final prefs = await SharedPreferences.getInstance();
    final schoolGuid = prefs.getString('schoolGuid');
    final grade = prefs.getString('grade');
    final ruCode = prefs.getString('ruCode');
    if (schoolGuid != null && schoolGuid.isNotEmpty && grade != null && grade.isNotEmpty) {
      _examService.setContext(schoolGuid: schoolGuid, grade: grade, ruCode: ruCode);
    }
  }

  /// 应用启动恢复会话：
  /// 只要有 token 就立即标记为已登录（登录状态不丢失），随后后台拉取完整信息增强。
  Future<void> init() async {
    await _loadSavedAccounts();
    DioClient.onUnauthorized = _onUnauthorized;
    DioClient.reloginProvider = _silentRelogin;
    final token = await DioClient().getToken();
    if (token != null && token.isNotEmpty) {
      // 先用 token 构造最小用户，保证 isLoggedIn=true，避免重启后掉登录
      _user = UserModel(userId: '', token: token);
      notifyListeners();
      // 恢复业务上下文
      await _restoreContext();
      // 协商会话密钥并拉取完整信息（失败不影响已登录状态）
      unawaited(_refreshUserInfo());
    }
    _isInitialized = true;
    notifyListeners();
  }

  // ─── 多账号管理 ───────────────────────────────────────────

  /// 从加密安全存储读取已保存账号
  Future<void> _loadSavedAccounts() async {
    try {
      final s = await _secureStorage.read(key: _savedAccountsKey);
      if (s != null && s.isNotEmpty) {
        final arr = jsonDecode(s) as List<dynamic>;
        _savedAccounts = arr
            .map((e) => SavedAccount.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
  }

  Future<void> _persistSavedAccounts() async {
    try {
      await _secureStorage.write(
        key: _savedAccountsKey,
        value: jsonEncode(_savedAccounts.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
    notifyListeners();
  }

  /// 登录成功/信息刷新后记住账号(含密码, 用于切换时静默重登)
  Future<void> _upsertSavedAccount(UserModel user, {String? password}) async {
    if (user.userId.isEmpty) return;
    await _loadSavedAccounts();
    var pwd = password ?? '';
    final existing =
        _savedAccounts.where((a) => a.userCode == user.userId).toList();
    if (existing.isNotEmpty && password == null) {
      pwd = existing.first.password;
    }
    _savedAccounts.removeWhere((a) => a.userCode == user.userId);
    _savedAccounts.insert(
        0,
        SavedAccount(
          userCode: user.userId,
          password: pwd,
          nickname: user.nickname ?? '',
          schoolName: user.schoolName ?? '',
          userJson: jsonEncode(user.toJson()),
          savedAt: DateTime.now().toIso8601String(),
        ));
    await _persistSavedAccounts();
  }

  /// 删除某个已保存账号(不影响当前登录)
  Future<void> removeAccount(String userCode) async {
    await _loadSavedAccounts();
    _savedAccounts.removeWhere((a) => a.userCode == userCode);
    await _persistSavedAccounts();
  }

  /// 切换账号: 优先用保存的密码静默重登(拿到新token), 否则用缓存的token
  /// 返回 null 表示成功, 否则为错误提示
  Future<String?> switchAccount(SavedAccount account) async {
    if (_switching) return '正在切换中，请稍候';
    if (_lastSwitchAt != null) {
      final elapsed = DateTime.now().difference(_lastSwitchAt!);
      if (elapsed < _switchCooldown) {
        final remain = (_switchCooldown - elapsed).inSeconds + 1;
        return '切换过于频繁，请 $remain 秒后再试（频繁登录可能触发服务端限制）';
      }
    }
    _switching = true;
    try {
      // 先把当前账号存档(更新token/资料)
      if (_user != null && _user!.isLoggedIn && _user!.userId.isNotEmpty) {
        await _upsertSavedAccount(_user!);
      }
      UserModel? target;
      if (account.password.isNotEmpty) {
        try {
          target =
              await _authService.loginByPassword(account.userCode, account.password);
        } catch (_) {}
      }
      target ??= _userFromSaved(account);
      if (target == null) {
        return '切换失败：该账号的登录凭据可能已失效，请删除后重新登录该账号';
      }
      await _applyAccount(target,
          password: account.password.isNotEmpty ? account.password : null);
      _lastSwitchAt = DateTime.now();
      return null;
    } finally {
      _switching = false;
    }
  }

  UserModel? _userFromSaved(SavedAccount a) {
    if (a.userJson.isEmpty) return null;
    try {
      return UserModel.fromJson(jsonDecode(a.userJson) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 应用某个账号: 重绑token/恢复资料/上下文并记住
  Future<void> _applyAccount(UserModel user, {String? password}) async {
    _generation++; // 作废在途的旧账号刷新
    _user = user;
    // 关键: 将目标账号token重绑进DioClient。此前token回退路径漏掉此步,
    // 导致切换后请求仍携带旧账号token, 永远显示旧账号数据
    if (user.token != null && user.token!.isNotEmpty) {
      await DioClient().saveToken(user.token!);
    }
    if (password == null) {
      // 非重登路径(直接用缓存token): 强制重新协商会话密钥,
      // 避免会话AES密钥仍绑定上一个账号导致加密接口异常
      try {
        await DioClient().negotiateKey();
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    if (user.schoolGuid?.isNotEmpty == true) {
      await prefs.setString('schoolGuid', user.schoolGuid!);
    }
    if (user.grade?.isNotEmpty == true) {
      await prefs.setString('grade', user.grade!);
    }
    if (user.ruCode?.isNotEmpty == true) {
      await prefs.setString('ruCode', user.ruCode!);
    }
    _examService.setContext(
        schoolGuid: user.schoolGuid, grade: user.grade, ruCode: user.ruCode);
    await _upsertSavedAccount(user, password: password);
    notifyListeners();
  }

  // ─── 登录态失效检测 ────────────────────────────────────────

  Future<String?>? _reloginFuture;

  /// 401 静默重登: 用当前账号保存的密码重登, 返回新 token (失败返回 null)。
  /// 并发 401 共享同一次重登, 避免连环触发登录接口引发风控。
  Future<String?> _silentRelogin() async {
    if (_reloginFuture != null) return _reloginFuture;
    final completer = Completer<String?>();
    _reloginFuture = completer.future;
    try {
      final code = _user?.userId ?? '';
      await _loadSavedAccounts();
      SavedAccount? acc;
      for (final a in _savedAccounts) {
        if (a.userCode == code && a.password.isNotEmpty) {
          acc = a;
          break;
        }
      }
      if (acc == null) {
        completer.complete(null);
        return null;
      }
      logger.info('Auth', '静默重登: $code');
      final user = await _authService.loginByPassword(acc.userCode, acc.password);
      if (user == null) {
        completer.complete(null);
        return null;
      }
      await _applyAccount(user, password: acc.password);
      completer.complete(user.token);
      return user.token;
    } catch (_) {
      completer.complete(null);
      return null;
    } finally {
      Future.delayed(const Duration(milliseconds: 100), () => _reloginFuture = null);
    }
  }

  /// DioClient 检测到 401(HTTP或业务status): 清会话并弹窗引导重登
  void _onUnauthorized(String message) {
    if (_handlingAuthExpired) return;
    _handlingAuthExpired = true;
    _generation++;
    _user = null;
    notifyListeners();
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) {
      _handlingAuthExpired = false;
      return;
    }
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        title: const Text('登录已失效'),
        content: Text(message.isEmpty
            ? '账号可能在其他设备登录，请重新登录。已保存的其他账号不受影响，可随时切换。'
            : message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dCtx);
              _handlingAuthExpired = false;
              appNavigatorKey.currentState
                  ?.pushNamedAndRemoveUntil('/login', (route) => false);
            },
            child: const Text('重新登录'),
          ),
        ],
      ),
    );
  }

  /// 供下拉刷新等主动触发：重新拉取完整用户信息
  Future<void> refreshUserInfo() => _refreshUserInfo();

  Future<void> _refreshUserInfo() async {
    final gen = _generation;
    try {
      final user = await _authService.getUserInfo();
      // 会话已在请求期间切换/登出, 丢弃迟到的结果, 防止覆盖新账号
      if (gen != _generation) return;
      if (user != null) {
        _user = user;
        await _upsertSavedAccount(user);
        // 保存业务上下文到 SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        if (user.schoolGuid != null && user.schoolGuid!.isNotEmpty) {
          await prefs.setString('schoolGuid', user.schoolGuid!);
        }
        if (user.grade != null && user.grade!.isNotEmpty) {
          await prefs.setString('grade', user.grade!);
        }
        if (user.ruCode != null && user.ruCode!.isNotEmpty) {
          await prefs.setString('ruCode', user.ruCode!);
        }
        // 更新 ExamService 上下文
        _examService.setContext(schoolGuid: user.schoolGuid, grade: user.grade, ruCode: user.ruCode);
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 密码登录：phone=手机号, password=明文密码（底层会加密）
  Future<bool> login(String phone, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      final user = await _authService.loginByPassword(phone, password);
      _isLoading = false;
      notifyListeners();
      if (user != null) {
        _user = user;
        await _upsertSavedAccount(user, password: password);
        // 保存业务上下文到 SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        if (user.schoolGuid != null && user.schoolGuid!.isNotEmpty) {
          await prefs.setString('schoolGuid', user.schoolGuid!);
        }
        if (user.grade != null && user.grade!.isNotEmpty) {
          await prefs.setString('grade', user.grade!);
        }
        if (user.ruCode != null && user.ruCode!.isNotEmpty) {
          await prefs.setString('ruCode', user.ruCode!);
        }
        // 更新 ExamService 上下文
        _examService.setContext(schoolGuid: user.schoolGuid, grade: user.grade, ruCode: user.ruCode);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _generation++; // 作废在途刷新, 防止登出后又被旧结果写回登录态
    await _authService.logout();
    _user = null;
    // 清除保存的上下文
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('schoolGuid');
    await prefs.remove('grade');
    await prefs.remove('ruCode');
    notifyListeners();
  }

  /// 编辑昵称：调用服务端并本地更新
  Future<bool> updateNickname(String nickName) async {
    try {
      final d = await DioClient().updateNickname(nickName);
      if (d != null) {
        // 服务端返回 auditNickName/nickName，优先取 nickName
        final newName = d['nickName']?.toString() ?? nickName;
        if (_user != null) {
          _user = UserModel(
            userId: _user!.userId,
            phone: _user!.phone,
            nickname: newName,
            avatar: _user!.avatar,
            token: _user!.token,
            refreshToken: _user!.refreshToken,
            gradeId: _user!.gradeId,
            gradeName: _user!.gradeName,
            schoolName: _user!.schoolName,
            cityName: _user!.cityName,
            schoolGuid: _user!.schoolGuid,
            grade: _user!.grade,
            ruCode: _user!.ruCode,
            cityCode: _user!.cityCode,
            studentName: _user!.studentName,
          );
          notifyListeners();
        }
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}