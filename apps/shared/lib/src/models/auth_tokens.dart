class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
      );

  final String accessToken;
  final String refreshToken;

  Map<String, dynamic> toJson() =>
      {'access_token': accessToken, 'refresh_token': refreshToken};
}
