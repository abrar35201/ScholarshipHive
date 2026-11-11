import 'package:dio/dio.dart';
import '../core/api_config.dart';
import '../core/api_exception.dart';
import 'secure_storage_service.dart';

class ApiClient {
  final Dio _dio;
  final SecureStorageService _storage;

  ApiClient(this._storage)
      : _dio = Dio(BaseOptions(
          connectTimeout: ApiConfig.timeout,
          receiveTimeout: ApiConfig.timeout,
          validateStatus: (status) => status != null && status < 500,
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.readToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  /// [receiveTimeout] lets slow endpoints (e.g. the AI assistant, which may run
  /// several model round-trips server-side) wait longer than the normal default.
  Future<Map<String, dynamic>> post(String url, Map<String, dynamic> data, {Duration? receiveTimeout}) async {
    try {
      final response = await _dio.post(
        url,
        data: data,
        options: receiveTimeout != null ? Options(receiveTimeout: receiveTimeout) : null,
      );
      return _handle(response);
    } on DioException catch (e) {
      throw ApiException(_dioErrorMessage(e), statusCode: e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> postMultipart(String url, FormData data) async {
    try {
      final response = await _dio.post(url, data: data);
      return _handle(response);
    } on DioException catch (e) {
      throw ApiException(_dioErrorMessage(e), statusCode: e.response?.statusCode);
    }
  }

  /// Downloads raw bytes (e.g. a report's attached file) with the auth header attached.
  Future<List<int>> getBytes(String url) async {
    try {
      final response = await _dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
      if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
        return response.data!;
      }
      throw ApiException('Could not download that file.');
    } on DioException catch (e) {
      throw ApiException(_dioErrorMessage(e), statusCode: e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> get(String url) async {
    try {
      final response = await _dio.get(url);
      return _handle(response);
    } on DioException catch (e) {
      throw ApiException(_dioErrorMessage(e), statusCode: e.response?.statusCode);
    }
  }

  Future<List<dynamic>> getList(String url) async {
    try {
      final response = await _dio.get(url);
      if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
        return response.data as List<dynamic>;
      }
      throw ApiException('Something went wrong. Please try again.');
    } on DioException catch (e) {
      throw ApiException(_dioErrorMessage(e), statusCode: e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> put(String url, Map<String, dynamic> data) async {
    try {
      final response = await _dio.put(url, data: data);
      return _handle(response);
    } on DioException catch (e) {
      throw ApiException(_dioErrorMessage(e), statusCode: e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> delete(String url) async {
    try {
      final response = await _dio.delete(url);
      return _handle(response);
    } on DioException catch (e) {
      throw ApiException(_dioErrorMessage(e), statusCode: e.response?.statusCode);
    }
  }

  Map<String, dynamic> _handle(Response response) {
    final data = response.data;
    if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
      if (data is Map<String, dynamic>) return data;
      return {'data': data};
    }

    String message = 'Something went wrong. Please try again.';
    String? code;
    if (data is Map<String, dynamic>) {
      if (data['message'] is String) message = data['message'] as String;
      if (data['code'] is String) code = data['code'] as String;
    }
    throw ApiException(message, statusCode: response.statusCode, code: code);
  }

  String _dioErrorMessage(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'Could not reach the server. Check your internet connection and try again.';
    }
    return 'Something went wrong. Please try again.';
  }
}
