/// Voucher redemption state. Widget -> controller -> repository.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_providers.dart';
import '../../../core/session/session.dart';
import '../data/voucher_repository_impl.dart';
import '../domain/voucher.dart';

final voucherRepositoryProvider = Provider<VoucherRepository>(
  (ref) => VoucherRepositoryImpl(ref.watch(apiClientProvider)),
);

sealed class VoucherState {
  const VoucherState();
}

final class VoucherIdle extends VoucherState {
  const VoucherIdle();
}

final class VoucherChecking extends VoucherState {
  const VoucherChecking();
}

final class VoucherSucceeded extends VoucherState {
  final String? packName;
  const VoucherSucceeded(this.packName);
}

final class VoucherFailed extends VoucherState {
  /// A dictionary key, never a server string.
  final String messageKey;
  const VoucherFailed(this.messageKey);
}

class VoucherController extends Notifier<VoucherState> {
  @override
  VoucherState build() => const VoucherIdle();

  Future<void> redeem(String token) async {
    if (state is VoucherChecking) return;

    // Redemption provisions an eSIM against an account. Signing in first is
    // not a policy choice here — the endpoint is authenticated.
    if (!ref.read(isSignedInProvider)) {
      state = const VoucherFailed('voucher.error.signInFirst');
      return;
    }

    state = const VoucherChecking();
    final result = await ref.read(voucherRepositoryProvider).redeem(token);

    // The VERDICT decides, not the status code — see VoucherResult.
    state = switch (result) {
      VoucherAccepted(:final packName) => VoucherSucceeded(packName),
      VoucherRejected(:final messageKey) => VoucherFailed(messageKey),
    };
  }

  void reset() => state = const VoucherIdle();
}

final voucherControllerProvider =
    NotifierProvider<VoucherController, VoucherState>(VoucherController.new);
