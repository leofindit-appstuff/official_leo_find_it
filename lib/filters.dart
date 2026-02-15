import 'package:flutter/foundation.dart';

enum SortMode {
  recent,       // default
  distanceAsc,  // closest -> farthest
}

class FiltersState {
  final bool filterByRssi;
  final int rssiThreshold; // show devices with rssi >= threshold
  final SortMode sortMode;

  const FiltersState({
    required this.filterByRssi,
    required this.rssiThreshold,
    required this.sortMode,
  });

  FiltersState copyWith({
    bool? filterByRssi,
    int? rssiThreshold,
    SortMode? sortMode,
  }) {
    return FiltersState(
      filterByRssi: filterByRssi ?? this.filterByRssi,
      rssiThreshold: rssiThreshold ?? this.rssiThreshold,
      sortMode: sortMode ?? this.sortMode,
    );
  }
}

class FiltersModel {
  static final ValueNotifier<FiltersState> notifier =
  ValueNotifier<FiltersState>(
    const FiltersState(
      filterByRssi: false,
      rssiThreshold: -70,
      sortMode: SortMode.recent,
    ),
  );

  static FiltersState get state => notifier.value;

  static void setFilterByRssi(bool v) =>
      notifier.value = notifier.value.copyWith(filterByRssi: v);

  static void setRssiThreshold(int v) =>
      notifier.value = notifier.value.copyWith(rssiThreshold: v);

  static void setSortMode(SortMode mode) =>
      notifier.value = notifier.value.copyWith(sortMode: mode);
}
