/// Inputs. The one place the app decides what a field looks like.
///
/// The frames agree on the box and disagree on everything around it — Log In
/// labels in #1e1c09, Sign Up in #3f4948; Log In's placeholder is IBM Plex
/// Sans 14 at #6b7280, Sign Up's is Noto Sans 16 at 60% of the border colour.
/// One resolution for both, taken here: the label is UI chrome, the value and
/// its placeholder are prose at the same size, so nothing jumps family or size
/// when the user starts typing.
///
/// The placeholder deliberately does NOT use Figma's `rgba(191,201,199,0.6)` —
/// that is roughly 1.6:1 on white, which is not readable text. [AppTokens
/// .inkFaint] is the same intent at a contrast a person can actually use.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Label, box, error. Shared by every kind of field so they cannot drift.
class AppFieldShell extends StatelessWidget {
  final String label;

  /// Appended to the label, dimmed — "· optional". The design writes this into
  /// the label text itself ("Phone Number (Optional)"), which a translator
  /// then has to re-derive per language; it is a separate string here.
  final String? note;

  /// Rendered to the right of the label. Log In hangs "Forgot Password?" here.
  final Widget? trailing;

  final Widget child;
  final String? errorText;

  /// Draws the box in the brand's primary when the field has focus.
  final bool focused;

  const AppFieldShell({
    super.key,
    required this.label,
    required this.child,
    this.note,
    this.trailing,
    this.errorText,
    this.focused = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final bad = errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: label,
                  children: note == null
                      ? null
                      : [
                          TextSpan(
                            text: '  $note',
                            style: AppType.label.copyWith(color: t.inkFaint),
                          ),
                        ],
                ),
                style: AppType.label.copyWith(color: t.inkMuted),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: Gap.xs),
        DecoratedBox(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(Radii.chip),
            border: Border.all(
              color: bad
                  ? t.danger
                  : focused
                      ? t.primary
                      : t.fieldBorder,
              width: bad || focused ? 1.5 : 1,
            ),
            boxShadow: Shadows.field,
          ),
          child: SizedBox(height: kAppFieldHeight, child: child),
        ),
        if (bad)
          Padding(
            padding: const EdgeInsets.only(top: Gap.xs, left: Gap.xs),
            child: Text(errorText!, style: AppType.caption.copyWith(color: t.danger)),
          ),
      ],
    );
  }
}

/// 48, from both frames.
const double kAppFieldHeight = 48;

class AppTextField extends StatefulWidget {
  final String label;
  final String? note;
  final String? hint;
  final Widget? labelTrailing;

  /// Drawn inside the box on the leading edge, at the design's 18px inset.
  final IconData? icon;

  final TextEditingController? controller;
  final String? initialValue;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final List<TextInputFormatter> formatters;
  final bool obscure;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final Iterable<String>? autofillHints;

  const AppTextField({
    super.key,
    required this.label,
    this.note,
    this.hint,
    this.labelTrailing,
    this.icon,
    this.controller,
    this.initialValue,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.formatters = const [],
    this.obscure = false,
    this.autofocus = false,
    this.onChanged,
    this.validator,
    this.autofillHints,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final _focus = FocusNode();
  late bool _hidden = widget.obscure;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);

    return FormField<String>(
      initialValue: widget.controller?.text ?? widget.initialValue ?? '',
      validator: widget.validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      builder: (field) => AppFieldShell(
        label: widget.label,
        note: widget.note,
        trailing: widget.labelTrailing,
        errorText: field.errorText,
        focused: _focus.hasFocus,
        child: Row(
          children: [
            if (widget.icon != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: Gap.lg, end: Gap.md),
                child: Icon(widget.icon, size: 18, color: t.inkFaint),
              ),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                obscureText: _hidden,
                keyboardType: widget.keyboardType,
                textInputAction: widget.textInputAction,
                inputFormatters: widget.formatters,
                autofillHints: widget.autofillHints,
                style: AppType.body.copyWith(color: t.ink),
                cursorColor: t.primary,
                onChanged: (v) {
                  field.didChange(v);
                  widget.onChanged?.call(v);
                },
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  contentPadding: EdgeInsetsDirectional.only(
                    start: widget.icon == null ? Gap.lg : 0,
                    end: Gap.lg,
                  ),
                  hintText: widget.hint,
                  hintStyle: AppType.placeholder.copyWith(color: t.inkFaint),
                ),
              ),
            ),
            if (widget.obscure)
              Semantics(
                // Announced rather than left as a bare glyph: a screen-reader
                // user otherwise hears "button" and has to guess.
                label: _hidden ? 'Show password' : 'Hide password',
                child: IconButton(
                  onPressed: () => setState(() => _hidden = !_hidden),
                  icon: Icon(
                    _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 18,
                    color: t.inkFaint,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A field whose value is chosen somewhere else — a date in a calendar, a
/// country in a sheet. One widget for both, because to the user they are the
/// same gesture and to the form they are the same contract.
class AppPickerField<T> extends StatelessWidget {
  final String label;
  final String? note;
  final IconData trailingIcon;

  /// What to show when [value] is null.
  final String placeholder;

  final T? value;

  /// How to render a chosen value.
  final String Function(T value) format;

  /// Opens the picker and returns the choice, or null if dismissed.
  final Future<T?> Function() onPick;

  final ValueChanged<T> onChanged;
  final FormFieldValidator<T>? validator;

  const AppPickerField({
    super.key,
    required this.label,
    required this.placeholder,
    required this.value,
    required this.format,
    required this.onPick,
    required this.onChanged,
    this.note,
    this.validator,
    this.trailingIcon = Icons.expand_more,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);

    return FormField<T>(
      initialValue: value,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      builder: (field) => AppFieldShell(
        label: label,
        note: note,
        errorText: field.errorText,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.chip),
          onTap: () async {
            final picked = await onPick();
            if (picked == null) return;
            field.didChange(picked);
            onChanged(picked);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
            child: Row(
              children: [
                Expanded(
                  child: Builder(builder: (_) {
                    // `field.value`, not the `value` property: after a pick the
                    // FormField holds the answer, and reading the property
                    // instead makes the field render correctly only when the
                    // parent happens to rebuild with a new one. It does in the
                    // registration form, which is why this looked fine.
                    final current = field.value;
                    return Text(
                      current == null ? placeholder : format(current),
                      style: current == null
                          ? AppType.placeholder.copyWith(color: t.inkFaint)
                          : AppType.body.copyWith(color: t.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  }),
                ),
                Icon(trailingIcon, size: 20, color: t.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A search box: the same 48px box as every other field, with no label above
/// it and the icon leading. Its own widget only because a labelled field and a
/// search field are visually different things that must stay the same shape.
class AppSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  const AppSearchField({super.key, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: t.fieldBorder),
        boxShadow: Shadows.field,
      ),
      child: SizedBox(
        height: kAppFieldHeight,
        child: TextField(
          onChanged: onChanged,
          style: AppType.body.copyWith(color: t.ink),
          cursorColor: t.primary,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: Gap.md),
            prefixIcon: Icon(Icons.search, size: 20, color: t.inkMuted),
            hintText: hint,
            hintStyle: AppType.placeholder.copyWith(color: t.inkFaint),
          ),
        ),
      ),
    );
  }
}
