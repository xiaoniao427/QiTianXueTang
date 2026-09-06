import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../models/exam_model.dart';
import '../models/study_report_model.dart';
import '../services/exam_service.dart';
import '../services/local_cache.dart';

class ExamProvider extends ChangeNotifier {
  final ExamService _examService = ExamService();
  List<ExamModel> _exams = [];
  ExamModel? _currentExam;
  StudyReportModel? _studyReport;
  bool _isLoading = false;
  bool _fromCache = false;
  int _unClaimCount = 0;
  // 科目附加数据(AI总结/作文信息): examGuid → {km → Subjects条目}
  final Map<String, Map<String, Map<String, dynamic>>> _subjectExtras = {};

  List<ExamModel> get exams => _exams;
  ExamModel? get currentExam => _currentExam;
  StudyReportModel? get studyReport => _studyReport;
  bool get isLoading => _isLoading;
  bool get fromCache => _fromCache;
  int get unClaimCount => _unClaimCount;

  /// 取某科目在 Subjects 接口里的附加数据(AI总结/作文等)
  Map<String, dynamic>? subjectExtra(String examGuid, String km) =>
      _subjectExtras[examGuid]?[km];

  /// 登录后/用户信息更新后配置业务上下文
  void updateContext({String? schoolGuid, String? grade, String? ruCode}) {
    _examService.setContext(schoolGuid: schoolGuid, grade: grade, ruCode: ruCode);
  }

  Future<void> loadExams({int page = 1}) async {
    // 冷启动先展示本地缓存, 网络返回后覆盖
    if (page == 1 && _exams.isEmpty) {
      final cached = await LocalCache.getExamList();
      if (cached != null) {
        try {
          final list = cached['list'];
          if (list is List && list.isNotEmpty) {
            _exams = list.map((e) => ExamModel.fromClaimJson(e)).toList();
            _fromCache = true;
            notifyListeners();
          }
        } catch (_) {}
      }
    }
    _isLoading = true;
    await Future<void>.delayed(Duration.zero);
    notifyListeners();
    final list = await _examService.getExamList(page: page, pageSize: 20);
    // 网络返回空但已有缓存/旧数据时保留(上下文未就绪等情况)
    if (page == 1 && list.isEmpty && _exams.isNotEmpty) {
      _isLoading = false;
      _fromCache = true;
      notifyListeners();
      return;
    }
    if (list.isNotEmpty) _fromCache = false;
    _exams = page == 1 ? list : [..._exams, ...list];
    _isLoading = false;
    notifyListeners();
  }

  /// 拉取 Subjects 完整响应, 提取每科 AI 总结/作文信息
  Future<void> loadSubjectExtras(String examGuid) async {
    if (_subjectExtras[examGuid] != null) return;
    try {
      final raw = await _examService.getSubjectsFull(examGuid);
      if (raw == null) return;
      final map = <String, Map<String, dynamic>>{};
      final list = raw['list'];
      if (list is List) {
        for (final e in list) {
          if (e is Map && e['km'] != null) {
            map[e['km'].toString()] = e.cast<String, dynamic>();
          }
        }
      }
      _subjectExtras[examGuid] = map;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadUnClaimCount(String studentName) async {
    final c = await _examService.getUnClaimCount(studentName: studentName);
    _unClaimCount = c;
    notifyListeners();
  }

  /// 考试详情/学情报告：下一批实现
  Future<void> loadExamDetail(String examId) async {
    _isLoading = true;
    notifyListeners();
    final exam = await _examService.getExamDetail(examId);
    _currentExam = exam;
    _isLoading = false;
    notifyListeners();
  }

  /// 获取单科列表
  Future<List<Map<String, dynamic>>?> loadSubjectList(String examId) async {
    _isLoading = true;
    notifyListeners();
    final list = await _examService.getSubjectList(examId);
    _isLoading = false;
    notifyListeners();
    return list;
  }

  Future<void> loadStudyReport() async {}
}