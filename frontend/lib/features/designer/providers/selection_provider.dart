import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/material_model.dart';

class SelectionState {
  final String? selectedFurnitureId;
  final String? selectedElementType; // 'furniture', 'wall', 'floor', 'ceiling'
  final MaterialModel? previewMaterial;

  const SelectionState({
    this.selectedFurnitureId,
    this.selectedElementType,
    this.previewMaterial,
  });

  SelectionState copyWith({
    String? selectedFurnitureId,
    bool clearFurniture = false,
    String? selectedElementType,
    bool clearElementType = false,
    MaterialModel? previewMaterial,
    bool clearPreviewMaterial = false,
  }) {
    return SelectionState(
      selectedFurnitureId: clearFurniture ? null : (selectedFurnitureId ?? this.selectedFurnitureId),
      selectedElementType: clearElementType ? null : (selectedElementType ?? this.selectedElementType),
      previewMaterial: clearPreviewMaterial ? null : (previewMaterial ?? this.previewMaterial),
    );
  }
}

class SelectionNotifier extends Notifier<SelectionState> {
  @override
  SelectionState build() {
    return const SelectionState();
  }

  void selectFurniture(String id) {
    state = state.copyWith(
      selectedFurnitureId: id,
      selectedElementType: 'furniture',
      clearPreviewMaterial: true,
    );
  }

  void selectElement(String type) {
    state = state.copyWith(
      selectedElementType: type,
      clearFurniture: type != 'furniture',
      clearPreviewMaterial: true,
    );
  }

  void setPreviewMaterial(MaterialModel? material) {
    state = state.copyWith(
      previewMaterial: material,
    );
  }

  void clearSelection() {
    state = const SelectionState();
  }
}

final selectionProvider = NotifierProvider<SelectionNotifier, SelectionState>(() {
  return SelectionNotifier();
});
