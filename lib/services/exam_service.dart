import '../../models/exam_model.dart';
import 'dio_client.dart';
import 'logger.dart';

/// 成绩服务
/// ponytail: 依据真实抓包。列表用 szone-score/exam/getClaimExams (AES-ECB)，
/// 需要 schoolGuid/grade 上下文；详情用 Question/ScoreReport (请求侧 AES-GCM)，
/// 额外还需 ruCode —— 缺它接口必空，见 ExamProvider.updateContext。
class ExamService {
  final DioClient _client = DioClient();
  // 需要调用方先配置上下文(setContext后才有值)
  String schoolGuid = '';
  String grade = '';
  String ruCode = '';

  /// 设置业务上下文(登录/GetUserInfo后调用)
  void setContext({String? schoolGuid, String? grade, String? ruCode}) {
    if (schoolGuid != null && schoolGuid.isNotEmpty) this.schoolGuid = schoolGuid;
    if (grade != null && grade.isNotEmpty) this.grade = grade;
    if (ruCode != null && ruCode.isNotEmpty) this.ruCode = ruCode;
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
      // 增加 ruCode 校验，保证调用端已设置完整上下文
      if (schoolGuid.isEmpty || grade.isEmpty || ruCode.isEmpty) {
        logger.error('Exam', '缺少上下文 schoolGuid=$schoolGuid grade=$grade ruCode=$ruCode');
        return null;
      }
      logger.debug('Exam', '开始获取考试详情 examGuid=$examId schoolGuid=$schoolGuid grade=$grade ruCode=$ruCode');
      final raw = await _client.getScoreReport(
        examGuid: examId,
        schoolGuid: schoolGuid,
        grade: grade,
        ruCode: ruCode, // 传入 ruCode
      );
      if (raw == null) {
        logger.error('Exam', 'ScoreReport 返回 null');
        return null;
      }

      // 解密后若无 km_info/km_list，说明业务未返回成绩（关闭查询/未发布等），
      // 不要展示成"暂无数据"的空壳：直接判失败。
      if (raw['km_list'] == null && raw['km_info'] == null) {
        logger.error('Exam', 'ScoreReport 无成绩数据: ${raw.keys.toList()}');
        return null;
      }

      logger.debug('Exam', 'ScoreReport keys: ${raw.keys.toList()}');
      final exam = ExamModel.fromDetailJson(raw);
      logger.debug('Exam',
          'ScoreReport 解析: examName=${exam.examName}, 总分=${exam.studentScore}/${exam.totalScore}, 科目数=${exam.subjects?.length}');
      return exam;
    } catch (e) {
      logger.error('Exam', '获取考试详情失败: $e');
      return null;
    }
  }
}
