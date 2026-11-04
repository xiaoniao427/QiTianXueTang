import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/home_provider.dart';
import 'exam/exam_list_page.dart';
import 'profile/profile_page.dart';

/// 安全取首字符
String _firstChar(String? s) =>
    (s == null || s.isEmpty) ? '?' : s.substring(0, 1);

/// 主界面：底部 3 个已实现的 Tab（首页 / 考试 / 我的）
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  static const _tabs = <Widget>[
    _HomeTab(),
    ExamListPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
          BottomNavigationBarItem(icon: Icon(Icons.assignment), label: '考试'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }
}

/// 首页 Tab：用户信息 + 学情/消息
class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  bool _loaded = false;

  void _maybeLoad() {
    if (_loaded) return;
    final user = context.read<AuthProvider>().user;
    if (user == null || user.schoolGuid == null || user.schoolGuid!.isEmpty) return;
    // 使用 addPostFrameCallback 在 build 完成后执行，避免在 build 阶段调用 notifyListeners
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeProvider>().loadAll(user).catchError((_) {});
    });
    _loaded = true;
  }

  @override
  Widget build(BuildContext context) {
    _maybeLoad();
    final user = context.watch<AuthProvider>().user;
    final home = context.watch<HomeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('七天学堂'),
        actions: [
          Stack(children: [
            IconButton(
              icon: const Icon(Icons.notifications_none),
              onPressed: () => _switchTo(context, 2),
            ),
            if (home.noReadMessage > 0)
              Positioned(
                right: 6, top: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                      color: AppTheme.errorColor, shape: BoxShape.circle),
                  child: Text('${home.noReadMessage}',
                      style: const TextStyle(color: Colors.white, fontSize: 9)),
                ),
              ),
          ]),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () {
          _loaded = false;
          return user == null
              ? Future.value()
              : context.read<HomeProvider>().loadAll(user).catchError((_) {});
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildUserCard(user?.nickname, user?.phone, user?.avatar,
                onTap: () => _switchTo(context, 2)),
            const SizedBox(height: 16),
            // 学情数据条
            if (home.studyTotalHour.isNotEmpty ||
                home.collectionQuantity > 0) ...[
              _buildStatBar(home.studyTotalHour, home.collectionQuantity),
              const SizedBox(height: 16),
            ],
            if (home.ads.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...home.ads.map((a) => _buildAd(a)),
            ],
            if (home.plates.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...home.plates.map((p) => _buildPlate(p)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatBar(String totalHour, int collection) {
    final hours = double.tryParse(totalHour) ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _statCell(hours.toStringAsFixed(1), "累计学习(时)"),
            _statCell("$collection", "收藏"),
          ],
        ),
      ),
    );
  }

  Widget _statCell(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor)),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      ],
    );
  }

  Widget _buildAd(AdItem a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: a.jumpLink.isNotEmpty ? () => _launchUrl(a.jumpLink) : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: a.imgLink.isNotEmpty
              ? Image.network(a.imgLink, height: 80, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(height: 80))
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  void _launchUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Widget _buildPlate(PlateItem p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: p.image.isNotEmpty
            ? Image.network(p.image, height: 96, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(height: 96))
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildUserCard(String? nickname, String? phone, String? avatar,
      {required VoidCallback onTap}) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppTheme.primaryColor,
                backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                child: avatar == null
                    ? Text(_firstChar(nickname),
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nickname ?? '同学',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(phone ?? '',
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  void _switchTo(BuildContext context, int index) {
    final h = context.findAncestorStateOfType<_HomePageState>();
    h?.setState(() => h._currentIndex = index);
  }
}
