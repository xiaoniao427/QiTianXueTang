/// 已保存的多账号信息 (存储于加密安全存储)
class SavedAccount {
  final String userCode; // 手机号/登录名
  final String password; // 保存密码用于切换时静默重登 (仅存于本机安全存储)
  final String nickname;
  final String schoolName;
  final String userJson; // 完整 UserModel.toJson (含 token)
  final String savedAt;

  SavedAccount({
    required this.userCode,
    this.password = '',
    this.nickname = '',
    this.schoolName = '',
    this.userJson = '',
    this.savedAt = '',
  });

  factory SavedAccount.fromJson(Map<String, dynamic> json) => SavedAccount(
        userCode: json['userCode']?.toString() ?? '',
        password: json['password']?.toString() ?? '',
        nickname: json['nickname']?.toString() ?? '',
        schoolName: json['schoolName']?.toString() ?? '',
        userJson: json['userJson']?.toString() ?? '',
        savedAt: json['savedAt']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'userCode': userCode,
        'password': password,
        'nickname': nickname,
        'schoolName': schoolName,
        'userJson': userJson,
        'savedAt': savedAt,
      };
}
