import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/exam_model.dart';
import '../../services/exam_service.dart';
import '../../services/local_cache.dart';
import '../../services/logger.dart';
import '../../providers/exam_provider.dart';

/// 成绩趋势: 总分趋势直接取考试列表; 各科趋势从本地缓存的成绩详情聚合,
/// 可一键拉取全部历史详情(串行+间隔, 避免触发服务端风控)。
/// 支持勾选考试参与绘图(全选/全不选/反选)与反向绘制。
class ScoreTrendPage extends StatefulWidget {
  const ScoreTrendPage({super.key});

  @override
  State<ScoreTrendPage> createState() => _ScoreTrendPageState();
}

class _ScoreTrendPageState extends State<ScoreTrendPage> {
  final ExamService _examService = ExamService();
  bool _loading = true;
  bool _fetchingAll = false;
  String _fetchText = '';
  String _selectedKm = '总分';
  // examGuid → (考试名, 时间, {km: score})
  final List<_ExamRecord> _records = [];
  final Set<String> _checked = {};
  bool _reversed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final exams = context.read<ExamProvider>().exams;
    for (final e in exams) {
      final score = e.studentScore;
      final rec = _ExamRecord(e.examId, e.examName, e.examTime ?? e.gradeName ?? '');
      if (score != null && score > 0) rec.total = score;
      // 本地缓存里已有的成绩详情
      final raw = await LocalCache.getExamDetail(e.examId);
      if (raw != null) _fillKmScores(rec, raw);
      _records.add(rec);
    }
    // 默认全部参与绘图
    _checked.addAll(_records.map((r) => r.examGuid));
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _fillKmScores(_ExamRecord rec, Map<String, dynamic> raw) {
    final kmInfo = raw['km_info'];
    if (kmInfo is Map) {
      final s = double.tryParse(kmInfo['score']?.toString() ?? '');
      // 0 分 = 官方未提供总分(批阅中/无总分界面), 不当作真实数据
      if (s != null && s > 0 && rec.total == null) rec.total = s;
    }
    final kmList = raw['km_list'];
    if (kmList is List) {
      for (final e in kmList) {
        if (e is! Map || e['km'] == null) continue;
        final s = double.tryParse(e['score']?.toString() ?? '');
        if (s != null) rec.kmScores[e['km'].toString()] = s;
      }
    }
  }

  List<String> get _allKms {
    final set = <String>{'总分'};
    for (final r in _records) {
      set.addAll(r.kmScores.keys);
    }
    final list = set.where((k) => k != '总分').toList()..sort();
    return ['总分', ...list];
  }

  /// 当前勾选且有有效数据的记录, 按绘制顺序排列
  List<_ExamRecord> get _plotted {
    final km = _selectedKm;
    var rs = _records
        .where((r) => _checked.contains(r.examGuid))
        .toList();
    rs = rs.where((r) {
      final v = km == '总分' ? r.total : r.kmScores[km];
      // 总分 0 = 官方无数据(批阅中), 不参与绘图
      return v != null && !(km == '总分' && v <= 0);
    }).toList();
    if (_reversed) rs = rs.reversed.toList();
    return rs;
  }

  List<FlSpot> get _spots {
    final km = _selectedKm;
    final plotted = _plotted;
    final spots = <FlSpot>[];
    for (var i = 0; i < plotted.length; i++) {
      final v = km == '总分' ? plotted[i].total : plotted[i].kmScores[km];
      spots.add(FlSpot(i.toDouble(), v!));
    }
    return spots;
  }

  String _label(int i) {
    if (i < 0 || i >= _plotted.length) return '';
    final t = _plotted[i].time;
    final m = RegExp(r'\d{2}-\d{2}').firstMatch(t);
    return m != null ? m.group(0)! : '${i + 1}';
  }

  void _setAllChecked(bool v) {
    setState(() {
      _checked
        ..clear()
        ..addAll(_records.map((r) => r.examGuid).where((_) => v));
    });
  }

  void _invertChecked() {
    setState(() {
      final next = <String>{};
      for (final r in _records) {
        if (!_checked.contains(r.examGuid)) next.add(r.examGuid);
      }
      _checked
        ..clear()
        ..addAll(next);
    });
  }

  /// 拉取全部历史成绩详情(每次请求间隔 1.5 秒防风控)
  Future<void> _fetchAllDetails() async {
    if (_fetchingAll) return;
    setState(() => _fetchingAll = true);
    var done = 0;
    try {
      for (final r in _records) {
        if (r.total != null && r.kmScores.isNotEmpty) {
          done++;
          continue;
        }
        setState(() => _fetchText = '拉取历史成绩 ${done + 1}/${_records.length}...');
        final detail = await _examService.getExamDetail(r.examGuid);
        if (detail != null) {
          final raw = await LocalCache.getExamDetail(r.examGuid);
          if (raw != null) _fillKmScores(r, raw);
        }
        done++;
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
    } catch (e) {
      logger.error('Trend', '拉取历史成绩失败', e);
    } finally {
      if (mounted) {
        setState(() {
          _fetchingAll = false;
          _fetchText = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spots = _spots;
    final plotted = _plotted;
    final maxY = spots.isEmpty
        ? 100.0
        : spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('成绩趋势'),
        actions: [
          IconButton(
            onPressed: _fetchingAll ? null : _fetchAllDetails,
            icon: const Icon(Icons.cloud_download),
            tooltip: '拉取全部历史成绩',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    const Text('科目：',
                        style: TextStyle(color: AppTheme.textSecondary)),
                    Expanded(
                      child: DropdownButton<String>(
                        value: _allKms.contains(_selectedKm)
                            ? _selectedKm
                            : '总分',
                        isExpanded: true,
                        items: _allKms
                            .map((k) => DropdownMenuItem(
                                value: k, child: Text(k)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedKm = v ?? '总分'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 绘图控制: 反向绘制 + 勾选快捷键
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      label: const Text('反向绘制'),
                      selected: _reversed,
                      onSelected: (v) => setState(() => _reversed = v),
                    ),
                    ActionChip(
                      label: const Text('全选'),
                      onPressed: () => _setAllChecked(true),
                    ),
                    ActionChip(
                      label: const Text('全不选'),
                      onPressed: () => _setAllChecked(false),
                    ),
                    ActionChip(
                      label: const Text('反选'),
                      onPressed: _invertChecked,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 260,
                  child: spots.length < 2
                      ? Center(
                          child: Text(
                          spots.isEmpty ? '暂无数据（勾选考试参与绘图）' : '只有一场有数据，无法画趋势线',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppTheme.textSecondary),
                        ))
                      : LineChart(
                          LineChartData(
                            minY: 0,
                            maxY: maxY,
                            gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                horizontalInterval: maxY > 0 ? maxY / 5 : 1),
                            titlesData: FlTitlesData(
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(
                                    showTitles: true, reservedSize: 40),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 28,
                                  getTitlesWidget: (v, meta) => Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(_label(v.toInt()),
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: AppTheme.textSecondary)),
                                  ),
                                ),
                              ),
                              topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(
                                show: true,
                                border: Border.all(color: Colors.grey.shade300)),
                            lineBarsData: [
                              LineChartBarData(
                                spots: spots,
                                isCurved: true,
                                color: AppTheme.primaryColor,
                                barWidth: 3,
                                dotData: const FlDotData(show: true),
                              ),
                            ],
                          ),
                        ),
                  ),
                if (_fetchText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_fetchText,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.primaryColor)),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('明细',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(
                      '已选 ${_checked.length}/${_records.length}',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._records.map((r) {
                  final checked = _checked.contains(r.examGuid);
                  final v =
                      _selectedKm == '总分' ? r.total : r.kmScores[_selectedKm];
                  // 总分 0 = 官方无数据; 单科 0 分可能是真实成绩, 保留
                  final invalid =
                      v == null || (v <= 0 && _selectedKm == '总分');
                  return Opacity(
                    opacity: checked ? 1 : 0.45,
                    child: ListTile(
                      dense: true,
                      leading: Checkbox(
                        value: checked,
                        onChanged: (_) => setState(() {
                          checked
                              ? _checked.remove(r.examGuid)
                              : _checked.add(r.examGuid);
                        }),
                      ),
                      title: Text(r.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle:
                          Text(r.time, style: const TextStyle(fontSize: 11)),
                      trailing: Text(
                        invalid ? '暂无' : _selectedKm == '总分' ? '$v 分' : '$v',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: invalid
                                ? AppTheme.textHint
                                : AppTheme.primaryColor),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                const Text(
                  '提示：各科历史数据来自已浏览过的考试详情，点右上角可拉取全部历史（每次请求间隔1.5秒，避免触发服务端风控）。勾选控制哪些考试参与绘图。',
                  style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                ),
              ],
            ),
    );
  }
}

class _ExamRecord {
  final String examGuid;
  final String name;
  final String time;
  double? total;
  final Map<String, double> kmScores = {};

  _ExamRecord(this.examGuid, this.name, this.time);
}
