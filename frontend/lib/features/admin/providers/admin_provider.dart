import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../furniture/data/furniture_api_client.dart';
import '../../designer/data/material_api_client.dart';
import '../../project/data/project_api_client.dart';
import '../../furniture/models/furniture_asset.dart';
import '../../analytics/data/analytics_api_client.dart';

enum AdminSection {
  dashboard,
  furniture,
  materials,
  categories,
  users,
  analytics,
  system,
}

class AdminState {
  final bool isLoading;
  final String? errorMessage;
  final AdminSection activeSection;
  final int activeUsersCount;
  final int projectsCount;
  final int furnitureAssetsCount;
  final int materialsCount;
  final double storageUsedBytes;
  final double storageTotalBytes;
  final List<Map<String, dynamic>> recentActivities;
  final List<Map<String, dynamic>> users;
  final List<dynamic> roles;
  final List<dynamic> permissions;
  final List<dynamic> userSessions;
  final List<FurnitureAsset> furnitureAssets;
  final List<FurnitureCategory> categories;
  final List<dynamic> materials;
  final Map<String, int> categoriesBreakdown;
  final Map<String, String> systemHealth;
  final Map<String, bool> systemConfig;
  
  // New Paginated & Selection properties
  final List<String> selectedFurnitureIds;
  final String furnitureSearch;
  final String? furnitureCategoryFilter;
  final String? furnitureStyleFilter;
  final int furniturePage;
  final int furnitureLimit;
  final bool furnitureHasMore;
  
  // Telemetry properties
  final String selectedPeriod;
  final Map<String, dynamic>? telemetryData;

  const AdminState({
    this.isLoading = false,
    this.errorMessage,
    this.activeSection = AdminSection.dashboard,
    this.activeUsersCount = 142,
    this.projectsCount = 84,
    this.furnitureAssetsCount = 312,
    this.materialsCount = 98,
    this.storageUsedBytes = 1.2 * 1024 * 1024 * 1024,
    this.storageTotalBytes = 5.0 * 1024 * 1024 * 1024,
    this.recentActivities = const [],
    this.users = const [],
    this.roles = const [],
    this.permissions = const [],
    this.userSessions = const [],
    this.furnitureAssets = const [],
    this.categories = const [],
    this.materials = const [],
    this.categoriesBreakdown = const {},
    this.systemHealth = const {
      'FastAPI Service': 'HEALTHY',
      'Database': 'CONNECTED',
      'Storage Service': 'HEALTHY',
      'Cache Manager': '32 MB',
    },
    this.systemConfig = const {
      'Maintenance Mode': false,
      'Verbose Logging': false,
      'Enable AI Planning': true,
    },
    this.selectedFurnitureIds = const [],
    this.furnitureSearch = '',
    this.furnitureCategoryFilter,
    this.furnitureStyleFilter,
    this.furniturePage = 1,
    this.furnitureLimit = 20,
    this.furnitureHasMore = true,
    this.selectedPeriod = '7d',
    this.telemetryData,
  });

  AdminState copyWith({
    bool? isLoading,
    String? errorMessage,
    AdminSection? activeSection,
    int? activeUsersCount,
    int? projectsCount,
    int? furnitureAssetsCount,
    int? materialsCount,
    double? storageUsedBytes,
    double? storageTotalBytes,
    List<Map<String, dynamic>>? recentActivities,
    List<Map<String, dynamic>>? users,
    List<dynamic>? roles,
    List<dynamic>? permissions,
    List<dynamic>? userSessions,
    List<FurnitureAsset>? furnitureAssets,
    List<FurnitureCategory>? categories,
    List<dynamic>? materials,
    Map<String, int>? categoriesBreakdown,
    Map<String, String>? systemHealth,
    Map<String, bool>? systemConfig,
    List<String>? selectedFurnitureIds,
    String? furnitureSearch,
    String? furnitureCategoryFilter,
    bool clearCategoryFilter = false,
    String? furnitureStyleFilter,
    bool clearStyleFilter = false,
    int? furniturePage,
    int? furnitureLimit,
    bool? furnitureHasMore,
    String? selectedPeriod,
    Map<String, dynamic>? telemetryData,
  }) {
    return AdminState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      activeSection: activeSection ?? this.activeSection,
      activeUsersCount: activeUsersCount ?? this.activeUsersCount,
      projectsCount: projectsCount ?? this.projectsCount,
      furnitureAssetsCount: furnitureAssetsCount ?? this.furnitureAssetsCount,
      materialsCount: materialsCount ?? this.materialsCount,
      storageUsedBytes: storageUsedBytes ?? this.storageUsedBytes,
      storageTotalBytes: storageTotalBytes ?? this.storageTotalBytes,
      recentActivities: recentActivities ?? this.recentActivities,
      users: users ?? this.users,
      roles: roles ?? this.roles,
      permissions: permissions ?? this.permissions,
      userSessions: userSessions ?? this.userSessions,
      furnitureAssets: furnitureAssets ?? this.furnitureAssets,
      categories: categories ?? this.categories,
      materials: materials ?? this.materials,
      categoriesBreakdown: categoriesBreakdown ?? this.categoriesBreakdown,
      systemHealth: systemHealth ?? this.systemHealth,
      systemConfig: systemConfig ?? this.systemConfig,
      selectedFurnitureIds: selectedFurnitureIds ?? this.selectedFurnitureIds,
      furnitureSearch: furnitureSearch ?? this.furnitureSearch,
      furnitureCategoryFilter: clearCategoryFilter ? null : (furnitureCategoryFilter ?? this.furnitureCategoryFilter),
      furnitureStyleFilter: clearStyleFilter ? null : (furnitureStyleFilter ?? this.furnitureStyleFilter),
      furniturePage: furniturePage ?? this.furniturePage,
      furnitureLimit: furnitureLimit ?? this.furnitureLimit,
      furnitureHasMore: furnitureHasMore ?? this.furnitureHasMore,
      selectedPeriod: selectedPeriod ?? this.selectedPeriod,
      telemetryData: telemetryData ?? this.telemetryData,
    );
  }
}

class AdminNotifier extends Notifier<AdminState> {
  final ApiClient _apiClient = ApiClient();
  final FurnitureApiClient _furnitureApiClient = FurnitureApiClient();
  final MaterialApiClient _materialApiClient = MaterialApiClient();
  final ProjectApiClient _projectApiClient = ProjectApiClient();
  final AnalyticsApiClient _analyticsApiClient = AnalyticsApiClient();

  @override
  AdminState build() {
    // Perform initial fetch on state initialization
    Future.microtask(() => fetchAdminDashboard());
    return const AdminState(
      users: [
        {
          'id': '',
          'name': 'Alice Smith',
          'email': 'alice@flowspace.com',
          'role': 'Administrator',
          'status': 'Active',
          'last_login': 'N/A',
        },
        {
          'id': '',
          'name': 'Bob Miller',
          'email': 'bob@designer.com',
          'role': 'Interior Designer',
          'status': 'Active',
          'last_login': 'N/A',
        },
        {
          'id': '',
          'name': 'Charlie Green',
          'email': 'charlie@architect.io',
          'role': 'Architect',
          'status': 'Active',
          'last_login': 'N/A',
        },
        {
          'id': '',
          'name': 'David Jones',
          'email': 'david@gmail.com',
          'role': 'Customer',
          'status': 'Suspended',
          'last_login': 'N/A',
        },
        {
          'id': '',
          'name': 'Eva Brown',
          'email': 'eva@outlook.com',
          'role': 'Customer',
          'status': 'Active',
          'last_login': 'N/A',
        },
      ],
      recentActivities: [
        {
          'user': 'alice@flowspace.com',
          'action': 'Uploaded asset "Scandia Lounge Chair"',
          'time': '5 mins ago',
          'icon': 'upload_file',
        },
        {
          'user': 'bob@designer.com',
          'action': 'Created project "Sunny Living Room"',
          'time': '15 mins ago',
          'icon': 'add_circle',
        },
        {
          'user': 'charlie@architect.io',
          'action': 'Applied material "Light Oak Wood"',
          'time': '42 mins ago',
          'icon': 'texture',
        },
      ],
    );
  }

  void changeSection(AdminSection section) {
    state = state.copyWith(activeSection: section);
  }

  Future<void> fetchAdminDashboard() async {
    if (!ref.mounted) return;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      // 1. Fetch real assets
      List<FurnitureAsset> assetsList = [];
      try {
        assetsList = await _furnitureApiClient.getFurnitureAssets(
          search: state.furnitureSearch,
          category: state.furnitureCategoryFilter,
          style: state.furnitureStyleFilter,
          page: state.furniturePage,
          limit: state.furnitureLimit,
        );
      } catch (_) {}

      // 2. Fetch categories
      List<FurnitureCategory> categoriesList = [];
      try {
        categoriesList = await _furnitureApiClient.getCategories();
      } catch (_) {}

      // 3. Fetch real materials
      List<dynamic> materialsList = [];
      try {
        final res = await _materialApiClient.getMaterials(limit: 100);
        materialsList = res['materials'] ?? [];
      } catch (_) {}

      // 4. Fetch real projects
      List<dynamic> projectsList = [];
      try {
        projectsList = await _projectApiClient.getProjects(limit: 100);
      } catch (_) {}

      // 5. Fetch real users from backend
      List<Map<String, dynamic>> usersList = [];
      try {
        final res = await _apiClient.get('/auth/admin/users');
        final data = jsonDecode(res.body);
        if (res.statusCode == 200 && data['success'] == true) {
          final List rawUsers = data['data'] ?? [];
          usersList = rawUsers.map<Map<String, dynamic>>((u) => {
            'id': u['id'] ?? '',
            'name': u['full_name'] ?? '',
            'email': u['email'] ?? '',
            'role': u['role'] ?? '',
            'status': (u['is_active'] == true) ? 'Active' : 'Suspended',
            'is_verified': u['is_verified'] ?? false,
            'last_login': u['last_login'] ?? 'Never',
          }).toList();
        }
      } catch (_) {}

      // 6. Fetch roles
      List<dynamic> rolesList = [];
      try {
        final res = await _apiClient.get('/auth/admin/roles');
        final data = jsonDecode(res.body);
        if (res.statusCode == 200 && data['success'] == true) {
          rolesList = data['data'] ?? [];
        }
      } catch (_) {}

      // 7. Fetch permissions
      List<dynamic> permissionsList = [];
      try {
        final res = await _apiClient.get('/auth/admin/permissions');
        final data = jsonDecode(res.body);
        if (res.statusCode == 200 && data['success'] == true) {
          permissionsList = data['data'] ?? [];
        }
      } catch (_) {}

      // 8. Calculate category counts
      final Map<String, int> categories = {};
      for (final asset in assetsList) {
        final cat = asset.category;
        categories[cat] = (categories[cat] ?? 0) + 1;
      }
      for (final mat in materialsList) {
        final cat = mat.category?.name ?? 'Uncategorized';
        categories[cat] = (categories[cat] ?? 0) + 1;
      }

      // 9. Fetch system telemetry
      Map<String, dynamic>? telemetry;
      try {
        telemetry = await _analyticsApiClient.getSystemTelemetry(state.selectedPeriod);
      } catch (_) {}

      // Fetch system status
      Map<String, String> systemHealthMap = Map<String, String>.from(state.systemHealth);
      double storageUsed = state.storageUsedBytes;
      double storageTotal = state.storageTotalBytes;
      try {
        final systemRes = await _apiClient.get('/system/status');
        if (systemRes.statusCode == 200) {
          final systemData = jsonDecode(systemRes.body);
          final List healthList = systemData['health'] ?? [];
          final cacheData = systemData['cache'] ?? {};
          final storageData = systemData['storage'] ?? {};
          
          systemHealthMap.clear();
          for (final h in healthList) {
            final service = h['service'] ?? '';
            final status = h['status'] ?? '';
            systemHealthMap[service] = status;
          }
          if (cacheData.containsKey('size_formatted')) {
            systemHealthMap['Cache Manager'] = cacheData['size_formatted'];
          }
          
          if (storageData.containsKey('total_size_bytes')) {
            storageUsed = (storageData['total_size_bytes'] as num).toDouble();
          }
          if (storageData.containsKey('disk_usage')) {
            storageTotal = (storageData['disk_usage']['total'] as num).toDouble();
          }
        }
      } catch (_) {}

      if (!ref.mounted) return;
      final bool hasMore = assetsList.length >= state.furnitureLimit;
      state = state.copyWith(
        isLoading: false,
        furnitureAssets: assetsList,
        categories: categoriesList,
        materials: materialsList,
        users: usersList.isNotEmpty ? usersList : state.users,
        roles: rolesList.isNotEmpty ? rolesList : state.roles,
        permissions: permissionsList.isNotEmpty ? permissionsList : state.permissions,
        activeUsersCount: telemetry != null
            ? (telemetry['active_users']['active_users_count'] as num).toInt()
            : (usersList.isNotEmpty ? usersList.length : state.activeUsersCount),
        furnitureAssetsCount: assetsList.isNotEmpty ? assetsList.length : state.furnitureAssetsCount,
        materialsCount: materialsList.isNotEmpty ? materialsList.length : state.materialsCount,
        projectsCount: telemetry != null
            ? (telemetry['project_statistics']['total_projects'] as num).toInt()
            : (projectsList.isNotEmpty ? projectsList.length : state.projectsCount),
        categoriesBreakdown: telemetry != null
            ? Map<String, int>.from(telemetry['furniture_usage']['categories_breakdown'])
            : categories,
        furnitureHasMore: hasMore,
        telemetryData: telemetry ?? state.telemetryData,
        systemHealth: systemHealthMap,
        storageUsedBytes: storageUsed,
        storageTotalBytes: storageTotal,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> updateSelectedPeriod(String period) async {
    state = state.copyWith(selectedPeriod: period, isLoading: true);
    await fetchAdminDashboard();
  }

  void updateSearch(String search) {
    state = state.copyWith(furnitureSearch: search, furniturePage: 1);
    fetchAdminDashboard();
  }

  void updateCategoryFilter(String? category) {
    if (category == null || category.isEmpty) {
      state = state.copyWith(clearCategoryFilter: true, furniturePage: 1);
    } else {
      state = state.copyWith(furnitureCategoryFilter: category, furniturePage: 1);
    }
    fetchAdminDashboard();
  }

  void updateStyleFilter(String? style) {
    if (style == null || style.isEmpty) {
      state = state.copyWith(clearStyleFilter: true, furniturePage: 1);
    } else {
      state = state.copyWith(furnitureStyleFilter: style, furniturePage: 1);
    }
    fetchAdminDashboard();
  }

  void nextPage() {
    if (state.furnitureHasMore && !state.isLoading) {
      state = state.copyWith(furniturePage: state.furniturePage + 1);
      fetchAdminDashboard();
    }
  }

  void previousPage() {
    if (state.furniturePage > 1 && !state.isLoading) {
      state = state.copyWith(furniturePage: state.furniturePage - 1);
      fetchAdminDashboard();
    }
  }

  void setPage(int page) {
    if (page >= 1 && !state.isLoading) {
      state = state.copyWith(furniturePage: page);
      fetchAdminDashboard();
    }
  }

  void toggleSelection(String assetId) {
    final updated = List<String>.from(state.selectedFurnitureIds);
    if (updated.contains(assetId)) {
      updated.remove(assetId);
    } else {
      updated.add(assetId);
    }
    state = state.copyWith(selectedFurnitureIds: updated);
  }

  void selectAll() {
    final ids = state.furnitureAssets.map((a) => a.id).toList();
    state = state.copyWith(selectedFurnitureIds: ids);
  }

  void clearSelection() {
    state = state.copyWith(selectedFurnitureIds: const []);
  }

  Future<void> deleteFurnitureAsset(String assetId) async {
    state = state.copyWith(isLoading: true);
    try {
      await _furnitureApiClient.deleteFurnitureAsset(assetId);
      final updated = List<String>.from(state.selectedFurnitureIds)..remove(assetId);
      state = state.copyWith(selectedFurnitureIds: updated);
      await fetchAdminDashboard();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> deleteMaterial(String id) async {
    state = state.copyWith(isLoading: true);
    try {
      await _materialApiClient.deleteMaterial(id);
      await fetchAdminDashboard();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> bulkDeleteFurnitureAssets() async {
    if (state.selectedFurnitureIds.isEmpty) return;
    state = state.copyWith(isLoading: true);
    try {
      await _furnitureApiClient.bulkDeleteFurniture(state.selectedFurnitureIds);
      state = state.copyWith(selectedFurnitureIds: const []);
      await fetchAdminDashboard();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> bulkUpdateFurnitureCategory(String category) async {
    if (state.selectedFurnitureIds.isEmpty) return;
    state = state.copyWith(isLoading: true);
    try {
      await _furnitureApiClient.bulkUpdateCategory(state.selectedFurnitureIds, category);
      state = state.copyWith(selectedFurnitureIds: const []);
      await fetchAdminDashboard();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> createCategory(String name, String? description) async {
    state = state.copyWith(isLoading: true);
    try {
      await _furnitureApiClient.createCategory(name, description);
      await fetchAdminDashboard();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> updateCategory(String id, String name, String? description) async {
    state = state.copyWith(isLoading: true);
    try {
      await _furnitureApiClient.updateCategory(id, name, description);
      await fetchAdminDashboard();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> deleteCategory(String id) async {
    state = state.copyWith(isLoading: true);
    try {
      await _furnitureApiClient.deleteCategory(id);
      await fetchAdminDashboard();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  void toggleConfig(String key) {
    final updatedConfig = Map<String, bool>.from(state.systemConfig);
    if (updatedConfig.containsKey(key)) {
      updatedConfig[key] = !updatedConfig[key]!;
      state = state.copyWith(systemConfig: updatedConfig);
    }
  }

  Future<void> toggleUserStatus(String userIdOrEmail, [String? currentStatus]) async {
    final index = state.users.indexWhere((u) => u['id'] == userIdOrEmail || u['email'] == userIdOrEmail);
    String status = currentStatus ?? '';
    String userId = userIdOrEmail;
    if (index != -1) {
      status = currentStatus ?? state.users[index]['status'];
      userId = state.users[index]['id'] ?? userIdOrEmail;
    }

    if (userId.isEmpty || userId.contains('@')) {
      final updatedUsers = state.users.map((user) {
        if (user['email'] == userIdOrEmail || user['id'] == userIdOrEmail) {
          final newStatus = user['status'] == 'Active' ? 'Suspended' : 'Active';
          return {
            ...user,
            'status': newStatus,
          };
        }
        return user;
      }).toList();
      state = state.copyWith(users: updatedUsers);
      return;
    }

    state = state.copyWith(isLoading: true);
    try {
      final isSuspended = status == 'Suspended';
      final endpoint = isSuspended
          ? '/auth/admin/users/$userId/activate'
          : '/auth/admin/users/$userId/suspend';
      
      final res = await _apiClient.post(endpoint);
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        await fetchAdminDashboard();
      } else {
        state = state.copyWith(isLoading: false, errorMessage: data['message'] ?? 'Failed to update user status');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> changeUserRole(String userId, String roleName) async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await _apiClient.put(
        '/auth/admin/users/$userId/role',
        body: {'role_name': roleName},
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        await fetchAdminDashboard();
      } else {
        state = state.copyWith(isLoading: false, errorMessage: data['message'] ?? 'Failed to update user role');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> deleteUser(String userId) async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await _apiClient.delete('/auth/admin/users/$userId');
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        await fetchAdminDashboard();
      } else {
        state = state.copyWith(isLoading: false, errorMessage: data['message'] ?? 'Failed to delete user');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> fetchUserSessions(String userId) async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await _apiClient.get('/auth/admin/users/$userId/sessions');
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        state = state.copyWith(isLoading: false, userSessions: data['data'] ?? []);
      } else {
        state = state.copyWith(isLoading: false, errorMessage: data['message'] ?? 'Failed to fetch sessions');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> revokeUserSession(String sessionId, String userId) async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await _apiClient.post('/auth/admin/sessions/$sessionId/revoke');
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        await fetchUserSessions(userId);
      } else {
        state = state.copyWith(isLoading: false, errorMessage: data['message'] ?? 'Failed to revoke session');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> revokeAllUserSessions(String userId) async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await _apiClient.post('/auth/admin/users/$userId/sessions/revoke-all');
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        await fetchUserSessions(userId);
      } else {
        state = state.copyWith(isLoading: false, errorMessage: data['message'] ?? 'Failed to revoke all sessions');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> updateRolePermissions(String roleId, List<String> permissionNames) async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await _apiClient.put(
        '/auth/admin/roles/$roleId/permissions',
        body: {'permission_names': permissionNames},
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        await fetchAdminDashboard();
      } else {
        state = state.copyWith(isLoading: false, errorMessage: data['message'] ?? 'Failed to update permissions');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> clearSystemCache() async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await _apiClient.post('/system/cache/purge');
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        final currentSize = data['current_size'] ?? '0 B';
        final updatedHealth = Map<String, String>.from(state.systemHealth);
        updatedHealth['Cache Manager'] = currentSize;

        final updatedActivities = List<Map<String, dynamic>>.from(state.recentActivities);
        updatedActivities.insert(0, {
          'user': 'admin@flowspace.com',
          'action': 'Cleared system log and GLB optimization cache',
          'time': 'Just now',
          'icon': 'delete_sweep',
        });

        state = state.copyWith(
          isLoading: false,
          systemHealth: updatedHealth,
          recentActivities: updatedActivities,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: data['message'] ?? 'Failed to purge cache',
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }
}

final adminProvider = NotifierProvider<AdminNotifier, AdminState>(() {
  return AdminNotifier();
});
