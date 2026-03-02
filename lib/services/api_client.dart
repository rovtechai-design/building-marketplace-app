import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

class ApiClient {
  ApiClient({
    required this.authService,
    this.baseUrl = 'http://localhost:8000',
  });

  final String baseUrl;
  final AuthService authService;

  Future<http.Response> get(
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = _buildUri(path, query: query);
    final headers = await _buildHeaders();
    return http.get(uri, headers: headers);
  }

  Future<http.Response> postJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? query,
  }) async {
    final uri = _buildUri(path, query: query);
    final headers = await _buildHeaders();
    return http.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
  }

  Uri _buildUri(
    String path, {
    Map<String, String>? query,
  }) {
    final uri = Uri.parse('$baseUrl$path');
    if (query == null) {
      return uri;
    }

    return uri.replace(queryParameters: query);
  }

  Future<Map<String, String>> _buildHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (authService.currentUser != null) {
      headers['Authorization'] = 'Bearer ${await authService.getIdToken()}';
    }

    return headers;
  }
}
