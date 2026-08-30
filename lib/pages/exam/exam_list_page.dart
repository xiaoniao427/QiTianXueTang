import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/exam_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/exam_model.dart';
import 'exam_detail_page.dart';
import 'score_trend_page.dart';

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
      appBar: AppBar(
        title: const Text('考试成绩'),
        actions: [
          IconButton(
            icon: const Icon(Icons.insights),
            tooltip: '成绩趋势',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ScoreTrendPage()),
            ),
          ),
        ],
      ),
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
              if (exam.examTime != null)
                Text(
                  '考试时间: ${exam.examTime}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              const SizedBox(height: 12),
              if (exam.studentScore != null && exam.totalScore != null)
                Row(
                  children: [
                    _ScoreChip(label: '得分', value: '${exam.studentScore!.toStringAsFixed(0)}/${exam.totalScore!.toStringAsFixed(0)}'),
                    if (exam.classRank != null)
                      _ScoreChip(label: '班级排名', value: exam.classRank!.toStringAsFixed(0)),
                    if (exam.gradeRank != null)
                      _ScoreChip(label: '年级排名', value: exam.gradeRank!.toStringAsFixed(0)),
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