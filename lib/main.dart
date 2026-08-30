import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/app_navigator.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/exam_provider.dart';
import 'providers/home_provider.dart';
import 'services/dio_client.dart';
import 'services/logger.dart';
import 'pages/splash_page.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger().init();
  logger.info('App', '应用启动');
  DioClient().init();
  runApp(const QiTianApp());
}

class QiTianApp extends StatelessWidget {
  const QiTianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..init()),
        ChangeNotifierProvider(create: (_) => ExamProvider()),
        ChangeNotifierProvider(create: (_) => HomeProvider()),
      ],
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        title: '七天学堂',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routes: {
          '/login': (_) => const LoginPage(),
          '/home': (_) => const HomePage(),
        },
        home: const SplashPage(),
      ),
    );
  }
}