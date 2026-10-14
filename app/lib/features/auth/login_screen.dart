import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform_info.dart';
import '../../core/theme.dart';
import '../../data/api/api_client.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // On the web the UI is served by the API itself: always talk to this origin.
    if (PlatformInfo.isWeb) {
      _server.text = Uri.base.origin;
    } else {
      ref.read(authRepositoryProvider).serverUrl.then((v) {
        if (mounted && v.isNotEmpty) _server.text = v;
      });
    }
  }

  @override
  void dispose() {
    _server.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = L10n.of(context);
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = ref.read(sessionProvider.notifier);
      if (_register) {
        await session.register(
          _server.text,
          _email.text.trim(),
          _password.text,
        );
      } else {
        await session.login(_server.text, _email.text.trim(), _password.text);
      }
    } on ApiException catch (e) {
      setState(() => _error = l.authFailed(e.message));
    } on NetworkException {
      setState(() => _error = l.networkError);
    } catch (e) {
      setState(() => _error = l.authFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _editServer = false;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = context.tokens;
    final host = Uri.tryParse(_server.text)?.host ?? '';
    final showServerField = !PlatformInfo.isWeb && (_editServer || _server.text.trim().isEmpty);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: CustomScrollView(slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const SizedBox(height: Space.huge + Space.lg),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: t.accent5,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [BoxShadow(color: t.accent.withValues(alpha: .12), blurRadius: 32, spreadRadius: 4)],
                            ),
                            child: Icon(Icons.calendar_today_rounded, color: t.accent, size: 32),
                          ),
                        ),
                        const SizedBox(height: Space.xl),
                        Text(_register ? l.createAccount : l.welcomeBack, style: context.text.headlineSmall),
                        const SizedBox(height: Space.sm),
                        Text(_register ? l.registerSubtitle : l.loginSubtitle, style: context.text.bodyMedium),
                        const SizedBox(height: Space.huge),
                        if (showServerField) ...[
                          TextFormField(
                            controller: _server,
                            decoration: InputDecoration(hintText: l.serverUrlHint, prefixIcon: const Icon(Icons.dns_outlined)),
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            onChanged: (_) => setState(() {}),
                            validator: (v) => (v == null || v.trim().isEmpty) ? l.serverUrlHint : null,
                          ),
                          const SizedBox(height: Space.md),
                        ],
                        TextFormField(
                          controller: _email,
                          decoration: InputDecoration(hintText: l.email, prefixIcon: const Icon(Icons.mail_outline_rounded)),
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          validator: (v) => (v == null || !v.contains('@')) ? l.invalidEmail : null,
                        ),
                        const SizedBox(height: Space.md),
                        TextFormField(
                          controller: _password,
                          decoration: InputDecoration(hintText: l.password, prefixIcon: const Icon(Icons.lock_outline_rounded)),
                          obscureText: true,
                          autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) => (v == null || v.length < 8) ? l.passwordTooShort : null,
                        ),
                        if (!PlatformInfo.isWeb && !showServerField) ...[
                          const SizedBox(height: Space.md),
                          Padding(
                            padding: const EdgeInsets.only(left: Space.xs),
                            child: Text.rich(
                              TextSpan(text: '${l.serverLine(host)} · ', children: [
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.baseline,
                                  baseline: TextBaseline.alphabetic,
                                  child: GestureDetector(
                                    onTap: () => setState(() => _editServer = true),
                                    child: Text(l.change, style: context.text.labelMedium?.copyWith(color: t.accent)),
                                  ),
                                ),
                              ]),
                              style: context.text.bodySmall,
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: Space.lg),
                          Text(_error!, style: context.text.bodySmall?.copyWith(color: t.danger)),
                        ],
                        const Spacer(),
                        const SizedBox(height: Space.xl),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(_register ? l.register : l.login),
                        ),
                        const SizedBox(height: Space.sm),
                        TextButton(
                          onPressed: _busy ? null : () => setState(() => _register = !_register),
                          child: Text(_register ? l.haveAccount : l.createAccount),
                        ),
                        const SizedBox(height: Space.xl),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
