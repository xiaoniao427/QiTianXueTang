import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/home_service.dart';

class HomeProvider extends ChangeNotifier {
  final HomeService _service = HomeService();
  List<PlateItem> _plates = [];
  List<AdItem> _ads = [];
  String _studyTotalHour = '';
  int _collectionQuantity = 0;
  int _noReadMessage = 0;
  bool _loading = false;

  List<PlateItem> get plates => _plates;
  List<AdItem> get ads => _ads;
  String get studyTotalHour => _studyTotalHour;
  int get collectionQuantity => _collectionQuantity;
  int get noReadMessage => _noReadMessage;
  bool get loading => _loading;

  Future<void> loadAll(UserModel user) async {
    _loading = true;
    notifyListeners();
    try {
      final results = await Future.wait<Object>([
        _service.getPlates(user),
        _service.getAds(user),
        _service.getStatistical(),
        _service.getMessageTop(),
      ]);
      _plates = results[0] as List<PlateItem>;
      _ads = results[1] as List<AdItem>;
      final stat = results[2] as Map<String, dynamic>;
      final message = results[3] as Map<String, dynamic>;
      _studyTotalHour = stat['studyTotalHour']?.toString() ?? '';
      _collectionQuantity = (stat['collectionQuantity'] as num?)?.toInt() ?? 0;
      _noReadMessage = (message['noReadNumber'] as num?)?.toInt() ?? 0;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
