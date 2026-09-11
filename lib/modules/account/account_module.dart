import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand/brand_config.dart';
import '../../core/modules/app_module.dart';
import 'presentation/auth_screens.dart';
import 'presentation/profile_screen.dart';

/// Sign-in, registration, verification, password reset and profile.
///
/// Always active, and no `features.account` flag: nothing would read it.
class AccountModule extends AppModule {
  const AccountModule();

  @override
  String get id => 'account';

  @override
  bool isEnabled(BrandConfig config) => true;

  @override
  List<RouteBase> routes(BrandConfig config) => <RouteBase>[
        // The only tabbed route; everything else is task-focused and sits
        // outside the shell, as the designs show.
        GoRoute(
          path: '/profile',
          name: 'profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/welcome',
          name: 'welcome',
          builder: (context, state) => const WelcomeScreen(),
        ),
        GoRoute(
          path: '/sign-in',
          name: 'signIn',
          builder: (context, state) => const SignInScreen(),
        ),
        GoRoute(
          path: '/register',
          name: 'register',
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/verify',
          name: 'verify',
          builder: (context, state) =>
              VerifyScreen(email: state.uri.queryParameters['email'] ?? ''),
        ),
        GoRoute(
          path: '/forgot-password',
          name: 'forgotPassword',
          builder: (context, state) => const ForgotPasswordScreen(),
        ),
      ];

  @override
  List<NavEntry> navEntries(BrandConfig config) => const <NavEntry>[
        NavEntry(
          moduleId: 'account',
          path: '/profile',
          labelKey: 'nav.profile',
          icon: Icons.person_outline,
        ),
      ];
}
