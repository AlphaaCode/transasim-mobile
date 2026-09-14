/// The single network layer. ARCHITECTURE-MOBILE.md §10.1.
///
/// No module ever calls dio or http directly — rule L4, enforced by
/// `tool/check_layers.dart`. The base URL comes from [BrandConfig], so a client
/// talks to its own backend and nothing else (§10.3).
///
/// Three things the old app did that are deliberately not done here:
///  - it printed every response body, and part of the Stripe client secret, in
///    release builds (`ANALYSE-EXISTANT.md` §7.8);
///  - it never sent `Accept-Language`, so every server-side message came back
///    in the backend's default language while the app served seven (§8.2);
///  - it treated any 2xx as success and any failure as a raw exception string
///    reaching a dialog.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../perf/perf_log.dart';
import '../result/result.dart';

/// Supplies the bearer token, or null when signed out.
///
/// A function rather than a session object so `core/network` does not depend on
/// `core/session`: the account module lands later and this contract does not
/// have to change when it does.
typedef TokenSource = String? Function();

class ApiClient {
  final Dio _dio;
  final TokenSource _token;

  ApiClient({
    required String baseUrl,
    required TokenSource token,
    required String Function() language,
    Dio? dio,
  })  : _token = token,
        _dio = dio ?? Dio() {
    // ignore: prefer_initializing_formals
    _dio.options = _dio.options.copyWith(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      // Never throw on status: every response is turned into a typed Result.
      validateStatus: (_) => true,
      headers: <String, String>{'Content-Type': 'application/json'},
    );
    // Only where it logs. An injected test dio keeps its own transformer.
    if (!kReleaseMode && dio == null) _dio.transformer = _TimingTransformer();

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // `auth: false` means false. An expired token sent to a public route
          // comes back 401, which the mapping below reads as SessionExpired —
          // so a stale token would sign the user out of the catalogue, and
          // would fail the very sign-in meant to replace it.
          final t = options.extra['auth'] == false ? null : _token();
          if (t != null && t.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $t';
          }
          // The old app served eight locales and never asked the server for one.
          options.headers['Accept-Language'] = language();
          options.extra['perf.start'] = perfNow;
          handler.next(options);
        },
      ),
    );
  }

  /// GET returning a decoded JSON value.
  ///
  /// [auth] is explicit at every call site rather than implied by five different
  /// pre-configured client instances, which is how the old app ended up sending
  /// no token on endpoints that needed one.
  Future<Result<T>> get<T>(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
  }) =>
      _send<T>(() => _dio.get<dynamic>(
            path,
            queryParameters: query,
            options: Options(extra: {'auth': auth}),
          ));

  Future<Result<T>> post<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
  }) =>
      _send<T>(() => _dio.post<dynamic>(
            path,
            data: body,
            queryParameters: query,
            options: Options(extra: {'auth': auth}),
          ));

  Future<Result<T>> put<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
  }) =>
      _send<T>(() => _dio.put<dynamic>(
            path,
            data: body,
            queryParameters: query,
            options: Options(extra: {'auth': auth}),
          ));

  Future<Result<T>> _send<T>(Future<Response<dynamic>> Function() call) async {
    late final Response<dynamic> response;
    try {
      response = await call();
    } on DioException catch (e) {
      return Err<T>(NetworkUnavailable(e.type.name));
    } catch (e) {
      return Err<T>(NetworkUnavailable(e.runtimeType.toString()));
    }

    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      return Err<T>(_httpFailure(status, response.data));
    }

    final data = response.data;
    if (data is T) return Ok<T>(data);

    // An empty 2xx body is a legitimate success for some endpoints. The old
    // HttpClient coerced it to {'status':'success'}, which is how an empty
    // response became "your voucher is valid".
    if (data == null && null is T) return Ok<T>(null as T);

    return Err<T>(
      ContractViolation('expected $T but the server sent ${data.runtimeType}'),
    );
  }

  AppError _httpFailure(int status, dynamic body) {
    if (status == 401) return const SessionExpired();
    String? code;
    String? message;
    if (body is Map) {
      // JHipster sends `message` (often an error key like `error.idexists`)
      // and/or `detail`/`title`.
      code = body['message']?.toString();
      message = (body['detail'] ?? body['title'] ?? body['error'])?.toString();
    }
    return HttpFailure(status, serverCode: code, serverMessage: message);
  }
}

/// Splits a response's time into its stages without changing what is decoded:
/// the body is read in full (download), then handed to dio's own transformer
/// (decode). The request's start comes from the interceptor above, so
/// headers-arrived minus start is the wait on the server plus the connection.
class _TimingTransformer extends BackgroundTransformer {
  @override
  Future<dynamic> transformResponse(RequestOptions options, ResponseBody body) async {
    if (options.responseType == ResponseType.stream) {
      return super.transformResponse(options, body);
    }
    final start = options.extra['perf.start'] as int? ?? perfNow;
    final headersAt = perfNow;
    final chunks = <int>[];
    await for (final chunk in body.stream) {
      chunks.addAll(chunk);
    }
    final downloadedAt = perfNow;
    final result = await super.transformResponse(
      options,
      ResponseBody.fromBytes(
        chunks,
        body.statusCode,
        statusMessage: body.statusMessage,
        isRedirect: body.isRedirect,
        headers: body.headers,
      ),
    );
    perfLog('http ${options.method} ${options.path} ${body.statusCode}'
        ' wait=${headersAt - start}ms'
        ' download=${downloadedAt - headersAt}ms'
        ' decode=${perfNow - downloadedAt}ms'
        ' ${(chunks.length / 1024).toStringAsFixed(1)}KB');
    return result;
  }
}
