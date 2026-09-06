import 'package:flutter/foundation.dart';
import '../models/exam_model.dart';
import '../models/study_report_model.dart';
import '../services/exam_service.dart';

class ExamProvider extends ChangeNotifier {
  final ExamService _examService = ExamService();
  List<ExamModel> _exams = [];
  ExamModel? _currentExam;
  StudyReportModel? _studyReport;
  bool _isLoading = false;
  int _unClaimCount = 0;

  List<ExamModel> get exams => _exams;
  ExamModel? get currentExam => _currentExam;
  StudyReportModel? get studyReport => _studyReport;
  bool get isLoading => _isLoading;
  int get unClaimCount => _unClaimCount;

  /// 登录后/用户信息更新后配置业务上下文
  void updateContext({String? schoolGuid, String? grade}) {
    _examService.setContext(schoolGuid: schoolGuid, grade: grade);
  }

  Future<void> loadExams({int page = 1}) async {
    _isLoading = true;
    await Future<void>.delayed(Duration.zero);
    notifyListeners();
    final list = await _examService.getExamList(page: page, pageSize: 20);
    _exams = page == 1 ? list : [..._exams, ...list];
    _isLoading = false;
    notifyListeners();
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