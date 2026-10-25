class FurnitureCategory {
  final String id;
  final String name;
  final String? description;
  final String? parentId;

  FurnitureCategory({
    required this.id,
    required this.name,
    this.description,
    this.parentId,
  });

  factory FurnitureCategory.fromJson(Map<String, dynamic> json) {
    return FurnitureCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      parentId: json['parent_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'parent_id': parentId,
    };
  }
}

class FurnitureAsset {
  final String id;
  final String name;
  final String category;
  final String? subcategory;
  final String style;
  final double width;
  final double depth;
  final double height;
  final double clearance;
  final double assemblyClearance;
  final String? tags;
  final String glbUrl;
  final String thumbnailUrl;
  final String? previewUrl;
  final DateTime createdAt;
  final bool isFavorite;

  FurnitureAsset({
    required this.id,
    required this.name,
    required this.category,
    this.subcategory,
    required this.style,
    required this.width,
    required this.depth,
    required this.height,
    required this.clearance,
    required this.assemblyClearance,
    this.tags,
    required this.glbUrl,
    required this.thumbnailUrl,
    this.previewUrl,
    required this.createdAt,
    this.isFavorite = false,
  });

  factory FurnitureAsset.fromJson(Map<String, dynamic> json) {
    return FurnitureAsset(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      subcategory: json['subcategory'] as String?,
      style: json['style'] as String,
      width: (json['width'] as num).toDouble(),
      depth: (json['depth'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      clearance: (json['clearance'] as num? ?? 0.0).toDouble(),
      assemblyClearance: (json['assembly_clearance'] as num? ?? 0.0).toDouble(),
      tags: json['tags'] as String?,
      glbUrl: json['glb_url'] as String? ?? '',
      thumbnailUrl: json['thumbnail_url'] as String? ?? '',
      previewUrl: json['preview_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      isFavorite: json['is_favorite'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'subcategory': subcategory,
      'style': style,
      'width': width,
      'depth': depth,
      'height': height,
      'clearance': clearance,
      'assembly_clearance': assemblyClearance,
      'tags': tags,
      'glb_url': glbUrl,
      'thumbnail_url': thumbnailUrl,
      'preview_url': previewUrl,
      'created_at': createdAt.toIso8601String(),
      'is_favorite': isFavorite,
    };
  }

  FurnitureAsset copyWith({
    String? id,
    String? name,
    String? category,
    String? subcategory,
    String? style,
    double? width,
    double? depth,
    double? height,
    double? clearance,
    double? assemblyClearance,
    String? tags,
    String? glbUrl,
    String? thumbnailUrl,
    String? previewUrl,
    DateTime? createdAt,
    bool? isFavorite,
  }) {
    return FurnitureAsset(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      style: style ?? this.style,
      width: width ?? this.width,
      depth: depth ?? this.depth,
      height: height ?? this.height,
      clearance: clearance ?? this.clearance,
      assemblyClearance: assemblyClearance ?? this.assemblyClearance,
      tags: tags ?? this.tags,
      glbUrl: glbUrl ?? this.glbUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      previewUrl: previewUrl ?? this.previewUrl,
      createdAt: createdAt ?? this.createdAt,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}
