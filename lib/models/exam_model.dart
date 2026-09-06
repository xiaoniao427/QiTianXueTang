class ExamModel {
  final String examId;
  final String examName;
  final String? subject;
  final String? gradeName;
  final String? examTime;
  final String? status;
  final double? totalScore;
  final double? studentScore;
  final double? classRank;
  final double? gradeRank;
  final double? classAvg;
  final double? gradeAvg;
  final List<SubjectScore>? subjects;

  ExamModel({
    required this.examId,
    required this.examName,
    this.subject,
    this.gradeName,
    this.examTime,
    this.status,
    this.totalScore,
    this.studentScore,
    this.classRank,
    this.gradeRank,
    this.classAvg,
    this.gradeAvg,
    this.subjects,
  });

  factory ExamModel.fromJson(Map<String, dynamic> json) {
    return ExamModel(
      examId: json['examId']?.toString() ?? '',
      examName: json['examName']?.toString() ?? '',
      subject: json['subject']?.toString(),
      gradeName: json['gradeName']?.toString(),
      examTime: json['examTime']?.toString(),
      status: json['status']?.toString(),
      totalScore: (json['totalScore'] as num?)?.toDouble(),
      studentScore: (json['studentScore'] as num?)?.toDouble(),
      classRank: (json['classRank'] as num?)?.toDouble(),
      gradeRank: (json['gradeRank'] as num?)?.toDouble(),
      classAvg: (json['classAvg'] as num?)?.toDouble(),
      gradeAvg: (json['gradeAvg'] as num?)?.toDouble(),
      subjects: (json['subjects'] as List<dynamic>?)
          ?.map((e) => SubjectScore.fromJson(e))
          .toList(),
    );
  }

  /// 考试详情解析：来自 ScoreReport 响应（字段名未知，防御性多键映射）
  factory ExamModel.fromDetailJson(Map<String, dynamic> json) {
    double? _d(Object? v) => (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '');
    String _s(List keys) {
      for (final k in keys) {
        final v = json[k];
        if (v != null && v.toString().isNotEmpty) return v.toString();
      }
      return '';
    }
    // 解析各科成绩（字段名可能为 subjects/subjectList/items 等）
    List<SubjectScore>? parseSubjects() {
      for (final k in ['subjects', 'subjectList', 'items', 'subjectScores', 'list']) {
        final v = json[k];
        if (v is List && v.isNotEmpty) {
          return v.map((e) => e is Map ? SubjectScore.fromJson(e.cast<String, dynamic>()) : null)
              .whereType<SubjectScore>().toList();
        }
      }
      return null;
    }
    return ExamModel(
      examId: _s(['examId', 'examGuid', 'id', 'guid']),
      examName: _s(['examName', 'name', 'paperName', 'title']),
      subject: _s(['subject', 'subjectName', 'courseName']),
      gradeName: _s(['gradeName', 'grade', 'currentGrade']),
      examTime: _s(['examTime', 'time', 'examDate', 'date']),
      status: _s(['status', 'type', 'examType']),
      totalScore: _d(json['totalScore'] ?? json['fullScore'] ?? json['total'] ?? json['fullMark']),
      studentScore: _d(json['studentScore'] ?? json['score'] ?? json['myScore'] ?? json['studentMark']),
      classRank: _d(json['classRank'] ?? json['classRanking'] ?? json['classOrder']),
      gradeRank: _d(json['gradeRank'] ?? json['gradeRanking'] ?? json['gradeOrder']),
      classAvg: _d(json['classAvg'] ?? json['classAverage'] ?? json['classAvgScore']),
      gradeAvg: _d(json['gradeAvg'] ?? json['gradeAverage'] ?? json['gradeAvgScore']),
      subjects: parseSubjects(),
    );
  }
  factory ExamModel.fromClaimJson(dynamic json) {
    final m = json is Map ? json : <String, dynamic>{};
    double? _d(Object? v) => (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '');
    return ExamModel(
      examId: m['examGuid']?.toString() ?? '',
      examName: m['examName']?.toString() ?? '',
      examTime: m['time']?.toString(),
      status: m['type']?.toString(),
      gradeName: m['grade']?.toString(),
      totalScore: _d(m['fullScore']) ?? _d(m['totalScore']),
      studentScore: _d(m['score']),
      // aiState/authView 用于详情是否可用
      subject: m['aiState']?.toString(),
    );
  }
}

class SubjectScore {
  final String subjectName;
  final double? score;
  final double? fullScore;
  final double? classAvg;
  final double? gradeAvg;
  final double? classRank;
  final double? gradeRank;
  final String? grade;

  SubjectScore({
    required this.subjectName,
    this.score,
    this.fullScore,
    this.classAvg,
    this.gradeAvg,
    this.classRank,
    this.gradeRank,
    this.grade,
  });

  factory SubjectScore.fromJson(Map<String, dynamic> json) {
    String _s(List keys) {
      for (final k in keys) {
        final v = json[k];
        if (v != null && v.toString().isNotEmpty) return v.toString();
      }
      return '';
    }
    double? _d(List keys) {
      for (final k in keys) {
        final v = json[k];
        if (v is num) return v.toDouble();
        final p = double.tryParse(v?.toString() ?? '');
        if (p != null) return p;
      }
      return null;
    }
    return SubjectScore(
      subjectName: _s(['km', 'subjectName', 'name', 'kmName']),
      score: _d(['score', 'myScore', 'studentScore', 'mark']),
      fullScore: _d(['fullScore', 'totalScore', 'fullMark', 'total']),
      classAvg: _d(['classAvg', 'classAverage', 'avgClass', 'classAvgScore']),
      gradeAvg: _d(['gradeAvg', 'gradeAverage', 'avgGrade', 'gradeAvgScore']),
      classRank: _d(['classRank', 'classRanking', 'rankClass', 'classOrder']),
      gradeRank: _d(['gradeRank', 'gradeRanking', 'rankGrade', 'gradeOrder']),
      grade: _s(['grade', 'level', 'ratingLevel']).isNotEmpty ? _s(['grade', 'level', 'ratingLevel']) : null,
    );
  }
}