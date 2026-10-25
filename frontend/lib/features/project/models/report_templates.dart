class ReportTemplate {
  final String id;
  final String name;
  final String description;
  final String styleName; // e.g. Standard, Executive, Technical, Compact
  final String primaryColorHex;
  final String secondaryColorHex;
  final bool includeFloorPlan;

  ReportTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.styleName,
    required this.primaryColorHex,
    required this.secondaryColorHex,
    this.includeFloorPlan = true,
  });

  static List<ReportTemplate> get templates => [
        ReportTemplate(
          id: 'standard',
          name: 'Standard corporate',
          description: 'A clean, professional report layout with standard tables and colors.',
          styleName: 'Standard',
          primaryColorHex: '#1E3A8A', // Deep Blue
          secondaryColorHex: '#4B5563', // Grey
        ),
        ReportTemplate(
          id: 'executive',
          name: 'Executive overview',
          description: 'High-level summaries with vibrant accent color palettes for presentations.',
          styleName: 'Executive',
          primaryColorHex: '#0F766E', // Teal
          secondaryColorHex: '#0D9488', // Light Teal
        ),
        ReportTemplate(
          id: 'technical',
          name: 'Technical spec sheet',
          description: 'Granular measurements, strict layouts, and comprehensive checklists.',
          styleName: 'Technical',
          primaryColorHex: '#B91C1C', // Deep Red
          secondaryColorHex: '#7F1D1D', // Dark Red
        ),
        ReportTemplate(
          id: 'compact',
          name: 'Compact summary',
          description: 'Condensed spacing and tables suitable for printing and reference.',
          styleName: 'Compact',
          primaryColorHex: '#1F2937', // Charcoal
          secondaryColorHex: '#4B5563',
          includeFloorPlan: false,
        ),
      ];
}
