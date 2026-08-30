import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 日志级别
enum LogLevel {
  debug(0),
  info(1),
  warn(2),
  error(3);

  final int value;
  const LogLevel(this.value);
}

/// 七天学堂日志系统
///
/// ponytail: 全局单例，日志只输出到文件 (外部存储 qitian_log.txt)。
/// 默认级别 debug，可运行时调高到 info 减少日志量。
/// 兜底: FlutterError.onError + PlatformDispatcher.onError 捕获未处理异常。
class AppLogger {
  // ─── 单例 ───────────────────────────────────────────────
  AppLogger._internal();
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;

  // ─── 状态 ───────────────────────────────────────────────
  LogLevel _level = LogLevel.info;
  File? _logFile;
  IOSink? _sink;
  bool _initialized = false;
  bool _fileEnabled = true;

  /// 日志文件开关: release 默认关闭(成绩属个人数据), 设置页可开
  bool get fileEnabled => _fileEnabled;
  void setFileEnabled(bool v) => _fileEnabled = v;

  // ─── 初始化 ─────────────────────────────────────────────
  Future<void> init({LogLevel level = LogLevel.debug}) async {
    if (_initialized) return;
    _level = level;

    // release 默认关闭文件日志(成绩属个人数据), 设置页可开
    try {
      final prefs = await SharedPreferences.getInstance();
      _fileEnabled = prefs.getBool('debug_logging') ?? !kReleaseMode;
    } catch (_) {}

    try {
      // 优先外部存储 (/storage/emulated/0/Android/data/<pkg>/files/)
      Directory? dir;
      try {
        dir = await getExternalStorageDirectory();
      } catch (_) {}
      // 兜底内部存储
      dir ??= await getApplicationDocumentsDirectory();

      _logFile = File('${dir.path}/qitian_log.txt');
      // 保留最近 1MB，避免日志文件无限膨胀
      if (await _logFile!.exists()) {
        final len = await _logFile!.length();
        if (len > 1024 * 1024) {
          // 截断到后半段
          final bytes = await _logFile!.readAsBytes();
          final half = bytes.length ~/ 2;
          await _logFile!.writeAsBytes(bytes.sublist(half));
        }
      }
      _sink = _logFile!.openWrite(mode: FileMode.append);
      _initialized = true;

      _write('I', 'Logger', '日志系统初始化完成: ${_logFile!.path}');
    } catch (e) {
      // 文件写入失败也不影响 App 运行，降级到仅控制台
      _initialized = true;
    }

    // 兜底：未捕获的 Flutter 错误
    FlutterError.onError = (details) {
      _write('E', 'FlutterError', '${details.exception}\n${details.stack}');
    };

    // 兜底：未捕获的异步异常
    PlatformDispatcher.instance.onError = (exception, stack) {
      _write('E', 'Platform', '$exception\n$stack');
      return true;
    };
  }

  // ─── 级别控制 ───────────────────────────────────────────
  void setLevel(LogLevel level) => _level = level;

  // ─── 核心写入 ───────────────────────────────────────────
  void _write(String tag, String module, String message) {
    final now = DateTime.now();
    final ts = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final line = '[$ts][$tag][$module] $message';

    // 只输出到文件(受开关控制)
    if (_fileEnabled && _sink != null) {
      _sink!.writeln(line);
    }
  }

  // ─── 公开方法 ───────────────────────────────────────────
  void debug(String module, String message) {
    if (_level.value > LogLevel.debug.value) return;
    _write('D', module, message);
  }

  void info(String module, String message) {
    if (_level.value > LogLevel.info.value) return;
    _write('I', module, message);
  }

  void warn(String module, String message) {
    if (_level.value > LogLevel.warn.value) return;
    _write('W', module, message);
  }

  void error(String module, String message, [Object? e, StackTrace? s]) {
    if (_level.value > LogLevel.error.value) return;
    final buf = StringBuffer(message);
    if (e != null) buf.write('\nException: $e');
    if (s != null) buf.write('\n$s');
    _write('E', module, buf.toString());
  }

  // ─── 获取日志文件路径 ───────────────────────────────────
  Future<String?> getLogFilePath() async {
    if (_logFile == null) return null;
    return _logFile!.path;
  }

  /// 读取全部日志（用于导出/分享）
  Future<String> readAll() async {
    if (_logFile == null) return '';
    try {
      return await _logFile!.readAsString();
    } catch (_) {
      return '';
    }
  }

  /// 清空日志
  Future<void> clear() async {
    if (_logFile == null) return;
    try {
      await _logFile!.writeAsString('');
    } catch (_) {}
  }

  void dispose() {
    _sink?.close();
  }
}

/// 便捷函数，在任意地方调用：logger.i('xxx') / logger.e('xxx')
final logger = AppLogger();