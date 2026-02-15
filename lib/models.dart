import 'dart:math';

enum DeviceStatus { unknown, suspect, friendly }

extension DeviceStatusX on DeviceStatus {
  String get label {
    switch (this) {
      case DeviceStatus.unknown:
        return "Unknown";
      case DeviceStatus.suspect:
        return "Suspect";
      case DeviceStatus.friendly:
        return "Friendly";
    }
  }
}

class TrackerDevice {
  final String signature;
  final String id;
  final String logicalId; // NEW: stable logical identity from Kotlin
  final String kind;

  // First stable MAC ever observed (never overwritten)
  final String? pinnedMac;

  // Last observed MAC (may rotate)
  final String? lastMac;

  final int rssi;
  final double distanceMeters;
  final int firstSeenMs;
  final int lastSeenMs;
  final int sightings;
  final int rotatingMacCount;
  final String rawFrame;

  // Smoothed RSSI (EMA)
  final double smoothedRssi;

  // Smoothed distance (EMA + outlier clamp)
  final double smoothedDistanceMeters;

  // NEW: status tag
  final DeviceStatus status;

  static const double _mToFt = 3.28084;

  TrackerDevice({
    required this.signature,
    required this.id,
    required this.logicalId,
    required this.kind,
    required this.pinnedMac,
    required this.lastMac,
    required this.rssi,
    required this.distanceMeters,
    required this.firstSeenMs,
    required this.lastSeenMs,
    required this.sightings,
    required this.rotatingMacCount,
    required this.rawFrame,
    required this.smoothedRssi,
    required this.smoothedDistanceMeters,
    required this.status,
  });

  /// Stable key used to dedupe across scan restarts / MAC rotation
  String get stableKey {
    if (logicalId.isNotEmpty) return logicalId;
    if (id.isNotEmpty) return id;
    return signature;
  }

  // Keep meters as internal unit for logic.
  double get distanceM => distanceMeters;

  // UI uses smoothed distance to reduce scary jumps.
  double get distanceUiM => smoothedDistanceMeters;

  // Convenience: feet for UI.
  double get distanceFt => distanceUiM * _mToFt;

  String get distanceFtLabel =>
      '${distanceFt.toStringAsFixed(distanceFt < 10 ? 1 : 0)} ft';

  // Backwards-compatible alias if you were using `distance` before.
  double get distance => distanceMeters;

  bool get isLikelyAirTag => kind == 'AIRTAG';
  bool get isLikelyTile => kind == 'TILE';
  bool get isLikelySamsung => kind == 'SAMSUNG';

  String get displayName {
    if (isLikelyAirTag) return 'Apple AirTag';
    if (isLikelyTile) return 'Tile Tracker';
    if (isLikelySamsung) return 'Samsung SmartTag';
    if (kind.contains('APPLE')) return 'Apple Find My Device';
    return 'Unknown Tracker';
  }

  String get displayMac => pinnedMac ?? lastMac ?? 'Random / Rotating';

  TrackerDevice withStatus(DeviceStatus s) => TrackerDevice(
    signature: signature,
    id: id,
    logicalId: logicalId,
    kind: kind,
    pinnedMac: pinnedMac,
    lastMac: lastMac,
    rssi: rssi,
    distanceMeters: distanceMeters,
    firstSeenMs: firstSeenMs,
    lastSeenMs: lastSeenMs,
    sightings: sightings,
    rotatingMacCount: rotatingMacCount,
    rawFrame: rawFrame,
    smoothedRssi: smoothedRssi,
    smoothedDistanceMeters: smoothedDistanceMeters,
    status: s,
  );

  TrackerDevice merge(TrackerDevice newer) {
    // preserve status across updates
    final preservedStatus = status;

    // RSSI EMA
    final smoothedRssiNew = (smoothedRssi * 0.7) + (newer.rssi * 0.3);

    // Distance smoothing + outlier rejection (prevents big panic jumps)
    final prevD = smoothedDistanceMeters;
    final rawD = newer.distanceMeters;

    final int dtMs = (newer.lastSeenMs - lastSeenMs).clamp(1, 60000) as int;
    final double dtS = dtMs / 1000.0;

    const double maxSpeedMps = 6.0;
    final double maxDelta = maxSpeedMps * dtS;

    double clampedRaw = rawD;
    if (prevD > 0 && rawD > 0) {
      final double delta = rawD - prevD;
      if (delta.abs() > maxDelta) {
        clampedRaw = prevD + (delta.isNegative ? -maxDelta : maxDelta);
      }
    }

    const double distAlpha = 0.18;
    final double smoothedDistNew =
        (prevD * (1 - distAlpha)) + (clampedRaw * distAlpha);

    return TrackerDevice(
      signature: newer.signature.isNotEmpty ? newer.signature : signature,
      id: newer.id.isNotEmpty ? newer.id : id,
      logicalId: newer.logicalId.isNotEmpty ? newer.logicalId : logicalId,
      kind: newer.kind.isNotEmpty ? newer.kind : kind,
      pinnedMac: pinnedMac ?? newer.lastMac,
      lastMac: newer.lastMac,
      rssi: newer.rssi,
      distanceMeters: newer.distanceMeters,
      firstSeenMs: firstSeenMs,
      lastSeenMs: newer.lastSeenMs,
      sightings: sightings + 1,
      rotatingMacCount: newer.rotatingMacCount,
      rawFrame: newer.rawFrame,
      smoothedRssi: smoothedRssiNew,
      smoothedDistanceMeters: smoothedDistNew,
      status: preservedStatus,
    );
  }

  factory TrackerDevice.fromNative(Map<String, dynamic> m) {
    final mac = m['address'] as String?;
    final int rssi = (m['rssi'] as int?) ?? -100;
    final double dist = ((m['distanceMeters'] as num?) ?? 0).toDouble();
    final int lastSeen = (m['lastSeenMs'] as int?) ??
        DateTime.now().millisecondsSinceEpoch;

    return TrackerDevice(
      signature: (m['signature'] as String?) ?? '',
      id: (m['id'] as String?) ?? '',
      logicalId: (m['logicalId'] as String?) ?? '',
      kind: (m['kind'] as String?) ?? 'UNKNOWN',
      pinnedMac: mac,
      lastMac: mac,
      rssi: rssi,
      distanceMeters: dist,
      firstSeenMs: lastSeen,
      lastSeenMs: lastSeen,
      sightings: 1,
      rotatingMacCount: (m['rotatingMacCount'] as int?) ?? 1,
      rawFrame: (m['rawFrame'] as String?) ?? '',
      smoothedRssi: rssi.toDouble(),
      smoothedDistanceMeters: dist > 0 ? dist : 0.0,
      status: DeviceStatus.unknown,
    );
  }
}
