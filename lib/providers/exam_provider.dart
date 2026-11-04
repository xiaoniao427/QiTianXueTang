import 'package:flutter/foundation.dart';
import '../models/exam_model.dart';
import '../services/exam_service.dart';

class ExamProvider extends ChangeNotifier {
  final ExamService _examService = ExamService();
  List<ExamModel> _exams = [];
  ExamModel? _currentExam;
  bool _isLoading = false;
  int _unClaimCount = 0;

  List<ExamModel> get exams => _exams;
  ExamModel? get currentExam => _currentExam;
  bool get isLoading => _isLoading;
  int get unClaimCount => _unClaimCount;

  /// 登录后/用户信息更新后配置业务上下文。
  /// ruCode 必须一起传，否则 Question/* 详情接口会返回空数据。
  void updateContext({String? schoolGuid, String? grade, String? ruCode}) {
    _examService.setContext(schoolGuid: schoolGuid, grade: grade, ruCode: ruCode);
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
    final count = await _examService.getUnClaimCount(studentName: studentName);
    _unClaimCount = count;
    notifyListeners();
  }

  /// 加载考试详情（Question/ScoreReport，请求侧 GCM 加密）
  Future<void> loadExamDetail(String examId) async {
    _isLoading = true;
    notifyListeners();
    final exam = await _examService.getExamDetail(examId);
    _currentExam = exam;
    _isLoading = false;
    notifyListeners();
  }
}
