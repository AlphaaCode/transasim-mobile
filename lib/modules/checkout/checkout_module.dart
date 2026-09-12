import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand/brand_config.dart';
import '../../core/commerce/money.dart';
import '../../core/modules/app_module.dart';
import 'presentation/checkout_screen.dart';
import 'presentation/voucher_screen.dart';

/// The money path. Always active — a store with no way to pay is not a store.
///
/// No nav entry: checkout is reached from a pack, never from a tab. It takes
/// its [PurchaseRequest] as route `extra` rather than re-fetching the pack,
/// which also keeps it from importing the catalogue module (rule L2) — the
/// shared vocabulary lives in `core/commerce`.
class CheckoutModule extends AppModule {
  const CheckoutModule();

  @override
  String get id => 'checkout';

  @override
  bool isEnabled(BrandConfig config) => true;

  @override
  List<RouteBase> routes(BrandConfig config) => <RouteBase>[
        GoRoute(
          path: '/checkout',
          name: 'checkout',
          builder: (context, state) {
            final request = state.extra;
            if (request is! PurchaseRequest) {
              // Reached without a pack — a deep link, or a restored route after
              // the process died. Send the user somewhere real rather than
              // rendering a checkout for nothing.
              return const _NoPurchase();
            }
            return CheckoutScreen(request: request);
          },
        ),
        // Redemption is acquisition without money: the same
        // `/v1/subscriptions/*` resource and the same provisioning outcome, so
        // it lives here rather than in a module of its own.
        GoRoute(
          path: '/voucher',
          name: 'voucher',
          builder: (context, state) => const VoucherScreen(),
        ),
      ];

  @override
  List<NavEntry> navEntries(BrandConfig config) => const <NavEntry>[];
}

class _NoPurchase extends StatelessWidget {
  const _NoPurchase();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: TextButton(
            onPressed: () => context.goNamed('store'),
            child: const Text('Store'),
          ),
        ),
      );
}
