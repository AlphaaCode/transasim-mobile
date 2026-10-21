import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// The dev flavor's mark on every screen (Slice H): a red strip across the top
/// saying this build talks to a test server. A DEV build is then never taken
/// for the store app, in a screenshot or in a customer's hands.
///
/// The strip takes the status bar's height and the app below it is laid out as
/// if there were no top inset, so no screen slides under it.
class DevBanner extends StatelessWidget {
  final Widget child;
  const DevBanner({super.key, required this.child});

  static const text = 'TEST SERVER - not for customers';

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        AnnotatedRegion<SystemUiOverlayStyle>(
          value: statusBarOver(kDevBannerColor),
          child: Material(
            color: kDevBannerColor,
            child: Padding(
              padding: EdgeInsets.fromLTRB(Gap.lg, top + Gap.xs, Gap.lg, Gap.xs),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: AppType.labelStrong.copyWith(color: kOnDevBannerColor),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
        ),
      ],
    );
  }
}
