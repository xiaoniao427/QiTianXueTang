import '../../models/exam_model.dart';
import 'dio_client.dart';
import 'logger.dart';

/// 成绩服务
/// ponytail: 依据真实抓包。列表用 szone-score/exam/getClaimExams (AES-ECB)，
/// 需要 schoolGuid/grade 上下文；详情(单科报告)属下一批(需请求侧AES-GCM加密)。
class ExamService {
  final DioClient _client = DioClient();
  // 需要调用方先配置上下文(setContext后才有值)
  String schoolGuid = '';
  String grade = '';

  /// 设置业务上下文(登录/GetUserInfo后调用)
  void setContext({String? schoolGuid, String? grade}) {
    if (schoolGuid != null && schoolGuid.isNotEmpty) this.schoolGuid = schoolGuid;
    if (grade != null && grade.isNotEmpty) this.grade = grade;
  }

  /// 获取考试列表
  Future<List<ExamModel>> getExamList({int page = 1, int pageSize = 20}) async {
    try {
      if (schoolGuid.isEmpty || grade.isEmpty) return [];
      final data = await _client.getClaimExams(
        startIndex: (page - 1) * pageSize,
        rows: pageSize,
        schoolGuid: schoolGuid,
        grade: grade,
      );
      if (data == null) return [];
      final list = data['list'];
      if (list is! List) return [];
      logger.debug('Exam', '考试列表 ${list.length} 条');
      return list.map((e) => ExamModel.fromClaimJson(e)).toList();
    } catch (e) {
      logger.error('Exam', '获取考试列表失败', e);
      return [];
    }
  }

  /// 未认领考试数
  Future<int> getUnClaimCount({required String studentName}) async {
    try {
      if (schoolGuid.isEmpty || grade.isEmpty) return 0;
      final data = await _client.getExamCount(
        studentName: studentName,
        schoolGuid: schoolGuid,
        grade: grade,
      );
      if (data == null) return 0;
      final n = data['unClaimCount'];
      if (n is num) return n.toInt();
      return data.containsKey('unClaimCount') ? int.tryParse('${data['unClaimCount']}') ?? 0 : 0;
    } catch (e) {
      logger.error('Exam', '获取未认领考试数失败', e);
      return 0;
    }
  }

  /// 考试详情（请求侧GCM加密）：POST Question/ScoreReport
  Future<ExamModel?> getExamDetail(String examId) async {
    try {
      if (schoolGuid.isEmpty || grade.isEmpty) {
        logger.error('Exam', '缺少上下文 schoolGuid=$schoolGuid grade=$grade');
        return null;
      }
      logger.debug('Exam', '开始获取考试详情 examGuid=$examId schoolGuid=$schoolGuid grade=$grade');
      final raw = await _client.getScoreReport(
        examGuid: examId,
        schoolGuid: schoolGuid,
        grade: grade,
      );
      if (raw == null) {
        logger.error('Exam', 'ScoreReport 返回 null');
        return null;
      }
      
      // 检查响应是否包含服务端错误（如 500）
      if (raw['status'] == 500) {
        logger.error('Exam', 'ScoreReport 服务端错误: ${raw['message']}');
        return null;
      }
      
      logger.debug('Exam', 'ScoreReport 响应类型: ${raw.runtimeType}');
      // raw 一定是 Map 类型（来自 _dataOf 返回）
      logger.debug('Exam', 'ScoreReport JSON keys: ${raw.keys.toList()}');
      final preview = raw.toString();
      logger.debug('Exam', 'ScoreReport JSON preview: ${preview.length > 200 ? preview.substring(0, 200) : preview}');
      // 用防御性映射解析：ScoreReport 响应含总分/各科/排名等
      final exam = ExamModel.fromDetailJson(raw);
      logger.debug('Exam', 'ScoreReport 解析后 exam: $exam');
      logger.debug('Exam', 'examName=${exam.examName}, studentScore=${exam.studentScore}, subjects=${exam.subjects?.length}');
      return exam;
    } catch (e) {
      logger.error('Exam', '获取考试详情失败: $e');
      return null;
    }
  }

  /// 获取单科列表（请求侧GCM加密）：POST Question/Subjects
  Future<List<Map<String, dynamic>>?> getSubjectList(String examId) async {
    try {
      if (schoolGuid.isEmpty || grade.isEmpty) return null;
      final raw = await _client.getSubjects(
        examGuid: examId,
        schoolGuid: schoolGuid,
        grade: grade,
      );
      if (raw == null) return null;
      logger.debug('Exam', 'Subjects 原始数据: $raw');
      return raw;
    } catch (e) {
      logger.error('Exam', '获取单科列表失败', e);
      return null;
    }
  }
}