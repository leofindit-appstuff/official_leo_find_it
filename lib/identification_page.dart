import 'package:flutter/material.dart';
import 'models.dart';
import 'device_marks.dart';
import 'search_page.dart';

// This is the page labeled 'identify' in the app...

class IdentificationPage extends StatelessWidget {
  final List<TrackerDevice> devices;

  const IdentificationPage({required this.devices, super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: DeviceMarks.version,
      builder: (_, __, ___) {
        // De-dupe by signature (latest snapshot wins)
        final Map<String, TrackerDevice> unique = {};
        for (final d in devices) {
          unique[d.signature] = d;
        }

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final qualified = unique.values.where((d) {
          if (d.distance <= 0) return false;
          if (nowMs - d.lastSeenMs > 30 * 1000) return false;
          return true;
        }).toList();

        final friendly = <TrackerDevice>[];
        final unknown = <TrackerDevice>[];
        final suspect = <TrackerDevice>[];

        for (final d in qualified) {
          final mark = DeviceMarks.get(d.signature) ?? DeviceMark.unknown;
          if (mark == DeviceMark.friendly) {
            friendly.add(d);
          } else if (mark == DeviceMark.suspect) {
            suspect.add(d);
          } else {
            unknown.add(d);
          }
        }

        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: _MarkTabs(),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _list(context, unknown, empty: 'No unknown trackers yet'),
                    _list(context, friendly, empty: 'No friendly trackers yet'),
                    _list(context, suspect, empty: 'No suspect trackers yet'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _list(BuildContext context, List<TrackerDevice> list,
      {required String empty}) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          empty,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 14),
      itemCount: list.length,
      itemBuilder: (_, i) => _deviceCard(context, list[i]),
    );
  }

  int _bars(int rssi) {
    if (rssi >= -55) return 5;
    if (rssi >= -65) return 4;
    if (rssi >= -75) return 3;
    if (rssi >= -85) return 2;
    return 1;
  }

  String _ageLabel(int lastSeenMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final s = ((now - lastSeenMs) / 1000).clamp(0, 999999).toDouble();
    if (s < 60) return "${s.toStringAsFixed(1)}s ago";
    final m = (s / 60).floor();
    final rs = (s - m * 60).floor();
    return "${m}m ${rs}s ago";
  }

  Widget _deviceCard(BuildContext context, TrackerDevice d) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SearchPage(device: d)),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(
                Icons.signal_cellular_alt_rounded,
                size: 44,
                color: _markColor(DeviceMarks.get(d.signature)),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.displayName,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Distance: ${d.distanceFt.toStringAsFixed(1)} ft',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Text(
                      'RSSI: ${d.rssi} dBm • Seen ${_ageLabel(d.lastSeenMs)}',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: List.generate(
                        5,
                            (i) => Icon(
                          Icons.signal_cellular_alt,
                          size: 18,
                          color: i < _bars(d.smoothedRssi.round())
                              ? Colors.green
                              : Colors.grey.shade300,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkTabs extends StatelessWidget {
  const _MarkTabs();

  static const _friendly = Color(0xFF2E7D32);
  static const _suspect = Color(0xFFD9534F);
  static const _unknown = Color(0xFF7A7A7A);

  @override
  Widget build(BuildContext context) {
    final bg = Colors.grey.shade100;

    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: TabBar(
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.grey.shade300, width: 1),
          boxShadow: [
            BoxShadow(
              blurRadius: 10,
              offset: const Offset(0, 3),
              color: Colors.black.withOpacity(0.06),
            ),
          ],
        ),
        labelPadding: EdgeInsets.zero,
        labelColor: Colors.black,
        unselectedLabelColor: Colors.grey.shade700,
        labelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 14,
          letterSpacing: 0.2,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        tabs: const [
          _TabPill(label: 'Unknown', color: _unknown),
          _TabPill(label: 'Friendly', color: _friendly),
          _TabPill(label: 'Suspect', color: _suspect),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final Color color;

  const _TabPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.signal_cellular_alt_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

Color _markColor(DeviceMark? mark) {
  switch (mark ?? DeviceMark.unknown) {
    case DeviceMark.friendly:
      return const Color(0xFF2E7D32);
    case DeviceMark.suspect:
      return const Color(0xFFD9534F);
    case DeviceMark.unknown:
      return const Color(0xFF7A7A7A);
  }
}


// Using google icons for icons here:
// https://fonts.google.com/icons?selected=Material+Symbols+Outlined:stacks:FILL@0;wght@400;GRAD@0;opsz@24&icon.size=24&icon.color=%23e3e3e3