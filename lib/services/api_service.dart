// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Returns the correct base URL for the current platform.
/// - Android emulator: 10.0.2.2 maps to your PC's localhost
/// - Android physical device: use your PC's WiFi IP (e.g. 192.168.1.5)
/// - iOS simulator / Web / Desktop: localhost
String getDefaultBaseUrl() {
  if (!kIsWeb && Platform.isAndroid) {
    // Change this to your PC's WiFi IP when using a real Android device
    return 'http://10.0.2.2:8000';
  }
  return 'http://localhost:8000';
}

class ApiService {
  String baseUrl;
  final _client = http.Client();
  static const _timeout = Duration(seconds: 10);

  ApiService({String? baseUrl}) : baseUrl = baseUrl ?? getDefaultBaseUrl();

  Map<String, String> get _h => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'ngrok-skip-browser-warning': 'true',
    'User-Agent': 'NetGuardApp/1.0',
  };

  Future<Map<String, dynamic>> _get(String path,
      {Map<String, String>? q}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: q);
    try {
      final r = await _client.get(uri, headers: _h).timeout(_timeout);
      return _parse(r);
    } on SocketException {
      throw ApiException(0, 'Cannot connect to server at $baseUrl');
    } on HttpException {
      throw ApiException(0, 'HTTP error');
    }
  }

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final r = await _client
          .post(uri, headers: _h, body: jsonEncode(body))
          .timeout(_timeout);
      return _parse(r);
    } on SocketException {
      throw ApiException(0, 'Cannot connect to server at $baseUrl');
    }
  }

  Map<String, dynamic> _parse(http.Response r) {
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 400) {
      throw ApiException(r.statusCode,
          body['detail']?.toString() ?? 'Server error ${r.statusCode}');
    }
    return body;
  }

  Future<bool> checkHealth() async {
    try {
      final r = await _get('/health');
      return r['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> startScan({String? interface}) =>
      _post('/scan/start', {'interface': interface});

  Future<Map<String, dynamic>> stopScan() =>
      _post('/scan/stop', {});

  Future<Map<String, dynamic>> getScanStatus({int maxPackets = 20}) =>
      _get('/scan/status',
          q: {'max_packets': maxPackets.toString()});

  Future<Map<String, dynamic>> detectThreats(
          List<Map<String, dynamic>> packets) =>
      _post('/detect', {'packets': packets});

  Future<Map<String, dynamic>> getPrediction() => _get('/predict');

  Future<Map<String, dynamic>> getLogs({
    int limit = 50,
    int offset = 0,
    String? severity,
    double? minScore,
  }) =>
      _get('/logs', q: {
        'limit': limit.toString(),
        'offset': offset.toString(),
        if (severity != null) 'severity': severity,
        if (minScore != null) 'min_score': minScore.toString(),
      });

  Future<Map<String, dynamic>> getDashboardData({int hours = 24}) =>
      _get('/dashboard-data', q: {'hours': hours.toString()});
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}
