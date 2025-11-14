import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  Future<void> _open(Uri uri, BuildContext context,
      {bool isCall = false}) async {
    if (isCall && kIsWeb) {
      // Desktop web cannot open native dialer
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Calling is only available on mobile devices')),
      );
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${uri.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'Call Support',
        '1800123456',
        Icons.call,
        Uri(scheme: 'tel', path: '1800123456'),
        true
      ),
      (
        'Email Support',
        'support@aiambulance.app',
        Icons.email,
        Uri(
          scheme: 'mailto',
          path: 'support@aiambulance.app',
          query:
              'subject=Support%20Request&body=Please%20describe%20your%20issue',
        ),
        false
      ),
      (
        'WhatsApp',
        '+91 800123456',
        FontAwesomeIcons.whatsapp,
        Uri.parse('https://wa.me/91800123456'),
        false
      ),
      (
        'Privacy Policy',
        'Read our privacy policy',
        Icons.privacy_tip,
        Uri.parse('https://example.com/privacy'),
        false
      ),
      (
        'Terms of Service',
        'View terms & conditions',
        Icons.description,
        Uri.parse('https://example.com/terms'),
        false
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Help'),
        backgroundColor: Colors.red,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Need help? Reach us via call, email or WhatsApp. '
                  'You can also read our Privacy Policy and Terms.',
                ),
              ),
            );
          }

          final (title, subtitle, icon, uri, isCall) = items[i - 1];

          return Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              onTap: () => _open(uri, context, isCall: isCall),
              leading: CircleAvatar(
                backgroundColor: Colors.grey.shade200,
                child: Icon(icon, color: Colors.red),
              ),
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.open_in_new),
            ),
          );
        },
      ),
    );
  }
}
