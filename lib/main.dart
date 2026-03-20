import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import 'ble_bridge.dart';
import 'models.dart';
import 'distance_page.dart';
import 'identification_page.dart';
import 'device_marks.dart';

import 'app_drawer.dart';
import 'filters.dart';
import 'reports_store.dart';
import 'search_page.dart';
import 'reports_page.dart';
import 'app_tutorial.dart';

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

  List<String> _displayOrder = [];
  Timer? _orderTimer;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey _scanButtonKey = GlobalKey();
  final GlobalKey _trackerListKey = GlobalKey();
  final GlobalKey _firstTrackerCardKey = GlobalKey();
  final GlobalKey _identifyTabsKey = GlobalKey();
  final GlobalKey _drawerButtonKey = GlobalKey();
  final GlobalKey _drawerFiltersKey = GlobalKey();
  final GlobalKey _drawerReportsKey = GlobalKey();

  BuildContext? _materialContext;

  bool _tutorialRunning = false;

  TrackerDevice get _demoTutorialDevice {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Pseudo tag for tutorial
    return TrackerDevice(
      signature: 'tutorial-demo-airtag',
      id: 'tutorial-demo-airtag',
      logicalId: 'tutorial-demo-airtag',
      kind: 'AIRTAG',
      pinnedMac: 'D4:90:F6:D4:4B:4F',
      lastMac: 'D4:90:F6:D4:4B:4F',
      rssi: -61,
      distanceMeters: 1.95,
      firstSeenMs: now - 6000,
      lastSeenMs: now - 1200,
      sightings: 8,
      rotatingMacCount: 1,
      rawFrame: '1EFF4C00121900112233445566778899AABBCC',
      smoothedRssi: -61,
      smoothedDistanceMeters: 1.95,
      status: DeviceStatus.unknown,
    );
  }

  @override
  void initState() {
    super.initState();

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

        if (prev == null) {
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

    _orderTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (!mounted) return;
      if (FiltersModel.state.sortMode != SortMode.recent) return;

      setState(() {
        _rebuildRecentOrder();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 500));
      _checkFirstLaunchTutorial();
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
      final c = db.lastSeenMs.compareTo(da.lastSeenMs);
      if (c != 0) return c;

      final ia = _displayOrder.indexOf(a);
      final ib = _displayOrder.indexOf(b);
      if (ia == -1 && ib == -1) return 0;
      if (ia == -1) return 1;
      if (ib == -1) return -1;
      return ia.compareTo(ib);
    });

    _displayOrder = sigs;
  }

  List<TrackerDevice> get devices {
    final mode = FiltersModel.state.sortMode;

    if (mode == SortMode.distanceAsc) {
      final list = _devicesBySig.values.toList()
        ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
      return list;
    }

    if (_displayOrder.isEmpty) _rebuildRecentOrder();

    return _displayOrder
        .where(_devicesBySig.containsKey)
        .map((sig) => _devicesBySig[sig]!)
        .toList();
  }

  Future<void> toggleScan() async {
    if (_tutorialRunning) return;

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

  Future<void> _checkFirstLaunchTutorial() async {
    final prefs = await SharedPreferences.getInstance();

    // For testing quickstart tutorial only, uncomment this:
    // await prefs.setBool('seen_quick_start_guide', false);

    final seen = prefs.getBool('seen_quick_start_guide') ?? false;
    if (seen || !mounted) return;
    if (_materialContext == null) return;

    await _showTutorialStartPrompt();
  }

  Future<void> _markTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_quick_start_guide', true);
  }

  Future<void> _showTutorialStartPrompt() async {
    final dialogContext = _materialContext;
    if (dialogContext == null) return;

    await showDialog(
      context: dialogContext,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Quick Start Guide',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w800,
            ),
          ),
          content: const Text(
            'Would you like a quickstart walkthrough of the app?',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _markTutorialSeen();
                if (_navigatorKey.currentState != null) {
                  _navigatorKey.currentState!.pop();
                }
              },
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_navigatorKey.currentState != null) {
                  _navigatorKey.currentState!.pop();
                }
                await Future.delayed(const Duration(milliseconds: 250));
                await _markTutorialSeen();
                await _startQuickGuide();
              },
              child: const Text('Start Guide'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _showCoach(List<TargetFocus> targets) async {
    final coachContext = _materialContext;
    if (coachContext == null || targets.isEmpty) return false;

    final completer = Completer<bool>();

    final coach = TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      opacityShadow: 0.78,
      paddingFocus: 10,
      hideSkip: true,
      onFinish: () {
        if (!completer.isCompleted) completer.complete(true);
      },
      onSkip: () {
        if (!completer.isCompleted) completer.complete(false);
        return true;
      },
    );

    await Future.delayed(const Duration(milliseconds: 100));
    coach.show(context: coachContext);
    return completer.future;
  }

  Future<void> _startQuickGuide() async {
    if (_tutorialRunning || !mounted) return;
    _tutorialRunning = true;

    if (scanning) {
      await BleBridge.stopScan();
      await _motionSub?.cancel();
      _motionSub = null;
      setState(() {
        scanning = false;
        lastScanTime = DateTime.now();
        scanStartTime = null;
      });
    }

    setState(() => pageIndex = 0);
    await Future.delayed(const Duration(milliseconds: 900));

    await _runDistanceTutorial();
    if (!mounted) return;

    await _openSearchTutorialFromDemoTracker();
    if (!mounted) return;

    setState(() => pageIndex = 1);
    await Future.delayed(const Duration(milliseconds: 900));

    await _runIdentifyTutorial();
    if (!mounted) return;

    await _runDrawerTutorial();
    if (!mounted) return;

    setState(() => pageIndex = 0);
    _tutorialRunning = false;
  }

  Future<void> _runDistanceTutorial() async {
    await _showCoach([
      tutorialTarget(
        key: _scanButtonKey,
        id: 'scan_button',
        title: 'Start and stop scanning',
        body: 'Press Scan here to stop and start device scanning.',
      ),
      tutorialTarget(
        key: _trackerListKey,
        id: 'distance_list',
        title: 'Detected tags',
        body:
        'Tags will show up here along with signal strength, name, and distance.',
        // Box offset was too high needed to be lowered:
        yOffset: 110,
      ),
      tutorialTarget(
        key: _firstTrackerCardKey,
        id: 'open_tracker',
        title: 'Open a tracker',
        body: 'You can click a tag to open a more detailed page.',
      ),
    ]);
  }

  Future<void> _openSearchTutorialFromDemoTracker() async {
    final navContext = _materialContext;
    if (navContext == null) return;

    await Future.delayed(const Duration(milliseconds: 250));

    await Navigator.push(
      navContext,
      MaterialPageRoute(
        builder: (_) => SearchPage(
          device: _demoTutorialDevice,
          tutorialMode: true,
        ),
      ),
    );
  }

  Future<void> _runIdentifyTutorial() async {
    await _showCoach([
      tutorialTarget(
        key: _identifyTabsKey,
        id: 'identify_tabs',
        title: 'Identify page',
        body:
        'Trackers will be categorized here once the user picks a category on the other page.',
      ),
    ]);
  }

  Future<void> _runDrawerTutorial() async {
    _scaffoldKey.currentState?.openDrawer();
    await Future.delayed(const Duration(milliseconds: 600));

    await _showCoach([
      tutorialTarget(
        key: _drawerFiltersKey,
        id: 'drawer_filters',
        title: 'Filter options',
        body: 'Use these filter options to control what trackers are shown.',
      ),
      tutorialTarget(
        key: _drawerReportsKey,
        id: 'drawer_reports',
        title: 'Reports page',
        body: 'Suspect tracker reports will show up here.',
      ),
    ]);

    if (!mounted || _materialContext == null) return;

    Navigator.of(_materialContext!).pop();
    await Future.delayed(const Duration(milliseconds: 300));

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

    final tutorialTrackedDevices =
    _tutorialRunning ? <TrackerDevice>[_demoTutorialDevice] : trackedDevices;

    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (materialContext) {
          _materialContext = materialContext;

          final pages = [
            DistancePage(
              devices: trackedDevices,
              scanning: scanning,
              onRescan: toggleScan,
              lastScanTime: lastScanTime,
              scanStartTime: scanStartTime,
              scanButtonKey: _scanButtonKey,
              trackerListKey: _trackerListKey,
              firstTrackerCardKey: _firstTrackerCardKey,
              tutorialMode: _tutorialRunning,
              tutorialDevice: _demoTutorialDevice,
            ),
            IdentificationPage(
              devices: tutorialTrackedDevices,
              identifyTabsKey: _identifyTabsKey,
            ),
          ];

          return FadeTransition(
            opacity: _fadeAnim,
            child: Scaffold(
              key: _scaffoldKey,
              drawer: AppDrawer(
                filtersTileKey: _drawerFiltersKey,
                reportsTileKey: _drawerReportsKey,
              ),
              // The hamburger menu icon is below
              appBar: AppBar(
                leading: IconButton(
                  key: _drawerButtonKey,
                  icon: const Icon(Icons.menu, size: 30),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                centerTitle: true,
                title: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
          );
        },
      ),
    );
  }
}

