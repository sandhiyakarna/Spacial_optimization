import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/project_sync_repository.dart';

class ProjectListState {
  final bool isLoading;
  final String? errorMessage;
  final List<dynamic> projects;
  final String search;
  final String? statusFilter;
  final String sortBy;
  final bool favoriteOnly;

  // New sync fields
  final bool isSyncing;
  final bool isOffline;
  final List<ProjectConflict> conflicts;

  const ProjectListState({
    this.isLoading = false,
    this.errorMessage,
    this.projects = const [],
    this.search = '',
    this.statusFilter,
    this.sortBy = 'created_at',
    this.favoriteOnly = false,
    this.isSyncing = false,
    this.isOffline = false,
    this.conflicts = const [],
  });

  ProjectListState copyWith({
    bool? isLoading,
    String? errorMessage,
    List<dynamic>? projects,
    String? search,
    String? statusFilter,
    bool clearStatusFilter = false,
    String? sortBy,
    bool? favoriteOnly,
    bool? isSyncing,
    bool? isOffline,
    List<ProjectConflict>? conflicts,
  }) {
    return ProjectListState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      projects: projects ?? this.projects,
      search: search ?? this.search,
      statusFilter: clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
      sortBy: sortBy ?? this.sortBy,
      favoriteOnly: favoriteOnly ?? this.favoriteOnly,
      isSyncing: isSyncing ?? this.isSyncing,
      isOffline: isOffline ?? this.isOffline,
      conflicts: conflicts ?? this.conflicts,
    );
  }
}

class ProjectNotifier extends Notifier<ProjectListState> {
  final ProjectSyncRepository _syncRepository = ProjectSyncRepository();
  Timer? _syncTimer;

  @override
  ProjectListState build() {
    // Start periodic auto-sync every 30 seconds
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      autoSync();
    });
    ref.onDispose(() {
      _syncTimer?.cancel();
    });
    return const ProjectListState();
  }

  Future<void> autoSync() async {
    if (state.isSyncing) return;
    try {
      final online = await _syncRepository.isOnline();
      state = state.copyWith(isOffline: !online);
      if (online) {
        state = state.copyWith(isSyncing: true);
        await _syncRepository.sync();
        final list = await _syncRepository.getProjects(
          search: state.search,
          status: state.statusFilter,
          sort: state.sortBy,
          favorite: state.favoriteOnly,
        );
        state = state.copyWith(
          isSyncing: false,
          projects: list,
          conflicts: _syncRepository.conflicts,
        );
      }
    } catch (_) {
      state = state.copyWith(isSyncing: false);
    }
  }

  Future<void> manualSync() async {
    state = state.copyWith(isSyncing: true, errorMessage: null);
    try {
      final online = await _syncRepository.isOnline();
      state = state.copyWith(isOffline: !online);
      if (!online) {
        state = state.copyWith(isSyncing: false, errorMessage: "Cannot sync: Device is offline.");
        return;
      }
      await _syncRepository.sync();
      final list = await _syncRepository.getProjects(
        search: state.search,
        status: state.statusFilter,
        sort: state.sortBy,
        favorite: state.favoriteOnly,
      );
      state = state.copyWith(
        isSyncing: false,
        projects: list,
        conflicts: _syncRepository.conflicts,
      );
    } catch (e) {
      state = state.copyWith(isSyncing: false, errorMessage: e.toString());
    }
  }

  Future<void> resolveConflict(String projectId, bool useLocal) async {
    state = state.copyWith(isSyncing: true);
    try {
      await _syncRepository.resolveConflict(projectId, useLocal);
      final list = await _syncRepository.getProjects(
        search: state.search,
        status: state.statusFilter,
        sort: state.sortBy,
        favorite: state.favoriteOnly,
      );
      state = state.copyWith(
        isSyncing: false,
        projects: list,
        conflicts: _syncRepository.conflicts,
      );
    } catch (e) {
      state = state.copyWith(isSyncing: false, errorMessage: e.toString());
    }
  }

  Future<void> fetchProjects() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final online = await _syncRepository.isOnline();
      final list = await _syncRepository.getProjects(
        search: state.search,
        status: state.statusFilter,
        sort: state.sortBy,
        favorite: state.favoriteOnly,
      );
      state = state.copyWith(
        isLoading: false,
        projects: list,
        isOffline: !online,
        conflicts: _syncRepository.conflicts,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  void updateSearch(String search) {
    state = state.copyWith(search: search);
    fetchProjects();
  }

  void updateStatusFilter(String? status) {
    if (status == null) {
      state = state.copyWith(clearStatusFilter: true);
    } else {
      state = state.copyWith(statusFilter: status);
    }
    fetchProjects();
  }

  void updateSortBy(String sortBy) {
    state = state.copyWith(sortBy: sortBy);
    fetchProjects();
  }

  void updateFavoriteOnly(bool favoriteOnly) {
    state = state.copyWith(favoriteOnly: favoriteOnly);
    fetchProjects();
  }

  Future<bool> createProject({
    required String projectName,
    String? description,
    String? location,
  }) async {
    try {
      await _syncRepository.createProject(
        projectName: projectName,
        description: description,
        location: location,
      );
      await fetchProjects();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> updateProject(String projectId, {
    String? projectName,
    String? description,
    String? location,
    String? status,
  }) async {
    try {
      await _syncRepository.updateProject(
        projectId,
        projectName: projectName,
        description: description,
        location: location,
        status: status,
      );
      await fetchProjects();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> toggleFavorite(String projectId) async {
    try {
      await _syncRepository.toggleFavorite(projectId);
      await fetchProjects();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> duplicateProject(String projectId) async {
    try {
      await _syncRepository.duplicateProject(projectId);
      await fetchProjects();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> archiveProject(String projectId) async {
    try {
      await _syncRepository.updateProject(projectId, status: 'Archived');
      await fetchProjects();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> restoreProject(String projectId) async {
    try {
      await _syncRepository.updateProject(projectId, status: 'Draft');
      await fetchProjects();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> deleteProject(String projectId) async {
    try {
      await _syncRepository.softDeleteProject(projectId);
      await fetchProjects();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }
}

final projectProvider = NotifierProvider<ProjectNotifier, ProjectListState>(() {
  return ProjectNotifier();
});
