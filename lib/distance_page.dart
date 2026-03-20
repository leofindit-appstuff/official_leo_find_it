import 'dart:async';
import 'package:flutter/material.dart';
import 'models.dart';
import 'search_page.dart';
import 'device_marks.dart';
import 'filters.dart';

// In the app this is labeled the Scan page, it is the first page the app opens to...

class DistancePage extends StatefulWidget {
  final List<TrackerDevice> devices;
  final bool scanning;
  final VoidCallback onRescan;
  final DateTime? lastScanTime;
  final DateTime? scanStartTime;

  final GlobalKey? scanButtonKey;
  final GlobalKey? trackerListKey;
  final GlobalKey? firstTrackerCardKey;

  final bool tutorialMode;
  final TrackerDevice? tutorialDevice;

  const DistancePage({
    super.key,
    required this.devices,
    required this.scanning,
    required this.onRescan,
    required this.lastScanTime,
    required this.scanStartTime,
    this.scanButtonKey,
    this.trackerListKey,
    this.firstTrackerCardKey,
    this.tutorialMode = false,
    this.tutorialDevice,
  });

  @override
  State<DistancePage> createState() => _DistancePageState();
}

class _DistancePageState extends State<DistancePage> {
  Timer? _tick;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() => _nowMs = DateTime.now().millisecondsSinceEpoch);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _formatTime(DateTime? t) {
    if (t == null) return '';
    int hour = t.hour % 12;
    if (hour == 0) hour = 12;
    final min = t.minute.toString().padLeft(2, '0');
    final am = t.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$min $am';
  }

  String _ageLabel(int lastSeenMs) {
    final s = ((_nowMs - lastSeenMs) / 1000).clamp(0, 999999).toDouble();
    if (s < 60) return "${s.toStringAsFixed(1)}s ago";
    final m = (s / 60).floor();
    final rs = (s - m * 60).floor();
    return "${m}m ${rs}s ago";
  }

  String _scanElapsed() {
    final st = widget.scanStartTime;
    if (!widget.scanning || st == null) return "";
    final sec =
    ((_nowMs - st.millisecondsSinceEpoch) / 1000).floor().clamp(0, 999999);
    final mm = (sec ~/ 60).toString().padLeft(2, '0');
    final ss = (sec % 60).toString().padLeft(2, '0');
    return "$mm:$ss";
  }

  int _bars(int rssi) {
    if (rssi >= -55) return 5;
    if (rssi >= -65) return 4;
    if (rssi >= -75) return 3;
    if (rssi >= -85) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: DeviceMarks.version,
      builder: (_, __, ___) {
        return ValueListenableBuilder<FiltersState>(
          valueListenable: FiltersModel.notifier,
          builder: (_, s, ____) {
            final List<TrackerDevice> track;
            if (widget.tutorialMode && widget.tutorialDevice != null) {
              track = [widget.tutorialDevice!];
            } else {
              track = widget.devices
                  .where((d) =>
              d.isLikelyAirTag || d.isLikelyTile || d.isLikelySamsung)
                  .where((d) {
                final mark =
                    DeviceMarks.get(d.signature) ?? DeviceMark.unknown;
                return mark == DeviceMark.unknown;
              }).where((d) {
                if (!s.filterByRssi) return true;
                return d.smoothedRssi >= s.rssiThreshold;
              }).toList();
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                  child: Column(
                    children: [
                      ElevatedButton.icon(
                        key: widget.scanButtonKey,
                        icon: Icon(
                          widget.scanning ? Icons.stop : Icons.play_arrow,
                          size: 28,
                          color: Colors.blueAccent,
                        ),
                        label: Text(
                          widget.scanning ? 'Stop Scan' : 'Start Scan',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            color: Colors.blueAccent,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade50,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 30,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                            side: BorderSide(
                              color: Colors.blueAccent.withOpacity(0.25),
                              width: 1.2,
                            ),
                          ),
                        ),
                        onPressed: widget.onRescan,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.tutorialMode
                            ? 'Tutorial demo tracker'
                            : widget.scanning
                            ? 'Scanning…  ${_scanElapsed()}'
                            : widget.lastScanTime == null
                            ? 'No scans yet'
                            : 'Last scan ${_formatTime(widget.lastScanTime)}',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    key: widget.trackerListKey,
                    child: track.isEmpty
                        ? const Center(
                      child: Text(
                        'No trackers detected',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey,
                        ),
                      ),
                    )
                        : ListView.builder(
                      itemCount: track.length,
                      itemBuilder: (_, i) {
                        final d = track[i];
                        return GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SearchPage(
                                device: d,
                                tutorialMode: widget.tutorialMode,
                              ),
                            ),
                          ),
                          child: Card(
                            key: i == 0 ? widget.firstTrackerCardKey : null,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 13,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.signal_cellular_alt_rounded,
                                    size: 46,
                                    color: Colors.blueAccent,
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          d.displayName,
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 22,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Distance: ${d.distanceFt.toStringAsFixed(1)} ft',
                                        ),
                                        Text(
                                          'RSSI: ${d.rssi} dBm • Seen ${_ageLabel(d.lastSeenMs)}',
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: List.generate(
                                            5,
                                                (i) => Icon(
                                              Icons.signal_cellular_alt,
                                              size: 20,
                                              color: i <
                                                  _bars(d.smoothedRssi
                                                      .round())
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
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
