import 'dart:convert';

import '../../models/exam_model.dart';
import 'dio_client.dart';
import 'local_cache.dart';
import 'logger.dart';

/// 成绩服务
/// ponytail: 依据真实抓包。列表用 szone-score/exam/getClaimExams (AES-ECB)，
/// 需要 schoolGuid/grade 上下文；详情(单科报告)属下一批(需请求侧AES-GCM加密)。
class ExamService {
  // 单例: AuthProvider/ExamProvider 各处持有的必须是同一实例, 否则上下文丢失
  static final ExamService _instance = ExamService._internal();
  factory ExamService() => _instance;
  ExamService._internal();

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
      await LocalCache.saveExamList(data);
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
      logger.debug('Exam', '开始获取考试详情 examGuid=$examId schoolGuid=$schoolGuid grade=$grade ruCode=$ruCode');
      final raw = await _client.getScoreReport(
        examGuid: examId,
        schoolGuid: schoolGuid,
        grade: grade,
        ruCode: ruCode,
        km: '总分',
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

      logger.debug('Exam', 'ScoreReport JSON keys: ${raw.keys.toList()}');
      logger.debug('Exam', 'ScoreReport 原始响应: $raw');
      await LocalCache.saveExamDetail(examId, raw);

      // 真实结构（与官方JS一致）: {km_info:{score,fullScore,grade}, km_list:[{km,score,fullScore,grade,...}], other}
      final flat = Map<String, dynamic>.from(raw);
      final kmList = raw['km_list'];
      if (kmList is List && kmList.isNotEmpty) {
        final subjects = kmList
            .whereType<Map>()
            .where((e) => e['km'] != '总分')
            .map((e) => e.cast<String, dynamic>())
            .toList();
        Map<String, dynamic>? totalEntry;
        for (final e in kmList) {
          if (e is Map && e['km'] == '总分') {
            totalEntry = e.cast<String, dynamic>();
            break;
          }
        }

        // 总分取值优先级: km_info → km_list"总分"条目 → 各科求和兜底。
        // 部分考试官方不提供总分数据(总分/满分为0或缺失), 此时按单科求和
        double? totalScore;
        double? totalFull;
        final kmInfo = raw['km_info'];
        if (kmInfo is Map) {
          totalScore = double.tryParse(kmInfo['score']?.toString() ?? '');
          totalFull = double.tryParse(kmInfo['fullScore']?.toString() ?? '');
        }
        if (totalEntry != null) {
          if (totalScore == null || totalScore == 0) {
            totalScore = double.tryParse(totalEntry['score']?.toString() ?? '');
          }
          if (totalFull == null || totalFull == 0) {
            totalFull = double.tryParse(totalEntry['fullScore']?.toString() ?? '');
          }
        }
        if (totalScore == null ||
            totalScore == 0 ||
            totalFull == null ||
            totalFull == 0) {
          double sumScore = 0, sumFull = 0;
          var hasScore = false, hasFull = false;
          for (final s in subjects) {
            final sc = double.tryParse(s['score']?.toString() ?? '');
            final fu = double.tryParse(s['fullScore']?.toString() ?? '');
            if (sc != null) {
              sumScore += sc;
              hasScore = true;
            }
            if (fu != null) {
              sumFull += fu;
              hasFull = true;
            }
          }
          if (totalScore == null || totalScore == 0) {
            totalScore = hasScore ? sumScore : null;
          }
          if (totalFull == null || totalFull == 0) {
            totalFull = hasFull ? sumFull : null;
          }
          logger.debug('Exam',
              '官方未提供总分数据, 已按各科求和: 总分=$totalScore 满分=$totalFull');
        }

        flat['studentScore'] = totalScore;
        flat['totalScore'] = totalFull;
        flat['subjects'] = subjects;
        logger.debug('Exam', 'km_list ${kmList.length} 条, 总分=$totalScore/$totalFull');
      }

      final exam = ExamModel.fromDetailJson(flat);
      logger.debug('Exam', '解析后 examName=${exam.examName}, studentScore=${exam.studentScore}, '
          'totalScore=${exam.totalScore}, classRank=${exam.classRank}, gradeRank=${exam.gradeRank}, '
          'subjects=${exam.subjects?.length}');
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
      final raw = await getSubjectsFull(examId);
      final list = raw?['list'];
      if (list is List) return list.cast<Map<String, dynamic>>();
      return null;
    } catch (e) {
      logger.error('Exam', '获取单科列表失败', e);
      return null;
    }
  }

  /// Subjects 完整响应: {list:[{km,responseGuid,...}], exam_info:{ruleHash,...}}
  Future<Map<String, dynamic>?> getSubjectsFull(String examId) async {
    try {
      if (schoolGuid.isEmpty || grade.isEmpty) return null;
      final raw = await _client.getSubjects(
        examGuid: examId,
        schoolGuid: schoolGuid,
        grade: grade,
        ruCode: ruCode,
      );
      if (raw == null) return null;
      logger.debug('Exam', 'Subjects 完整数据: $raw');
      return raw;
    } catch (e) {
      logger.error('Exam', '获取单科数据失败', e);
      return null;
    }
  }

  /// 答题卡: Subjects(取 responseGuid/ruleHash) → Question/AnswerCardUrl
  Future<Map<String, dynamic>?> getAnswerSheet(String examId, String km) async {
    try {
      final raw = await getSubjectsFull(examId);
      if (raw == null) return null;

      String responseGuid = '';
      String ruleHash = '';
      final list = raw['list'];
      if (list is List) {
        for (final e in list) {
          if (e is Map && (e['km'] == km || (km == '总分' && e['kmTag'] != null))) {
            responseGuid = e['responseGuid']?.toString() ?? '';
            break;
          }
        }
      }
      final examInfo = raw['exam_info'];
      if (examInfo is Map) {
        ruleHash = examInfo['ruleHash']?.toString() ??
            examInfo['RuleHash']?.toString() ??
            '';
      }
      if (responseGuid.isEmpty) {
        logger.warn('Exam', 'Subjects 中未找到 km=$km 的 responseGuid');
        return {'error': '未找到该科目的答卷数据'};
      }

      return await _client.getAnswerCardUrl(
        examGuid: examId,
        responseGuid: responseGuid,
        schoolGuid: schoolGuid,
        grade: grade,
        ruleHash: ruleHash,
        ruCode: ruCode,
      );
    } catch (e) {
      logger.error('Exam', '获取答题卡失败: $e');
      return null;
    }
  }
}