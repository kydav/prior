import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prior/core/lookup_counter.dart';
import 'package:prior/core/purchases_service.dart';
import 'package:prior/features/paywall/paywall_sheet.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          // ── Account header ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary.withAlpha(40),
                  child: Icon(
                    Icons.person,
                    size: 36,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(email, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Account actions ─────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change password'),
            subtitle: const Text('Send a reset link to your email'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _sendPasswordReset(context, email),
          ),
          const SizedBox(height: 10),
          _SubscriptionTile(),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => _signOut(context),
          ),

          const SizedBox(height: 32),

          // ── Danger zone ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Danger zone',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.grey,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(
              Icons.delete_forever_outlined,
              color: Colors.red,
            ),
            title: const Text(
              'Delete account',
              style: TextStyle(color: Colors.red),
            ),
            subtitle: const Text('Permanently delete your account and data'),
            onTap: () => _confirmDeleteAccount(context, email),
          ),
        ],
      ),
    );
  }

  Future<void> _sendPasswordReset(BuildContext context, String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reset link sent to $email')));
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Could not send reset email')),
      );
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    context.go('/login');
    // Router redirect handles navigation to /login
  }

  Future<void> _confirmDeleteAccount(BuildContext context, String email) async {
    final passCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes your account and all saved data. '
              'Enter your password to confirm.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passCtrl,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (_) => Navigator.pop(context, true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final password = passCtrl.text;
    passCtrl.dispose();

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final cred = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(cred);
      await user.delete();
      // Router redirect handles navigation to /login
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'wrong-password' || e.code == 'invalid-credential'
                ? 'Incorrect password.'
                : (e.message ?? 'Could not delete account'),
          ),
        ),
      );
    }
  }
}

class _SubscriptionTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder(
      future: ref.watch(isSubscribedProvider.future),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          final isPro = snapshot.data ?? false;
          if (isPro) {
            return Container(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.verified_outlined, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Prior Pro',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Active subscription',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.check_circle, color: cs.primary),
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, color: cs.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Free plan',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${LookupCounter.freeLimit} lookups included',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                child: FilledButton.icon(
                  onPressed: () => showPaywallSheet(context),
                  icon: const Icon(Icons.star_outline),
                  label: const Text('Upgrade to Prior Pro'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          );
        }
      },
    );
  }
}
