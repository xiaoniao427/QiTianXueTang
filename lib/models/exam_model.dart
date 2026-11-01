/// 成绩模型
/// 字段全部依据真实响应校准（GET /Question/ScoreReport 实测，2026-11-01）：
/// {
///   "km_info": {"isContainFuKm":0,"score":"358","fullScore":"600","grade":"C4"},
///   "km_list": [{"km":"语文","kmTag":0,"score":"45","fullScore":"120",
///                "fuScore":"","fuFullScore":"","grade":"D3","sort":"",
///                "rating":"","fuTag":false,"isFu":0}, ...,
///               {"km":"总分","kmTag":-2, ...}],
///   "other": {"totalSubjects":"语文+数学+...","fuTotalSubjects":""}
/// }
/// 注意两点易错处：
///   1. `grade` 是「等第」(如 C4/D3/B5)，不是数字排名。
///   2. `kmTag`: 0=正常, -2=总分行, -100=缺考。
class ExamModel {
  final String examId;
  final String examName;
  final String? gradeName;
  final String? examTime;
  final String? status;

  /// 总分信息（来自 km_info）
  final double? totalScore;
  final double? studentScore;

  /// 总分等第（km_info.grade，如 "C4"）
  final String? totalGrade;

  /// 各科（km_list 去掉总分行后的其余项）
  final List<SubjectScore>? subjects;

  /// 是否含赋分科目（km_info.isContainFuKm）
  final bool containFu;

  /// 参与统计的科目串（other.totalSubjects）
  final String? subjectSummary;

  ExamModel({
    required this.examId,
    required this.examName,
    this.gradeName,
    this.examTime,
    this.status,
    this.totalScore,
    this.studentScore,
    this.totalGrade,
    this.subjects,
    this.containFu = false,
    this.subjectSummary,
  });

  /// 考试列表解析：GET /exam/getClaimExams 的真实字段
  /// list 项: {examPublishType,isFu,ruleHash,examGuid,examName,type,time,score,grade,authView,aiState}
  /// 注意：列表接口只有 score（总分），没有满分/排名。
  factory ExamModel.fromClaimJson(dynamic json) {
    final m = json is Map ? json : <String, dynamic>{};
    return ExamModel(
      examId: m['examGuid']?.toString() ?? '',
      examName: m['examName']?.toString() ?? '',
      examTime: m['time']?.toString(),
      status: m['type']?.toString(),
      studentScore: _num(m['score']),
      containFu: m['isFu'] == 1 || m['isFu'] == true,
      // 列表项的 grade 通常为空串
      totalGrade: (m['grade']?.toString().isNotEmpty ?? false) ? m['grade'].toString() : null,
    );
  }

  /// 成绩详情解析：POST /Question/ScoreReport（解密后）
  factory ExamModel.fromDetailJson(Map<String, dynamic> json) {
    final info = json['km_info'] is Map
        ? (json['km_info'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final all = json['km_list'] is List
        ? (json['km_list'] as List)
            .whereType<Map>()
            .map((e) => SubjectScore.fromJson(e.cast<String, dynamic>()))
            .toList()
        : <SubjectScore>[];

    // 总分行（km=="总分"）单独摘出，它的数据同时也在 km_info 里
    final subjects = all.where((s) => !s.isTotal).toList();
    SubjectScore? totalRow;
    for (final s in all) {
      if (s.isTotal) {
        totalRow = s;
        break;
      }
    }
    final other = json['other'] is Map
        ? (json['other'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    return ExamModel(
      examId: json['examGuid']?.toString() ?? '',
      examName: json['examName']?.toString() ?? '',
      gradeName: json['grade']?.toString(),
      examTime: json['queryTime']?.toString(),
      // 总分优先取 km_info，回退到总分行
      studentScore: _num(info['score']) ?? totalRow?.score,
      totalScore: _num(info['fullScore']) ?? totalRow?.fullScore,
      totalGrade: (info['grade']?.toString().isNotEmpty ?? false)
          ? info['grade'].toString()
          : totalRow?.grade,
      subjects: subjects.isEmpty ? null : subjects,
      containFu: info['isContainFuKm'] == 1 || info['isContainFuKm'] == true,
      subjectSummary: (other['totalSubjects']?.toString().isNotEmpty ?? false)
          ? other['totalSubjects'].toString()
          : null,
    );
  }
}

/// 单科成绩行，对应 ScoreReport 的 km_list 每项（字段名以实测响应为准）
class SubjectScore {
  final String km; // 科目名
  final double? score;
  final double? fullScore;

  /// 等第，如 "D3" / "C4" / "B5"（**不是数字排名**）
  final String? grade;

  /// 综合评价，实测为 ""；原 App 模板里为 "劣" 时标红
  final String? rating;

  final bool isFu; // 是否赋分
  final double? fuScore; // 赋分后分数（实测为 ""）
  final double? fuFullScore;
  final String? fuTag; // 赋分文字（实测响应里是 bool，统一转字符串）
  final double? kmTag; // 0=正常, -2=总分, -100=缺考
  final String? sort;

  SubjectScore({
    required this.km,
    this.score,
    this.fullScore,
    this.grade,
    this.rating,
    this.isFu = false,
    this.fuScore,
    this.fuFullScore,
    this.fuTag,
    this.kmTag,
    this.sort,
  });

  bool get isTotal => km == '总分';

  /// kmTag == -100 表示缺考（模板 ue 渲染「缺考」）
  bool get isAbsent => kmTag == -100;

  /// 展示用得分：赋分科目优先显示赋分
  double? get displayScore => isFu ? (fuScore ?? score) : score;

  double? get displayFullScore => isFu ? (fuFullScore ?? fullScore) : fullScore;

  factory SubjectScore.fromJson(Map<String, dynamic> json) {
    return SubjectScore(
      km: json['km']?.toString() ?? '',
      score: _num(json['score']),
      fullScore: _num(json['fullScore']),
      grade: _str(json['grade']),
      rating: _str(json['rating']),
      isFu: json['isFu'] == 1 || json['isFu'] == true,
      fuScore: _num(json['fuScore']),
      fuFullScore: _num(json['fuFullScore']),
      // 实测 fuTag 为 bool；非空才当文字用
      fuTag: json['fuTag'] == true ? '赋分' : _str(json['fuTag']),
      kmTag: _num(json['kmTag']),
      sort: _str(json['sort']),
    );
  }
}

/// 数字：兼容 num 与数字字符串（响应普遍用字符串，如 "45"）
double? _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null; // 空串表示无值（fuScore/fuFullScore 实测为 ""）
  return double.tryParse(s);
}

/// 非空字符串；空串归一为 null，省掉调用处一堆 isNotEmpty 判断
String? _str(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty || s == 'false') ? null : s;
}