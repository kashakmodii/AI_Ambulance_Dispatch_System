import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class BookOnCallScreen extends StatelessWidget {
  const BookOnCallScreen({super.key, this.emergencyNumber = '108'});

  final String emergencyNumber;

  Future<void> _dial(String number, BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: number);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open dialer for $number')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      ('Ambulance', emergencyNumber, Icons.local_hospital),
      ('Police', '100', Icons.local_police),
      ('Fire', '101', Icons.local_fire_department),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Book on Call'),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.info, size: 32, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Tap a service to place a call via your phone\'s dialer.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: cards.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final (title, number, icon) = cards[i];
                  return ListTile(
                    tileColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: CircleAvatar(
                      child: Icon(icon),
                    ),
                    title: Text(title),
                    subtitle: Text(number),
                    trailing: FilledButton.icon(
                      onPressed: () => _dial(number, context),
                      icon: const Icon(Icons.call),
                      label: const Text('Call'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
