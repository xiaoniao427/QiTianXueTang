import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../account_switch_page.dart';
import '../login_page.dart';
import '../settings_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 用户信息 (点击编辑昵称)
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _editNickname(context),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: AppTheme.primaryColor,
                      backgroundImage: user?.avatar != null ? NetworkImage(user!.avatar!) : null,
                      child: user?.avatar == null
                          ? Text(
                              ((user?.nickname ?? '').isEmpty ? '?' : user!.nickname!.substring(0, 1)),
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user?.nickname ?? '同学',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(user?.phone ?? '', style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                          if (user?.schoolName != null)
                            Text(user!.schoolName!, style: const TextStyle(fontSize: 13, color: AppTheme.textHint)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
          const SizedBox(height: 16),

          // 功能菜单
          _buildMenuItem(Icons.assignment, '考试记录', () {}),
          _buildMenuItem(Icons.analytics, '学情报告', () {}),
          _buildMenuItem(Icons.auto_awesome, 'AI诊断', () {}),
          _buildMenuItem(Icons.star, '我的收藏', () {}),
          _buildMenuItem(Icons.help_outline, '帮助中心', () {}),
          _buildMenuItem(Icons.settings_outlined, '设置', () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            );
          }),
          const Divider(height: 32),
          _buildMenuItem(Icons.switch_account_outlined, '切换账号', () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountSwitchPage()),
            );
          }),
          _buildMenuItem(Icons.logout, '退出登录', () => _logout(context), color: AppTheme.errorColor),
        ],
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppTheme.textPrimary),
      title: Text(title, style: TextStyle(color: color)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }

  /// 编辑昵称对话框
  Future<void> _editNickname(BuildContext context) async {
    final controller = TextEditingController(text: context.read<AuthProvider>().user?.nickname ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改昵称'),
        content: TextField(
          controller: controller,
          maxLength: 16,
          decoration: const InputDecoration(hintText: '请输入新昵称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (saved == true) {
      final name = controller.text.trim();
      if (name.isNotEmpty) {
        final ok = await context.read<AuthProvider>().updateNickname(name);
        if (context.mounted && ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('昵称已更新')),
          );
        }
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirmed == true) {
      await context.read<AuthProvider>().logout();
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
    }
  }
}