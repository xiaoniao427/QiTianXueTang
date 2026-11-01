/// 七天学堂 API 配置
/// Ponytail: 根据真实抓包(HAR)修正。原App按业务拆分子域名，非 /api/v1。
/// 原App: var a={INDEX:l("index"),USER:l("my"),HOMEWORK:l("homework"),SCORE:l("score")}
///        l(t) => "https://szone-"+t+".7net.cc/"
class ApiConfig {
  // 各业务子域名
  static const String baseUser = 'https://szone-my.7net.cc';
  static const String baseScore = 'https://szone-score.7net.cc';
  static const String baseHomework = 'https://szone-homework.7net.cc';
  static const String baseIndex = 'https://szone-index.7net.cc';
  static const String baseActivity = 'https://szone-activity.7net.cc';
  static const String h5Base = 'https://h5.7net.cc';

  /// 认证头 Version 值 (原App: o="4.6.1")
  static const String version = '4.6.1';

  // 用户/认证 (szone-my)
  static const String login = '/login';                   // POST x-www-form-urlencoded: userCode+password
  static const String userInfo = '/userInfo/GetUserInfo'; // GET, 响应AES加密
  static const String userInfoStatistical = '/userInfo/statisticalRefresh'; // GET: studyTotalHour/collectionQuantity
  static const String userInfoUpdate = '/UserInfo/UpdateUserInfo';         // POST form: nickName
  static const String messageTop = '/Message/Top';                          // POST (空)消息
  static const String unionVipIsShow = '/UnionVip/IsShow';                  // POST form: grade
  static const String sdxOpen = '/SDX/Open';                                // POST form: currentGrade+ruCode

  // 成绩 (szone-score)
  static const String ganKaoSchoolIsOpen = '/GanKao/SchoolIsOpen'; // POST form: grade+schoolGuid -> {isOpen}
  static const String examGetClaimExams = '/exam/getClaimExams';   // GET startIndex+rows+schoolGuid+grade, AES加密
  static const String examGetExamCount = '/exam/getExamCount';     // GET studentName+schoolGuid+grade, AES加密
  static const String entranceConfig = '/Entrance/Config';         // GET schoolGuid+grade+types, 明文
  // 成绩详情（整卷报告）：响应GCM加密，请求体也加密进 bp 头(bn=iv)
  static const String questionScoreReport = '/Question/ScoreReport';       // POST, 响应GCM, bp=请求参数密文
  static const String questionAnswerCardUrl = '/Question/AnswerCardUrl';   // POST, 响应GCM
  static const String questionConclusion = '/Question/Conclusion';         // POST, 响应GCM
  static const String questionConfig = '/Question/Config';                 // POST, 响应GCM
  static const String questionSchoolRatingRules = '/Question/SchoolRatingRules'; // POST, 响应GCM

  // 作业 (szone-homework)
  static const String examHomeworkCheckOpen = '/ExamHomeWork/CheckSchoolIsOpen'; // POST form: studentName+ruCode+gradeCode

  // 首页 (szone-index)
  static const String getAdInfo = '/uad/getAdInfo';       // GET positionCode+cityCode+ruCode+grade+schoolGuid+currentGrade
  static const String navigationList = '/UNavigation/list'; // GET grade+schoolGuid+ruCode+cityCode+currentGrade
  static const String plateList = '/UPlate/plates';         // GET grade+currentGrade

  /// 响应AES解密密钥。原App: h = enc.Utf8.parse("c0f1a30c.."), mode:ECB padding:Pkcs7
  /// 响应当 data.isEncrypt==true 时 AesEcb.decrypt(content) 得到 JSON。
  /// 注意是 UTF-8 解析该字符串作为 256-bit key（32字节），非 hex。
  static const String aesKey = 'c0f1a30cba2147949ee71cf71cba3c20';

  // 密码加密见 QitianCrypto.encryptPassword:
  //   password = base64( 明文密码 + 常量后缀 "{MTgyMjU2MDU0MjF7c3pvbmV9}" )

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
}