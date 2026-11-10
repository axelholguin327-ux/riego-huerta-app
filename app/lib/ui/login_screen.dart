import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _hide = true, _busy = false;
  String? _error;

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).login(_email.text.trim(), _pass.text);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        // Encabezado verde de alto fijo detrás del logo y el título.
        Container(height: 300, color: AppColors.verde),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpace.s5, 48, AppSpace.s5, AppSpace.s5),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
                    child: const Icon(Icons.water_drop_rounded, size: 40, color: AppColors.rojo),
                  ),
                  const SizedBox(height: 14),
                  const Text('Huerta Manzanos',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)),
                  const Text('Monitoreo y control de riego', style: TextStyle(color: Color(0xE6FFFFFF))),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.s5),
                      child: Form(
                        key: _form,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const Text('Iniciar sesión', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: AppSpace.s1),
                          const Text('Usa tu usuario de ThingsBoard',
                              style: TextStyle(fontSize: 13, color: AppColors.texto2)),
                          const SizedBox(height: AppSpace.s4),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                                labelText: 'Correo electrónico', prefixIcon: Icon(Icons.mail_outline_rounded)),
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return 'Escribe tu correo';
                              if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(t)) return 'El correo no es válido';
                              return null;
                            },
                          ),
                          const SizedBox(height: AppSpace.s3),
                          TextFormField(
                            controller: _pass,
                            obscureText: _hide,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => _login(),
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                tooltip: _hide ? 'Mostrar' : 'Ocultar',
                                icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                                onPressed: () => setState(() => _hide = !_hide),
                              ),
                            ),
                            validator: (v) => (v ?? '').isEmpty ? 'Escribe tu contraseña' : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: AppSpace.s3),
                            Text(_error!, style: const TextStyle(color: AppColors.rojo, fontSize: 13)),
                          ],
                          const SizedBox(height: AppSpace.s4),
                          FilledButton(
                            onPressed: _busy ? null : _login,
                            child: _busy
                                ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                    SizedBox(width: 10),
                                    Text('Validando…'),
                                  ])
                                : const Text('Entrar'),
                          ),
                          const SizedBox(height: AppSpace.s2),
                          TextButton.icon(
                            onPressed: _busy ? null : () => ref.read(authProvider.notifier).demo(),
                            icon: const Icon(Icons.science_outlined),
                            label: const Text('Entrar en modo demo (sin el nodo)'),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
