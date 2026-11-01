import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/exam_model.dart';
import '../../providers/exam_provider.dart';

/// 考试详情页：总分 + 各科成绩
/// 数据源：Question/ScoreReport 的 {km_info, km_list}，km_list 已含全部单科，
/// 因此点击科目只需展示已加载数据，不再额外请求。
class ExamDetailPage extends StatefulWidget {
  final String examId;
  final String examName;
  const ExamDetailPage({super.key, required this.examId, required this.examName});

  @override
  State<ExamDetailPage> createState() => _ExamDetailPageState();
}

class _ExamDetailPageState extends State<ExamDetailPage> {
  @override
  void initState() {
    super.initState();
    // 使用 addPostFrameCallback 避免在 build 阶段调用 notifyListeners
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExamProvider>().loadExamDetail(widget.examId);
    });
  }

  void _showSubject(SubjectScore subject) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _SubjectDetailSheet(subject: subject),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.examName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<ExamProvider>().loadExamDetail(widget.examId),
          ),
        ],
      ),
      body: Consumer<ExamProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final exam = provider.currentExam;
          if (exam == null) {
            return const Center(
              child: Text('暂无数据', style: TextStyle(color: AppTheme.textSecondary)),
            );
          }
          final subjects = exam.subjects ?? const <SubjectScore>[];
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TotalCard(exam: exam),
                const SizedBox(height: 16),
                const Text('各科成绩',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (subjects.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无单科数据',
                        style: TextStyle(color: AppTheme.textSecondary)),
                  )
                else
                  ...subjects.map((s) => _SubjectCard(
                        subject: s,
                        onTap: () => _showSubject(s),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 总分卡片
class _TotalCard extends StatelessWidget {
  final ExamModel exam;
  const _TotalCard({required this.exam});

  @override
  Widget build(BuildContext context) {
    final score = exam.studentScore;
    final full = exam.totalScore;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('总分',
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  score == null ? '-' : _fmt(score),
                  style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor),
                ),
                if (full != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text('/ ${_fmt(full)}',
                        style: const TextStyle(
                            fontSize: 18, color: AppTheme.textSecondary)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (exam.totalGrade != null) _GradeTag(grade: exam.totalGrade!),
                if (exam.containFu) ...[
                  const SizedBox(width: 8),
                  const Text('含赋分科目',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ],
            ),
            if (exam.subjectSummary != null) ...[
              const SizedBox(height: 12),
              Text(exam.subjectSummary!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 单科行：科目 / 得分 / 满分 / 排名 / 等级
class _SubjectCard extends StatelessWidget {
  final SubjectScore subject;
  final VoidCallback onTap;
  const _SubjectCard({required this.subject, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final score = subject.displayScore;
    final full = subject.displayFullScore;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            subject.km.isEmpty ? '?' : subject.km.substring(0, 1),
            style: const TextStyle(fontSize: 16),
          ),
        ),
        title: Row(
          children: [
            Text(subject.km),
            if (subject.isFu) ...[
              const SizedBox(width: 6),
              const Text('赋分', style: TextStyle(fontSize: 11, color: AppTheme.primaryColor)),
            ],
          ],
        ),
        subtitle: Text(
          subject.isAbsent
              ? '缺考'
              : '${score == null ? '-' : _fmt(score)} / ${full == null ? '-' : _fmt(full)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (subject.grade != null) _GradeTag(grade: subject.grade!),
            if (subject.rating != null) ...[
              const SizedBox(width: 8),
              _RatingTag(rating: subject.rating!),
            ],
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

/// 等第标签（如 C4 / D3 / B5）。原 App 用字母等级表示相对位置，非数字排名。
class _GradeTag extends StatelessWidget {
  final String grade;
  const _GradeTag({required this.grade});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        grade,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: AppTheme.primaryColor,
        ),
      ),
    );
  }
}

/// 等级标签：「劣」标红（与原 App 一致）
class _RatingTag extends StatelessWidget {
  final String rating;
  const _RatingTag({required this.rating});

  @override
  Widget build(BuildContext context) {
    final bad = rating == '劣';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (bad ? AppTheme.errorColor : AppTheme.primaryColor).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        rating,
        style: TextStyle(
          fontSize: 11,
          color: bad ? AppTheme.errorColor : AppTheme.primaryColor,
        ),
      ),
    );
  }
}

/// 单科详情面板（数据已在内存，无网络请求）
class _SubjectDetailSheet extends StatelessWidget {
  final SubjectScore subject;
  const _SubjectDetailSheet({required this.subject});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _row('得分', subject.isAbsent
          ? '缺考'
          : '${subject.displayScore == null ? '-' : _fmt(subject.displayScore!)}'
              ' / ${subject.displayFullScore == null ? '-' : _fmt(subject.displayFullScore!)}'),
      if (subject.isFu && subject.score != null) _row('原始分', _fmt(subject.score!)),
      if (subject.isFu && subject.fuScore != null) _row('赋分', _fmt(subject.fuScore!)),
      // grade 是等第（如 C4），不是数字排名
      if (subject.grade != null) _row('等第', subject.grade!),
      if (subject.rating != null) _row('评价', subject.rating!),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(subject.km,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                if (subject.fuTag != null && subject.fuTag!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(subject.fuTag!,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ],
            ),
            const SizedBox(height: 12),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          Text(value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// 整数不带小数，非整数保留 1 位
String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);