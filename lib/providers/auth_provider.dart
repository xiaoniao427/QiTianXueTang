import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/dio_client.dart';
import '../services/exam_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final ExamService _examService = ExamService();
  UserModel? _user;
  bool _isLoading = false;
  bool _isInitialized = false;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user?.isLoggedIn ?? false;
  bool get isInitialized => _isInitialized;

  /// 从 SharedPreferences 恢复业务上下文
  Future<void> _restoreContext() async {
    final prefs = await SharedPreferences.getInstance();
    final schoolGuid = prefs.getString('schoolGuid');
    final grade = prefs.getString('grade');
    if (schoolGuid != null && schoolGuid.isNotEmpty && grade != null && grade.isNotEmpty) {
      _examService.setContext(schoolGuid: schoolGuid, grade: grade);
    }
  }

  /// 应用启动恢复会话：
  /// 只要有 token 就立即标记为已登录（登录状态不丢失），随后后台拉取完整信息增强。
  Future<void> init() async {
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

  /// 供下拉刷新等主动触发：重新拉取完整用户信息
  Future<void> refreshUserInfo() => _refreshUserInfo();

  Future<void> _refreshUserInfo() async {
    try {
      final user = await _authService.getUserInfo();
      if (user != null) {
        _user = user;
        // 保存 schoolGuid 和 grade 到 SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        if (user.schoolGuid != null && user.schoolGuid!.isNotEmpty) {
          await prefs.setString('schoolGuid', user.schoolGuid!);
        }
        if (user.grade != null && user.grade!.isNotEmpty) {
          await prefs.setString('grade', user.grade!);
        }
        // 更新 ExamService 上下文
        _examService.setContext(schoolGuid: user.schoolGuid, grade: user.grade);
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
        // 保存 schoolGuid 和 grade 到 SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        if (user.schoolGuid != null && user.schoolGuid!.isNotEmpty) {
          await prefs.setString('schoolGuid', user.schoolGuid!);
        }
        if (user.grade != null && user.grade!.isNotEmpty) {
          await prefs.setString('grade', user.grade!);
        }
        // 更新 ExamService 上下文
        _examService.setContext(schoolGuid: user.schoolGuid, grade: user.grade);
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
    await _authService.logout();
    _user = null;
    // 清除保存的上下文
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('schoolGuid');
    await prefs.remove('grade');
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