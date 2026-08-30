import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/exam_provider.dart';
import 'answer_sheet_page.dart';

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
      final provider = context.read<ExamProvider>();
      provider.loadExamDetail(widget.examId);
      provider.loadSubjectExtras(widget.examId);
    });
  }

  /// 分数显示: 有小数保留小数(331.5/84.5), 整数不带 .0(87/332)
  String _fmt(dynamic v) {
    if (v == null) return '-';
    if (v is num) return v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
    final d = double.tryParse(v.toString());
    if (d == null) return '-';
    return d % 1 == 0 ? d.toStringAsFixed(0) : d.toString();
  }

  Map<String, dynamic>? _essayOf(Map<String, dynamic>? extra) {
    if (extra == null) return null;
    final ar = extra['ai_essay_report'];
    if (ar is Map && ar['essayThInfo'] is Map) {
      return (ar['essayThInfo'] as Map).cast<String, dynamic>();
    }
    return null;
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
                          _fmt(exam.studentScore),
                          style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                        ),
                        Text(
                          '满分 ${_fmt(exam.totalScore)}',
                          style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatItem('班级排名', _fmt(exam.classRank)),
                            _buildStatItem('年级排名', _fmt(exam.gradeRank)),
                            _buildStatItem('班级平均', _fmt(exam.classAvg)),
                            _buildStatItem('年级平均', _fmt(exam.gradeAvg)),
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
                    final essay = _essayOf(
                        provider.subjectExtra(widget.examId, subject.subjectName));
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
                              '${_fmt(subject.score)} / ${_fmt(subject.fullScore)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            if (subject.grade != null)
                              Text(
                                '等级: ${subject.grade}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary),
                              ),
                            if (essay != null)
                              Text(
                                '作文 ${_fmt(essay['score'])}/${_fmt(essay['full'])} · '
                                '班级均分 ${_fmt(essay['avg'])} · 最高 ${_fmt(essay['max'])}',
                                style: const TextStyle(
                                    fontSize: 12, color: AppTheme.primaryColor),
                              ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AnswerSheetPage(
                                examId: widget.examId,
                                examName: exam.examName,
                                km: subject.subjectName,
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