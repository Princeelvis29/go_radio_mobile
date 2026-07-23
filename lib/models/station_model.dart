class Station {
  final int id;
  final String name;
  final String tagline;
  final String description;
  final String streamUrl;
  final String coverArt;
  final String category;
  final bool isActive;

  Station({
    required this.id,
    required this.name,
    required this.tagline,
    required this.description,
    required this.streamUrl,
    required this.coverArt,
    required this.category,
    required this.isActive,
  });

  factory Station.fromJson(Map<String, dynamic> json) {
    return Station(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Unknown Station',
      tagline: json['tagline'] ?? '',
      description: json['description'] ?? 'No description available.',
      streamUrl: json['stream_url'] ?? '',
      coverArt: json['cover_art'] ?? 'assets/images/default_cover.png',
      category: json['category'] ?? 'Uncategorized',
      isActive: json['is_active'] ?? true, // Defaults to true so stations show up
    );
  }
}