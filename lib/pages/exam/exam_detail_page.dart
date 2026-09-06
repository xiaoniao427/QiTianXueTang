import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/exam_provider.dart';
import 'exam_subject_detail_page.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.examName)),
      body: Consumer<ExamProvider>(
        builder: (context, provider, _) {
          final exam = provider.currentExam;
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (exam == null) {
            return const Center(child: Text('暂无数据'));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 总分卡片
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Text('总分', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                        const SizedBox(height: 8),
                        Text(
                          exam.studentScore?.toStringAsFixed(0) ?? '-',
                          style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                        ),
                        Text(
                          '满分 ${exam.totalScore?.toStringAsFixed(0) ?? '-'}',
                          style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatItem('班级排名', exam.classRank?.toStringAsFixed(0) ?? '-'),
                            _buildStatItem('年级排名', exam.gradeRank?.toStringAsFixed(0) ?? '-'),
                            _buildStatItem('班级平均', exam.classAvg?.toStringAsFixed(0) ?? '-'),
                            _buildStatItem('年级平均', exam.gradeAvg?.toStringAsFixed(0) ?? '-'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 各科成绩
                const Text('各科成绩', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (exam.subjects != null && exam.subjects!.isNotEmpty)
                  ...exam.subjects!.asMap().entries.map((entry) {
                    final subject = entry.value;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            subject.subjectName.substring(0, 1),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        title: Text(subject.subjectName),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${subject.score?.toStringAsFixed(0) ?? '-'} / ${subject.fullScore?.toStringAsFixed(0) ?? '-'}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            if (subject.classAvg != null)
                              Text(
                                '班级平均: ${subject.classAvg!.toStringAsFixed(1)}',
                                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                              ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ExamSubjectDetailPage(
                                examId: exam.examId,
                                examName: exam.examName,
                                subjectName: subject.subjectName,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }).toList(),
                if (exam.subjects == null || exam.subjects!.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '暂无单科数据',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      ],
    );
  }
}