import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../module/auth/auth_service.dart';
import '../module/persona/persona_service.dart';
import '../theme/app_colors.dart';

/// Shown on the **APK** to a member the Super Admin has converted to an agent
/// or an investor. Their work now lives in the web console, so the app stops
/// here and hands them the link rather than opening the customer shell.
///
/// The web build never shows this — there, a converted member gets the full
/// app with their agent / investor card on the home screen.
class WebAccessScreen extends StatelessWidget {
  const WebAccessScreen({super.key});

  /// Where a converted member goes. Overridable at build time with
  /// `--dart-define=WEB_CONSOLE_URL=…`.
  static const String consoleUrl = String.fromEnvironment(
    'WEB_CONSOLE_URL',
    defaultValue: 'https://shield-webapp-xq85.vercel.app',
  );

  @override
  Widget build(BuildContext context) {
    final persona = PersonaService.instance;
    final roleWord = persona.isAgent ? 'Agent' : 'Investor';
    final name = AuthService.instance.currentUser.value?.name.trim() ?? '';

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.desktop_windows_rounded,
                      size: 30,
                      color: AppColors.brandBlue,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    name.isEmpty
                        ? "You're now a SHIELD $roleWord"
                        : "$name, you're now a SHIELD $roleWord",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'The $roleWord portal runs in the SHIELD web console. '
                    'Open it in a browser to manage everything — this app is '
                    'for customers.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _UrlBox(url: consoleUrl),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => Clipboard.setData(
                      const ClipboardData(text: consoleUrl),
                    ).then((_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            const SnackBar(content: Text('Link copied')),
                          );
                      }
                    }),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy link'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => AuthService.instance.logOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UrlBox extends StatelessWidget {
  final String url;

  const _UrlBox({required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.pageTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: SelectableText(
        url,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.brandBlue,
        ),
      ),
    );
  }
}
