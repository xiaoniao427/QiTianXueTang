import '../models/user_model.dart';
import 'dio_client.dart';
import 'logger.dart';

/// 首页板块图
class PlateItem {
  final String mainTitle;
  final String subtTitle;
  final String url;
  final String image;

  PlateItem({
    required this.mainTitle,
    required this.subtTitle,
    required this.url,
    required this.image,
  });

  factory PlateItem.fromJson(Map<String, dynamic> json) => PlateItem(
        mainTitle: json['mainTitle']?.toString() ?? '',
        subtTitle: json['subtTitle']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        image: json['image']?.toString() ?? '',
      );
}

/// 首页广告
class AdItem {
  final String imgLink;
  final String jumpLink;
  final String title;

  AdItem({required this.imgLink, required this.jumpLink, required this.title});

  factory AdItem.fromJson(Map<String, dynamic> json) => AdItem(
        imgLink: json['imgLink']?.toString() ?? '',
        jumpLink: json['jumpLink']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
      );
}

/// 首页板块图、广告、学情和消息服务
class HomeService {
  final DioClient _client = DioClient();

  /// 首页广告（positionCode 使用原 App 首页广告位 9）
  Future<List<AdItem>> getAds(UserModel user) async {
    try {
      if (_ctxMissing(user)) return [];
      final raw = await _client.getAdInfo(
        positionCode: '9',
        cityCode: user.cityCode ?? '',
        ruCode: user.ruCode ?? '',
        grade: _grade(user),
        schoolGuid: user.schoolGuid!,
        currentGrade: user.grade ?? _grade(user),
      );
      if (raw == null) return [];
      return raw
          .map((item) => item is Map
              ? AdItem.fromJson(item.cast<String, dynamic>())
              : null)
          .whereType<AdItem>()
          .toList();
    } catch (error) {
      logger.error('Home', '广告失败', error);
      return [];
    }
  }

  /// 首页板块图
  Future<List<PlateItem>> getPlates(UserModel user) async {
    try {
      if (_ctxMissing(user)) return [];
      final raw = await _client.getPlates(
        grade: _grade(user),
        currentGrade: user.grade ?? _grade(user),
      );
      if (raw == null) return [];
      return raw
          .map((item) => item is Map
              ? PlateItem.fromJson(item.cast<String, dynamic>())
              : null)
          .whereType<PlateItem>()
          .toList();
    } catch (error) {
      logger.error('Home', '板块失败', error);
      return [];
    }
  }

  /// 学情数据
  Future<Map<String, dynamic>> getStatistical() async {
    try {
      return await _client.getStatistical() ?? {};
    } catch (error) {
      logger.error('Home', '学情失败', error);
      return {};
    }
  }

  /// 消息摘要
  Future<Map<String, dynamic>> getMessageTop() async {
    try {
      return await _client.getMessageTop() ?? {};
    } catch (error) {
      logger.error('Home', '消息失败', error);
      return {};
    }
  }

  bool _ctxMissing(UserModel user) =>
      user.schoolGuid == null || user.schoolGuid!.isEmpty;

  String _grade(UserModel user) => user.grade ?? '';
}
