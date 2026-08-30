import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/theme.dart';
import '../services/local_cache.dart';
import '../services/logger.dart';

/// 设置页: 调试日志开关、缓存管理
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _debugLog;

  @override
  void initState() {
    super.initState();
    _debugLog = logger.fileEnabled;
  }

  Future<void> _toggleDebugLog(bool v) async {
    setState(() => _debugLog = v);
    logger.setFileEnabled(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('debug_logging', v);
  }

  Future<void> _clearCache() async {
    final n = await LocalCache.clearAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清除 $n 条本地缓存（下次打开将重新拉取）')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('调试日志'),
            subtitle: Text(
              kReleaseMode
                  ? '关闭中。日志含成绩等个人信息，默认仅在诊断问题时开启'
                  : '开发版默认开启',
              style: const TextStyle(fontSize: 12),
            ),
            value: _debugLog,
            onChanged: _toggleDebugLog,
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services),
            title: const Text('清除本地缓存'),
            subtitle: const Text('考试列表与已浏览的成绩详情'),
            onTap: _clearCache,
          ),
          const Divider(),
          const ListTile(
            title: Text('关于'),
            subtitle: Text('七天学堂纯净版 4.6.1-patch · 学习研究用'),
          ),
        ],
      ),
    );
  }
}
