import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'ble_bridge.dart';
import 'models.dart';
import 'distance_page.dart';
import 'identification_page.dart';
import 'device_marks.dart';

import 'app_drawer.dart';
import 'filters.dart';
import 'reports_store.dart';

void main() {
  runApp(const LeoTrackerApp());
}

class LeoTrackerApp extends StatefulWidget {
  const LeoTrackerApp({super.key});

  @override
  State<LeoTrackerApp> createState() => _LeoTrackerAppState();
}

class _LeoTrackerAppState extends State<LeoTrackerApp>
    with SingleTickerProviderStateMixin {
  final Map<String, TrackerDevice> _devicesBySig = {};

  bool scanning = false;
  int pageIndex = 0;
  DateTime? lastScanTime;
  DateTime? scanStartTime;

  StreamSubscription<TrackerDevice>? _bleSub;
  StreamSubscription<AccelerometerEvent>? _motionSub;

  double _lastMag = 0;
  final double _movementThreshold = 1.2;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // Stable-ish display order to reduce jumping
  List<String> _displayOrder = [];
  Timer? _orderTimer;

  @override
  void initState() {
    super.initState();

    // Load saved reports (safe if file doesn't exist yet)
    ReportsStore.init();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _fadeAnim = CurvedAnimation(
      parent: _fadeCtrl,
      curve: Curves.easeOut,
    );

    _fadeCtrl.forward();

    _bleSub = BleBridge.detections.listen((device) {
      setState(() {
        final prev = _devicesBySig[device.signature];
        _devicesBySig[device.signature] =
        prev == null ? device : prev.merge(device);

        // If new device, push it to the top of the display order.
        if (prev == null) {
          // New trackers start as Unknown so Identify can organize them.
          if (DeviceMarks.get(device.signature) == null) {
            DeviceMarks.set(device.signature, DeviceMark.unknown);
          }

          _displayOrder = [
            device.signature,
            ..._displayOrder.where((s) => s != device.signature),
          ];
        }
      });
    });

    // Resort at a slow cadence only (prevents UI from constantly jumping)
    _orderTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (!mounted) return;

      // Only maintain recent ordering when that's the selected mode
      if (FiltersModel.state.sortMode != SortMode.recent) return;

      setState(() {
        _rebuildRecentOrder();
      });
    });
  }

  void _rebuildRecentOrder() {
    if (_devicesBySig.isEmpty) {
      _displayOrder = [];
      return;
    }

    final sigs = _devicesBySig.keys.toList();

    sigs.sort((a, b) {
      final da = _devicesBySig[a]!;
      final db = _devicesBySig[b]!;
      final c = db.lastSeenMs.compareTo(da.lastSeenMs); // recent first
      if (c != 0) return c;

      // tie-breaker: preserve existing order if possible
      final ia = _displayOrder.indexOf(a);
      final ib = _displayOrder.indexOf(b);
      if (ia == -1 && ib == -1) return 0;
      if (ia == -1) return 1;
      if (ib == -1) return -1;
      return ia.compareTo(ib);
    });

    _displayOrder = sigs;
  }

  // Devices list depends on filter sort mode.
  List<TrackerDevice> get devices {
    final mode = FiltersModel.state.sortMode;

    if (mode == SortMode.distanceAsc) {
      final list = _devicesBySig.values.toList()
        ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
      return list;
    }

    // default = recent ordering (stable-ish)
    if (_displayOrder.isEmpty) _rebuildRecentOrder();

    return _displayOrder
        .where(_devicesBySig.containsKey)
        .map((sig) => _devicesBySig[sig]!)
        .toList();
  }

  Future<void> toggleScan() async {
    if (scanning) {
      await BleBridge.stopScan();
      await _motionSub?.cancel();
      _motionSub = null;

      setState(() {
        scanning = false;
        lastScanTime = DateTime.now();
        scanStartTime = null;
      });
    } else {
      await BleBridge.startScan();
      _startMotionDetection();

      setState(() {
        scanning = true;
        scanStartTime = DateTime.now();
      });
    }
  }

  void _startMotionDetection() {
    _motionSub = accelerometerEventStream().listen((event) {
      if (!scanning) return;

      final magnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );

      final delta = (magnitude - _lastMag).abs();
      _lastMag = magnitude;

      if (delta > _movementThreshold) {
        // BLE scan already running continuously
      }
    });
  }

  @override
  void dispose() {
    _orderTimer?.cancel();
    _fadeCtrl.dispose();
    _motionSub?.cancel();
    _bleSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trackedDevices = devices
        .where((d) => d.isLikelyAirTag || d.isLikelyTile || d.isLikelySamsung)
        .toList();

    final pages = [
      DistancePage(
        devices: trackedDevices,
        scanning: scanning,
        onRescan: toggleScan,
        lastScanTime: lastScanTime,
        scanStartTime: scanStartTime,
      ),
      IdentificationPage(devices: trackedDevices),
    ];

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FadeTransition(
        opacity: _fadeAnim,
        child: Scaffold(
          drawer: const AppDrawer(),
          appBar: AppBar(
            centerTitle: true,
            title: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/leo_splash.png',
                      height: 20,
                      width: 20,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'LEOFindIt',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: pages[pageIndex],
          bottomNavigationBar: SizedBox(
            height: 71,
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: pageIndex,
              selectedItemColor: Colors.blueAccent,
              unselectedItemColor: Colors.grey,
              selectedFontSize: 16,
              unselectedFontSize: 12,
              iconSize: 28,
              onTap: (i) => setState(() => pageIndex = i),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.radar),
                  label: 'Scan',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.list_alt),
                  label: 'Identify',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
