import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/exam_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/exam_model.dart';
import 'exam_detail_page.dart';

class ExamListPage extends StatefulWidget {
  const ExamListPage({super.key});

  @override
  State<ExamListPage> createState() => _ExamListPageState();
}

class _ExamListPageState extends State<ExamListPage> {
  @override
  void initState() {
    super.initState();
    // 配置业务上下文(需要登录用户信息)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().user;
      context.read<ExamProvider>().updateContext(
            schoolGuid: user?.schoolGuid,
            grade: user?.grade,
            ruCode: user?.ruCode,
          );
      final provider = context.read<ExamProvider>();
      if (user?.studentName != null) {
        provider.loadUnClaimCount(user!.studentName!);
      }
      provider.loadExams();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('考试成绩')),
      body: Consumer<ExamProvider>(
        builder: (context, examProvider, _) {
          if (examProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (examProvider.exams.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment_late, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text(
                    '暂无考试记录',
                    style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => examProvider.loadExams(),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: examProvider.exams.length,
              itemBuilder: (context, index) {
                final exam = examProvider.exams[index];
                return _ExamCard(exam: exam);
              },
            ),
          );
        },
      ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  final ExamModel exam;
  const _ExamCard({required this.exam});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ExamDetailPage(examId: exam.examId, examName: exam.examName),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                exam.examName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (exam.status != null && exam.status!.isNotEmpty) ...[
                    _Tag(text: exam.status!),
                    const SizedBox(width: 8),
                  ],
                  if (exam.examTime != null && exam.examTime!.isNotEmpty)
                    Text(
                      exam.examTime!,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // 列表接口只返回总分(score)，无满分/排名，详情页才有
              Row(
                children: [
                  _ScoreChip(
                    label: '总分',
                    value: exam.studentScore == null
                        ? '-'
                        : _fmt(exam.studentScore!),
                  ),
                  const Icon(Icons.chevron_right, color: AppTheme.textHint),
                  const SizedBox(width: 4),
                  const Text('查看各科成绩',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  final String label;
  final String value;
  const _ScoreChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textHint)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
        ],
      ),
    );
  }
}

/// 考试类型标签（期中/月考…，对应列表接口的 type 字段）
class _Tag extends StatelessWidget {
  final String text;
  const _Tag({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 11, color: AppTheme.primaryColor)),
    );
  }
}

/// 整数不带小数，非整数保留 1 位
String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);