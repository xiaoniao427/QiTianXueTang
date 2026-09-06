import 'package:flutter/material.dart';

/// 全局导航Key: 供无 BuildContext 的场景(如401拦截)弹出对话框/跳转登录页
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
