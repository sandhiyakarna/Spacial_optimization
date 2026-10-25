class MaterialCategory {
  final String id;
  final String name;
  final DateTime createdAt;

  MaterialCategory({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory MaterialCategory.fromJson(Map<String, dynamic> json) {
    return MaterialCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'created_at': createdAt.toIso8601String(),
  };
}

class MaterialTexture {
  final String id;
  final String materialId;
  final String textureType;
  final String filePath;
  final DateTime createdAt;

  MaterialTexture({
    required this.id,
    required this.materialId,
    required this.textureType,
    required this.filePath,
    required this.createdAt,
  });

  factory MaterialTexture.fromJson(Map<String, dynamic> json) {
    return MaterialTexture(
      id: json['id'] as String,
      materialId: json['material_id'] as String,
      textureType: json['texture_type'] as String,
      filePath: json['file_path'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'material_id': materialId,
    'texture_type': textureType,
    'file_path': filePath,
    'created_at': createdAt.toIso8601String(),
  };
}

class MaterialModel {
  final String id;
  final String name;
  final String categoryId;
  final String? baseColor;
  final String? previewImage;
  final double opacity;
  final double reflectivity;
  final double defaultScale;
  final DateTime createdAt;
  final MaterialCategory category;
  final List<MaterialTexture> textures;

  MaterialModel({
    required this.id,
    required this.name,
    required this.categoryId,
    this.baseColor,
    this.previewImage,
    required this.opacity,
    required this.reflectivity,
    required this.defaultScale,
    required this.createdAt,
    required this.category,
    required this.textures,
  });

  factory MaterialModel.fromJson(Map<String, dynamic> json) {
    return MaterialModel(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryId: json['category_id'] as String,
      baseColor: json['base_color'] as String?,
      previewImage: json['preview_image'] as String?,
      opacity: (json['opacity'] as num? ?? 1.0).toDouble(),
      reflectivity: (json['reflectivity'] as num? ?? 0.0).toDouble(),
      defaultScale: (json['default_scale'] as num? ?? 1.0).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      category: MaterialCategory.fromJson(json['category'] as Map<String, dynamic>),
      textures: (json['textures'] as List<dynamic>? ?? [])
          .map((t) => MaterialTexture.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category_id': categoryId,
    'base_color': baseColor,
    'preview_image': previewImage,
    'opacity': opacity,
    'reflectivity': reflectivity,
    'default_scale': defaultScale,
    'created_at': createdAt.toIso8601String(),
    'category': category.toJson(),
    'textures': textures.map((t) => t.toJson()).toList(),
  };
}
