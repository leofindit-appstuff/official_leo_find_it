import 'package:flutter/material.dart';
import 'filters.dart';

class FiltersPage extends StatelessWidget {
  const FiltersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FiltersState>(
      valueListenable: FiltersModel.notifier,
      builder: (_, s, __) {
        return Scaffold(
          appBar: AppBar(title: const Text("Filters")),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const _SectionTitle("Filter"),

              _ToggleCard(
                title: "Filter by RSSI",
                subtitle:
                "Show only devices with RSSI stronger than your threshold.",
                value: s.filterByRssi,
                onChanged: FiltersModel.setFilterByRssi,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: s.filterByRssi
                      ? _RssiSlider(
                    value: s.rssiThreshold,
                    onChanged: FiltersModel.setRssiThreshold,
                  )
                      : const SizedBox.shrink(),
                ),
              ),

              const SizedBox(height: 18),

              const _SectionTitle("Sorting"),

              _ToggleCard(
                title: "Most recently seen",
                subtitle:
                "Default. Keeps new detections near the top without constant jumping.",
                value: s.sortMode == SortMode.recent,
                onChanged: (v) {
                  if (v) FiltersModel.setSortMode(SortMode.recent);
                },
              ),

              const SizedBox(height: 10),

              _ToggleCard(
                title: "By distance",
                subtitle: "Closest → farthest (uses distance estimates).",
                value: s.sortMode == SortMode.distanceAsc,
                onChanged: (v) {
                  if (v) FiltersModel.setSortMode(SortMode.distanceAsc);
                },
              ),

              const SizedBox(height: 18),

              Card(
                elevation: 0,
                color: Colors.grey.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Note: "Suspect" label is only shown when RSSI filter is ON and the device RSSI meets the threshold.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------- UI components ----------

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _ToggleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? child;

  const _ToggleCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: value,
                  onChanged: onChanged,
                ),
              ],
            ),
            if (child != null) ...[
              const SizedBox(height: 10),
              child!,
            ],
          ],
        ),
      ),
    );
  }
}

class _RssiSlider extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _RssiSlider({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "RSSI threshold: $value dBm",
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Slider(
          value: value.toDouble().clamp(-100.0, -30.0),
          min: -100,
          max: -30,
          divisions: 70,
          label: "$value dBm",
          onChanged: (v) => onChanged(v.round()),
        ),
        const SizedBox(height: 6),

        // Clickable drop-down tips
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(left: 2, right: 2, bottom: 6),
            title: Text(
              'Tips',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade800,
              ),
            ),
            children: const [
              _TipBullet(
                text: 'Less negative (e.g., -55) = closer / stronger signal.',
              ),
              SizedBox(height: 6),
              _TipBullet(
                text:
                'You may want to keep the threshold high (more negative) if you suspect a tracker is obstructed by multiple barriers (e.g., in an inaccessible part of a car, hidden in a case, etc.).',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TipBullet extends StatelessWidget {
  final String text;
  const _TipBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 3),
          child: Icon(Icons.circle, size: 6, color: Colors.grey),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }
}

