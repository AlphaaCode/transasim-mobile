import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/voucher.dart';

/// `POST /api/v1/subscriptions/voucher`, taking a `SubscriptionModel` whose
/// only populated field is `voucherToken` — the shape read off the deployed
/// `SubscriptionResourceExt`.
class VoucherRepositoryImpl implements VoucherRepository {
  final ApiClient _api;

  VoucherRepositoryImpl(this._api);

  @override
  Future<VoucherResult> redeem(String token) async {
    final result = await _api.post<dynamic>(
      '/v1/subscriptions/voucher',
      body: <String, dynamic>{'voucherToken': token},
    );

    return switch (result) {
      // A 2xx is NECESSARY but not SUFFICIENT. The payload is read first, and
      // only when it carries no verdict at all does the status code decide —
      // which is the case for this build's fixed success body.
      Ok(:final value) => readVoucherVerdict(value) ?? const VoucherAccepted(),

      // A 4xx may still carry a reason worth showing. JHipster puts one in the
      // body, so it is read before falling back to a generic message.
      Err(:final error) => _rejected(error),
    };
  }

  VoucherResult _rejected(AppError error) {
    if (error is HttpFailure) {
      final detail = error.serverMessage;
      if (detail != null) {
        final verdict = readVoucherVerdict(<String, dynamic>{'message': detail});
        if (verdict is VoucherRejected) return verdict;
      }
      return const VoucherRejected('voucher.error.invalid');
    }
    return VoucherRejected('error.${error.code}');
  }
}
