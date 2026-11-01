import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qitianxuetang/models/exam_model.dart';

/// ScoreReport 解析自检。
/// 样本是 **真实响应**（2026-11-01 实测 /Question/ScoreReport，解密后原文），
/// 不是构造的假数据，避免测试和实现一起跑偏。
const _realDetailJson = '''
{
  "km_info": {"isContainFuKm": 0, "score": "358", "fullScore": "600", "grade": "C4"},
  "km_list": [
    {"km":"语文","kmTag":0,"score":"45","fullScore":"120","fuScore":"","fuFullScore":"","grade":"D3","sort":"","rating":"","fuTag":false,"isFu":0},
    {"km":"数学","kmTag":0,"score":"57","fullScore":"120","fuScore":"","fuFullScore":"","grade":"C4","sort":"","rating":"","fuTag":false,"isFu":0},
    {"km":"英语","kmTag":0,"score":"76","fullScore":"120","fuScore":"","fuFullScore":"","grade":"C3","sort":"","rating":"","fuTag":false,"isFu":0},
    {"km":"总分","kmTag":-2,"score":"358","fullScore":"600","fuScore":"","fuFullScore":"","grade":"C4","sort":"","rating":"","fuTag":false,"isFu":0}
  ],
  "other": {"tips":"","totalSubjects":"语文+数学+英语","fuTotalSubjects":""}
}
''';

/// 真实考试列表样本（/exam/getClaimExams 解密后）
const _realClaimJson = '''
{"examPublishType":0,"isFu":0,"ruleHash":"","examGuid":"20251103-0236-4058-e0d7-6aa6cb804767",
 "examName":"吉林十中九年级期中检测","type":"期中","time":"2025-11-07","score":"358",
 "grade":"","authView":0,"aiState":0}
''';

void main() {
  group('ExamModel.fromDetailJson（真实响应）', () {
    late ExamModel exam;
    setUp(() {
      exam = ExamModel.fromDetailJson(
          jsonDecode(_realDetailJson) as Map<String, dynamic>);
    });

    test('总分取 km_info，满分为 600', () {
      expect(exam.studentScore, 358);
      expect(exam.totalScore, 600);
      expect(exam.totalGrade, 'C4');
    });

    test('总分行从科目列表摘出，不重复渲染', () {
      expect(exam.subjects!.map((s) => s.km), ['语文', '数学', '英语']);
    });

    test('每科分数按字符串解析（响应里是 "45" 不是 45）', () {
      final chinese = exam.subjects!.first;
      expect(chinese.score, 45);
      expect(chinese.fullScore, 120);
    });

    test('grade 是等第字符串，不被误解析成数字', () {
      expect(exam.subjects!.first.grade, 'D3');
    });

    test('other.totalSubjects 带出参与统计的科目', () {
      expect(exam.subjectSummary, '语文+数学+英语');
    });

    test('空串字段归一为 null（fuScore/fuFullScore/rating/sort 实测为 ""）', () {
      final s = exam.subjects!.first;
      expect(s.fuScore, isNull);
      expect(s.fuFullScore, isNull);
      expect(s.rating, isNull);
      expect(s.sort, isNull);
    });

    test('未被赋分时 isFu=false，展示分数即原始分', () {
      final s = exam.subjects!.first;
      expect(s.isFu, isFalse);
      expect(s.displayScore, 45);
    });

    test('kmTag=0 不算缺考', () {
      expect(exam.subjects!.every((s) => !s.isAbsent), isTrue);
    });
  });

  group('SubjectScore 边界（样本按实测结构构造）', () {
    test('kmTag=-100 判为缺考', () {
      final s = SubjectScore.fromJson(jsonDecode(
              '{"km":"英语","kmTag":-100,"score":"0","fuScore":"","fuFullScore":""}')
          as Map<String, dynamic>);
      expect(s.isAbsent, isTrue);
    });

    test('赋分科目展示时优先取赋分，原始分保留', () {
      final s = SubjectScore.fromJson(jsonDecode(
              '{"km":"物理","score":"70","fullScore":"100","isFu":1,'
              '"fuScore":"82","fuFullScore":"100","fuTag":true,"grade":"B5"}')
          as Map<String, dynamic>);
      expect(s.isFu, isTrue);
      expect(s.displayScore, 82);
      expect(s.displayFullScore, 100);
      expect(s.score, 70);
      // fuTag 实测是 bool，转成文字
      expect(s.fuTag, '赋分');
      expect(s.grade, 'B5');
    });

    test('空响应不崩，科目为 null', () {
      final e = ExamModel.fromDetailJson(<String, dynamic>{});
      expect(e.studentScore, isNull);
      expect(e.subjects, isNull);
    });
  });

  group('ExamModel.fromClaimJson（真实列表响应）', () {
    test('解析 examGuid/type/time/score，grade 空串归 null', () {
      final e = ExamModel.fromClaimJson(jsonDecode(_realClaimJson));
      expect(e.examId, '20251103-0236-4058-e0d7-6aa6cb804767');
      expect(e.examName, '吉林十中九年级期中检测');
      expect(e.status, '期中');
      expect(e.examTime, '2025-11-07');
      expect(e.studentScore, 358);
      // 列表项无满分/无等第
      expect(e.totalScore, isNull);
      expect(e.totalGrade, isNull);
    });
  });
}