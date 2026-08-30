import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_navigator.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../models/saved_account.dart';

/// 多账号切换页: 展示已保存账号, 点按切换, 长按删除, 右上角添加新账号
class AccountSwitchPage extends StatelessWidget {
  const AccountSwitchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final currentUserCode = auth.user?.userId ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('切换账号'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt),
            tooltip: '添加账号',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('添加账号'),
                  content: const Text('将退出当前登录并前往登录页，'
                      '当前账号已保存在切换列表中，随时可以切回。'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('继续')),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                await context.read<AuthProvider>().logout();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                      context, MaterialPageRoute(builder: (_) => const LoginPageRoute()), (r) => false);
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 频控提醒: 服务端对登录频率有限制, 频繁切换可能被临时限流
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
            ),
            child: const Text(
              '温馨提示：服务端对登录请求频率有限制，两次切换请间隔 30 秒以上；'
              '短时间内频繁切换/请求可能导致 IP 被临时限制，届时请更换网络或稍后再试。',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ),
          Expanded(
            child: auth.savedAccounts.isEmpty
                ? const Center(
                    child: Text('暂无已保存账号\n登录后账号会自动保存在这里',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textSecondary)))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final account in auth.savedAccounts)
                        _buildAccountCard(context, auth, account,
                            isCurrent: account.userCode == currentUserCode),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(
      BuildContext context, AuthProvider auth, SavedAccount account,
      {required bool isCurrent}) {
    final initial = account.nickname.isEmpty
        ? (account.userCode.isEmpty ? '?' : account.userCode.substring(0, 1))
        : account.nickname.substring(0, 1);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCurrent
            ? const BorderSide(color: AppTheme.primaryColor, width: 1.5)
            : BorderSide.none,
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isCurrent ? AppTheme.primaryColor : Colors.grey[400],
          child: Text(initial,
              style: const TextStyle(color: Colors.white, fontSize: 18)),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                account.nickname.isEmpty ? account.userCode : account.nickname,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (isCurrent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('当前使用',
                    style:
                        TextStyle(fontSize: 11, color: AppTheme.primaryColor)),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(account.userCode, style: const TextStyle(fontSize: 13)),
            if (account.schoolName.isNotEmpty)
              Text(account.schoolName,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textHint)),
          ],
        ),
        trailing: isCurrent
            ? const Icon(Icons.check_circle, color: AppTheme.primaryColor)
            : const Icon(Icons.chevron_right),
        onTap: isCurrent || auth.switching
            ? null
            : () => _switch(context, auth, account),
        onLongPress: isCurrent
            ? null
            : () => _remove(context, auth, account),
      ),
    );
  }

  Future<void> _switch(
      BuildContext context, AuthProvider auth, SavedAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换账号'),
        content: Text('切换到「${account.nickname.isEmpty ? account.userCode : account.nickname}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('切换')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final err = await auth.switchAccount(account);
    if (!context.mounted) return;
    Navigator.pop(context); // 关闭loading
    if (err == null) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _remove(
      BuildContext context, AuthProvider auth, SavedAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账号'),
        content: Text('从切换列表中移除「${account.nickname.isEmpty ? account.userCode : account.nickname}」？\n'
            '不影响账号本身，之后重新登录即可再次保存。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) {
      await auth.removeAccount(account.userCode);
    }
  }
}

/// 借助命名路由跳登录页的包装页
class LoginPageRoute extends StatelessWidget {
  const LoginPageRoute({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appNavigatorKey.currentState
          ?.pushNamedAndRemoveUntil('/login', (route) => false);
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
