import 'package:flutter/material.dart';
import 'package:prior/data/water_right.dart';
import 'package:url_launcher/url_launcher.dart';

class DetailScreen extends StatelessWidget {
  final List<WaterRight> rights;

  const DetailScreen({super.key, required this.rights});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${rights.length} Water Right${rights.length == 1 ? '' : 's'} Found',
        ),
        ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          itemCount: rights.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => WaterRightCard(right: rights[i]),
        ),
      ],
    );
  }
}

class WaterRightCard extends StatelessWidget {
  final WaterRight right;
  const WaterRightCard({super.key, required this.right});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.water_drop, size: 18, color: Colors.lightBlue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    right.rightNumber.isNotEmpty
                        ? 'Right #${right.rightNumber}'
                        : 'Water Right',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (right.isSenior) _Badge('Senior', Colors.amber),
                if (!right.isActive && right.status != null)
                  _Badge('Inactive', Colors.grey),
              ],
            ),
            const SizedBox(height: 10),
            if (right.source != null) _Row('Source', right.source!),
            if (right.sourceType != null) _Row('Type', right.sourceType!),
            if (right.priorityDate != null)
              _Row('Priority date', right.priorityDate!),
            if (right.volumeAcreFt != null)
              _Row(
                'Volume',
                '${right.volumeAcreFt!.toStringAsFixed(2)} acre-ft/yr',
              ),
            if (right.cfs != null)
              _Row('Flow rate', '${right.cfs!.toStringAsFixed(3)} cfs'),
            if (right.beneficialUse != null) _Row('Use', right.beneficialUse!),
            if (right.status != null) _Row('Status', right.status!),
            if (right.ownerName != null) _Row('Owner', right.ownerName!),
            if (right.plssLocation != null)
              _Row('Location', right.plssLocation!),
            if (right.divisionOfWaterRightsUrl != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_browser, size: 16),
                label: const Text('View DWRi record'),
                onPressed: () {
                  final url = Uri.tryParse(right.divisionOfWaterRightsUrl!);
                  if (url != null) {
                    launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}
