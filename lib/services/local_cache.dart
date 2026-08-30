import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本地缓存: 考试列表/成绩详情 JSON。
/// 用途: 冷启动秒开(先缓存后刷新)、成绩趋势统计(跨会话积累各科数据)
class LocalCache {
  static const String _examListKey = 'cache_exam_list';
  static const String _detailPrefix = 'cache_exam_detail_';

  static Future<void> saveExamList(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_examListKey, jsonEncode(data));
  }

  static Future<Map<String, dynamic>?> getExamList() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_examListKey);
    if (s == null || s.isEmpty) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveExamDetail(String examGuid, Map<String, dynamic> raw) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_detailPrefix$examGuid', jsonEncode(raw));
  }

  static Future<Map<String, dynamic>?> getExamDetail(String examGuid) async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('$_detailPrefix$examGuid');
    if (s == null || s.isEmpty) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 清除全部缓存, 返回清除条数
  static Future<int> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((k) => k == _examListKey || k.startsWith(_detailPrefix))
        .toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
    return keys.length;
  }
}
