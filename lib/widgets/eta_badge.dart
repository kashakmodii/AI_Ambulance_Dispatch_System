import 'package:flutter/material.dart';

class ETAbadge extends StatelessWidget {
  final int minutes;
  const ETAbadge({required this.minutes});

  @override
  Widget build(BuildContext context) {
    final text = (minutes < 0) ? '—' : '$minutes min';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('ETA', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 4),
          Text(text, style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
