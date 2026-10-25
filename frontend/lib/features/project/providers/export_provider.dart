import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/export_api_client.dart';

class ExportState {
  final bool isLoading;
  final String? errorMessage;
  final List<dynamic> reportHistory;
  final String? currentReportId;
  final String? reportStatus;
  final Uint8List? downloadedBytes;

  const ExportState({
    this.isLoading = false,
    this.errorMessage,
    this.reportHistory = const [],
    this.currentReportId,
    this.reportStatus,
    this.downloadedBytes,
  });

  ExportState copyWith({
    bool? isLoading,
    String? errorMessage,
    List<dynamic>? reportHistory,
    String? currentReportId,
    String? reportStatus,
    Uint8List? downloadedBytes,
    bool clearDownloadedBytes = false,
  }) {
    return ExportState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      reportHistory: reportHistory ?? this.reportHistory,
      currentReportId: currentReportId ?? this.currentReportId,
      reportStatus: reportStatus ?? this.reportStatus,
      downloadedBytes: clearDownloadedBytes ? null : (downloadedBytes ?? this.downloadedBytes),
    );
  }
}

class ExportNotifier extends Notifier<ExportState> {
  final ExportApiClient _apiClient = ExportApiClient();

  @override
  ExportState build() {
    return const ExportState();
  }

  Future<void> fetchReportHistory(String projectId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final history = await _apiClient.getReportHistory(projectId);
      state = state.copyWith(isLoading: false, reportHistory: history);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> generateAndPollReport({
    required String projectId,
    String? roomId,
    required String reportType,
    String format = 'PDF',
  }) async {
    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      currentReportId: null,
      reportStatus: 'Initiating',
      clearDownloadedBytes: true,
    );

    try {
      final reportId = await _apiClient.generateReport(
        projectId: projectId,
        roomId: roomId,
        reportType: reportType,
        format: format,
      );

      state = state.copyWith(currentReportId: reportId, reportStatus: 'Pending');

      // Poll report status
      bool isFinished = false;
      int attempts = 0;
      const maxAttempts = 15; // 15 seconds max

      while (!isFinished && attempts < maxAttempts) {
        await Future.delayed(const Duration(seconds: 1));
        attempts++;

        final status = await _apiClient.getReportStatus(reportId);
        state = state.copyWith(reportStatus: status);

        if (status == 'Completed') {
          isFinished = true;
          // Download bytes
          final bytes = await _apiClient.downloadReport(reportId);
          state = state.copyWith(
            isLoading: false,
            reportStatus: 'Completed',
            downloadedBytes: bytes,
          );
          await fetchReportHistory(projectId);
        } else if (status == 'Failed') {
          isFinished = true;
          state = state.copyWith(
            isLoading: false,
            reportStatus: 'Failed',
            errorMessage: 'Report generation failed on server.',
          );
          await fetchReportHistory(projectId);
        }
      }

      if (!isFinished) {
        state = state.copyWith(
          isLoading: false,
          reportStatus: 'Timed Out',
          errorMessage: 'Report generation timed out.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        reportStatus: 'Error',
        errorMessage: e.toString(),
      );
    }
  }

  Future<Map<String, dynamic>?> exportProjectJson(String projectId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final data = await _apiClient.exportProjectJson(projectId);
      state = state.copyWith(isLoading: false);
      return data;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return null;
    }
  }

  Future<Uint8List?> exportProjectFile(String projectId, String format) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final bytes = await _apiClient.exportProjectFile(projectId, format);
      state = state.copyWith(isLoading: false);
      return bytes;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return null;
    }
  }

  Future<Map<String, dynamic>?> exportRoomJson(String roomId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final data = await _apiClient.exportRoomJson(roomId);
      state = state.copyWith(isLoading: false);
      return data;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return null;
    }
  }

  Future<Uint8List?> exportRoomFile(String roomId, String format) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final bytes = await _apiClient.exportRoomFile(roomId, format);
      state = state.copyWith(isLoading: false);
      return bytes;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return null;
    }
  }

  Future<Uint8List?> exportSceneImage(String roomId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final bytes = await _apiClient.exportSceneImage(roomId);
      state = state.copyWith(isLoading: false);
      return bytes;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return null;
    }
  }

  Future<Map<String, dynamic>?> exportAnalytics(String roomId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final data = await _apiClient.exportAnalytics(roomId);
      state = state.copyWith(isLoading: false);
      return data;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return null;
    }
  }

  Future<bool> importProjectJson(String jsonString) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      await _apiClient.importProject(data);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<Map<String, dynamic>?> backupProject(String projectId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final backup = await _apiClient.backupProject(projectId);
      state = state.copyWith(isLoading: false);
      return backup;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return null;
    }
  }

  Future<bool> restoreProjectJson(String backupJsonString) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final data = jsonDecode(backupJsonString) as Map<String, dynamic>;
      await _apiClient.restoreProject(data);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<Uint8List> downloadReport(String reportId) async {
    return await _apiClient.downloadReport(reportId);
  }
}


final exportProvider = NotifierProvider<ExportNotifier, ExportState>(() {
  return ExportNotifier();
});
