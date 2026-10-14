import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform_info.dart';
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

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.calendar_month,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.appTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
                    if (!PlatformInfo.isWeb)
                      TextFormField(
                        controller: _server,
                        decoration: InputDecoration(
                          labelText: l.serverUrl,
                          hintText: l.serverUrlHint,
                        ),
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? l.serverUrlHint
                            : null,
                      ),
                    if (!PlatformInfo.isWeb) const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      decoration: InputDecoration(labelText: l.email),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      validator: (v) => (v == null || !v.contains('@'))
                          ? l.invalidEmail
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      decoration: InputDecoration(labelText: l.password),
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) => (v == null || v.length < 8)
                          ? l.passwordTooShort
                          : null,
                    ),
                    const SizedBox(height: 20),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_register ? l.register : l.login),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _register = !_register),
                      child: Text(
                        _register ? l.haveAccountLogin : l.noAccountRegister,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
