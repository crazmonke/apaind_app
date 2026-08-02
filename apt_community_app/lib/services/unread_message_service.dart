import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';

/// 읽지 않은 쪽지 수 조회 서비스.
/// 서버의 GET /api/messages/unread-count (Sanctum Bearer) 를 사용한다.
class UnreadMessageService {
  UnreadMessageService._();

  static final UnreadMessageService instance = UnreadMessageService._();

  static const String _authTokenKey = 'auth_token';
  static const String _endpointPath = '/api/messages/unread-count';

  /// 읽지 않은 쪽지 수를 반환한다.
  /// 비로그인(토큰 없음)·네트워크 오류 시 null을 반환한다.
  Future<int?> fetchUnreadCount() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? authToken = prefs.getString(_authTokenKey);

    if (authToken == null || authToken.isEmpty) {
      return null;
    }

    final Uri endpoint = Uri.parse(kBaseWebUrl).resolve(_endpointPath);

    try {
      final http.Response response = await http
          .get(
            endpoint,
            headers: <String, String>{
              'Accept': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Unread count fetch failed: ${response.statusCode}');
        return null;
      }

      final Map<String, dynamic> json =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Object? value = json['unread_count'];

      if (value is int) {
        return value;
      }
      return int.tryParse(value?.toString() ?? '');
    } catch (error) {
      debugPrint('Unread count fetch error: $error');
      return null;
    }
  }
}
