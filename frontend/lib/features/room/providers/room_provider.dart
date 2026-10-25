import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../project/data/project_sync_repository.dart';

class RoomListState {
  final bool isLoading;
  final String? errorMessage;
  final List<dynamic> rooms;

  const RoomListState({
    this.isLoading = false,
    this.errorMessage,
    this.rooms = const [],
  });

  RoomListState copyWith({
    bool? isLoading,
    String? errorMessage,
    List<dynamic>? rooms,
  }) {
    return RoomListState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      rooms: rooms ?? this.rooms,
    );
  }
}

class RoomListNotifier extends Notifier<RoomListState> {
  final ProjectSyncRepository _syncRepository = ProjectSyncRepository();

  @override
  RoomListState build() {
    return const RoomListState();
  }

  Future<void> fetchRooms(String projectId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final list = await _syncRepository.getRooms(projectId);
      state = RoomListState(rooms: list);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<String?> createRoom(String projectId, {
    required String roomName,
    required String roomType,
    int floorNumber = 1,
    String? notes,
    String roomColor = '#FFFFFF',
    String? properties,
  }) async {
    try {
      final roomId = await _syncRepository.createRoom(
        projectId,
        roomName: roomName,
        roomType: roomType,
        floorNumber: floorNumber,
        notes: notes,
        roomColor: roomColor,
        properties: properties,
      );
      await fetchRooms(projectId);
      return roomId;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return null;
    }
  }

  Future<bool> deleteRoom(String projectId, String roomId) async {
    try {
      await _syncRepository.deleteRoom(projectId, roomId);
      await fetchRooms(projectId);
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> duplicateRoom(String projectId, String roomId) async {
    try {
      await _syncRepository.duplicateRoom(projectId, roomId);
      await fetchRooms(projectId);
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }
}

final roomListProvider = NotifierProvider<RoomListNotifier, RoomListState>(() {
  return RoomListNotifier();
});

class RoomDetailsState {
  final bool isLoading;
  final String? errorMessage;
  final Map<String, dynamic>? details;

  const RoomDetailsState({
    this.isLoading = false,
    this.errorMessage,
    this.details,
  });

  RoomDetailsState copyWith({
    bool? isLoading,
    String? errorMessage,
    Map<String, dynamic>? details,
  }) {
    return RoomDetailsState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      details: details ?? this.details,
    );
  }
}

class RoomDetailsNotifier extends Notifier<RoomDetailsState> {
  final ProjectSyncRepository _syncRepository = ProjectSyncRepository();

  @override
  RoomDetailsState build() {
    return const RoomDetailsState();
  }

  Future<void> fetchDetails(String roomId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final data = await _syncRepository.getRoomDetails(roomId);
      state = RoomDetailsState(details: data);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<bool> updateRoom(String roomId, {
    required String roomName,
    required String roomType,
    required int floorNumber,
    String? notes,
    required String roomColor,
    String? properties,
  }) async {
    try {
      await _syncRepository.updateRoom(
        roomId,
        roomName: roomName,
        roomType: roomType,
        floorNumber: floorNumber,
        notes: notes,
        roomColor: roomColor,
        properties: properties,
      );
      await fetchDetails(roomId);
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> updateMeasurements(String roomId, {
    required double length,
    required double width,
    required double height,
    double? floorThickness,
    double? wallThickness,
    double? ceilingHeight,
  }) async {
    try {
      await _syncRepository.updateMeasurements(
        roomId,
        length: length,
        width: width,
        height: height,
        floorThickness: floorThickness,
        wallThickness: wallThickness,
        ceilingHeight: ceilingHeight,
      );
      await fetchDetails(roomId);
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }
}

final roomDetailsProvider = NotifierProvider<RoomDetailsNotifier, RoomDetailsState>(() {
  return RoomDetailsNotifier();
});
