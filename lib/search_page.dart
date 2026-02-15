import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'device_marks.dart';
import 'models.dart';
import 'ble_bridge.dart';
import 'reports_store.dart';

class SearchPage extends StatefulWidget {
  final TrackerDevice device;

  const SearchPage({required this.device, super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

enum ProximityBand { immediate, nearby, close, far, unknown }

class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  TrackerDevice? live;
  StreamSubscription<TrackerDevice>? sub;

  // UI decoupling
  Timer? _uiTimer;
  TrackerDevice? _pending;
  static const int _uiFrameMs = 60;

  // FOUND logic (meters)
  static const double _foundThresholdM = 0.10;
  static const double _foundReleaseM = 0.35;
  static const int _foundHoldMs = 1800;

  int? _foundAtMs;
  bool _hapticFired = false;

  // Display distance meters internally
  double? _displayDistanceM;

  // Direction smoothing (Apple-like)
  double? _dirRssi;
  double _rssiVelocity = 0.0;
  int _lastDirChangeMs = 0;

  static const double _rssiEmaAlpha = 0.18;
  static const double _velocityAlpha = 0.25;
  static const double _deadband = 0.25;
  static const int _directionHoldMs = 400;

  String direction = 'Hold steady';
  IconData arrow = Icons.navigation;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  Timer? _ageTick;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    live = widget.device;

    // Ensure every tracker has a mark; everything starts Unknown by default.
    if (DeviceMarks.get(widget.device.signature) == null) {
      DeviceMarks.set(widget.device.signature, DeviceMark.unknown);
    }

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.06)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_pulseCtrl);

    sub = BleBridge.detections.listen((d) {
      if (d.signature != widget.device.signature) return;
      _pending = d;
    });

    _uiTimer = Timer.periodic(const Duration(milliseconds: _uiFrameMs), (_) {
      if (!mounted || _pending == null) return;
      setState(() {
        _updateState(_pending!);
        live = _pending;
      });
    });

    _ageTick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() => _nowMs = DateTime.now().millisecondsSinceEpoch);
    });
  }

  bool _isFound(TrackerDevice d) {
    final dist = d.distanceUiM;
    if (dist.isNaN) return false;
    return dist >= 0 && dist <= _foundThresholdM;
  }

  String _feetLabel(double meters) {
    final feet = meters * 3.28084;
    return '${feet.toStringAsFixed(feet < 10 ? 1 : 0)} ft';
  }

  String _ageLabel(int lastSeenMs) {
    final s = ((_nowMs - lastSeenMs) / 1000).clamp(0, 999999).toDouble();
    if (s < 60) return "${s.toStringAsFixed(1)}s ago";
    final m = (s / 60).floor();
    final rs = (s - m * 60).floor();
    return "${m}m ${rs}s ago";
  }

  ProximityBand _bandFromRssi(double rssi) {
    if (rssi >= -55) return ProximityBand.immediate;
    if (rssi >= -65) return ProximityBand.nearby;
    if (rssi >= -75) return ProximityBand.close;
    if (rssi >= -85) return ProximityBand.far;
    return ProximityBand.unknown;
  }

  Color _bandColor(ProximityBand band) {
    switch (band) {
      case ProximityBand.immediate:
        return const Color(0xFF2E7D32);
      case ProximityBand.nearby:
        return const Color(0xFF66BB6A);
      case ProximityBand.close:
        return const Color(0xFFF9A825);
      case ProximityBand.far:
        return const Color(0xFFEF6C00);
      case ProximityBand.unknown:
        return Colors.grey.shade500;
    }
  }

  String _bandLabel(ProximityBand band) {
    switch (band) {
      case ProximityBand.immediate:
        return 'Very Close';
      case ProximityBand.nearby:
        return 'Nearby';
      case ProximityBand.close:
        return 'Close';
      case ProximityBand.far:
        return 'Far';
      case ProximityBand.unknown:
        return 'Unknown';
    }
  }

  void _updateState(TrackerDevice d) {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Use SMOOTHED device distance as input (prevents huge spikes)
    final rawDist = d.distanceUiM;

    // Additional tiny UI smoothing (just for display)
    _displayDistanceM ??= rawDist;
    _displayDistanceM = (_displayDistanceM! * 0.90) + (rawDist * 0.10);

    // FOUND logic
    if (_isFound(d)) {
      _foundAtMs ??= now;

      if (!_hapticFired) {
        HapticFeedback.lightImpact();
        _hapticFired = true;
      }

      if (!_pulseCtrl.isAnimating) {
        _pulseCtrl.repeat(reverse: true);
      }

      direction = 'FOUND';
      arrow = Icons.check_rounded;
      return;
    }

    if (_foundAtMs != null) {
      final held = now - _foundAtMs! < _foundHoldMs;
      final stillClose = d.distanceUiM <= _foundReleaseM;

      if (held || stillClose) {
        direction = 'FOUND';
        arrow = Icons.check_rounded;
        return;
      }

      _foundAtMs = null;
      _hapticFired = false;
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }

    // Direction logic (Apple-like smoothing)
    final rawRssi = d.rssi.toDouble();
    _dirRssi ??= rawRssi;

    final prevRssi = _dirRssi!;
    _dirRssi = (_dirRssi! * (1 - _rssiEmaAlpha)) + (rawRssi * _rssiEmaAlpha);

    final delta = _dirRssi! - prevRssi;
    _rssiVelocity =
        (_rssiVelocity * (1 - _velocityAlpha)) + (delta * _velocityAlpha);

    if (_rssiVelocity.abs() < _deadband) {
      direction = 'Hold steady';
      arrow = Icons.navigation;
      return;
    }

    if (now - _lastDirChangeMs < _directionHoldMs) return;

    if (_rssiVelocity > 0) {
      direction = 'Getting closer';
      arrow = Icons.arrow_circle_up_rounded;
      _lastDirChangeMs = now;
    } else {
      direction = 'Moving away';
      arrow = Icons.arrow_circle_down_rounded;
      _lastDirChangeMs = now;
    }
  }

  Future<void> _setMark(TrackerDevice d, DeviceMark mark) async {
    setState(() {
      DeviceMarks.set(d.signature, mark);
    });

    // Create report when marking as Suspect + SHOW POPUP
    if (mark == DeviceMark.suspect) {
      await ReportsStore.createFromDevice(d);

      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Report created for ${d.displayName}',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
              ),
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
    }
  }

  @override
  void dispose() {
    sub?.cancel();
    _uiTimer?.cancel();
    _ageTick?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = live ?? widget.device;

    final band = _bandFromRssi(d.smoothedRssi);
    final color = _bandColor(band);

    // Always treat null as Unknown
    final mark = DeviceMarks.get(d.signature) ?? DeviceMark.unknown;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          d.displayName,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _foundAtMs != null
                  ? _pulseAnim
                  : const AlwaysStoppedAnimation(1.0),
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _foundAtMs != null ? color : null,
                  gradient: _foundAtMs != null
                      ? null
                      : const LinearGradient(
                    colors: [Color(0xFF0996D1), Color(0xFF2084E8)],
                  ),
                ),
                child: Icon(arrow, size: 90, color: Colors.white),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              direction,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _feetLabel(_displayDistanceM ?? d.distanceUiM),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color, width: 1.5),
              ),
              child: Text(
                _bandLabel(band),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              "RSSI: ${d.rssi} dBm • Seen ${_ageLabel(d.lastSeenMs)}",
              style: const TextStyle(fontFamily: 'Inter'),
            ),
            const SizedBox(height: 8),
            Text(
              'MAC: ${d.displayMac}',
              style: const TextStyle(fontFamily: 'Inter'),
            ),
            const SizedBox(height: 18),

            // 3-way pill tab control
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _MarkTabs(
                selected: mark,
                onSelect: (m) => _setMark(d, m),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkTabs extends StatelessWidget {
  final DeviceMark selected;
  final ValueChanged<DeviceMark> onSelect;

  const _MarkTabs({required this.selected, required this.onSelect});

  static const Color _friendly = Color(0xFF2E7D32);
  static const Color _suspect = Color(0xFFD9534F); // softer red
  static const Color _unknown = Color(0xFF7A7A7A); // gray

  @override
  Widget build(BuildContext context) {
    final bg = Colors.grey.shade100;

    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Pill(
              label: 'Unknown',
              color: _unknown,
              selected: selected == DeviceMark.unknown,
              onTap: () => onSelect(DeviceMark.unknown),
            ),
          ),
          Expanded(
            child: _Pill(
              label: 'Friendly',
              color: _friendly,
              selected: selected == DeviceMark.friendly,
              onTap: () => onSelect(DeviceMark.friendly),
            ),
          ),
          Expanded(
            child: _Pill(
              label: 'Suspect',
              color: _suspect,
              selected: selected == DeviceMark.suspect,
              onTap: () => onSelect(DeviceMark.suspect),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? Colors.grey.shade300 : Colors.transparent,
          width: 1,
        ),
        boxShadow: selected
            ? [
          BoxShadow(
            blurRadius: 10,
            offset: const Offset(0, 3),
            color: Colors.black.withOpacity(0.06),
          ),
        ]
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.signal_cellular_alt_rounded,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                fontSize: 14,
                color: selected ? Colors.black : Colors.grey.shade700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
