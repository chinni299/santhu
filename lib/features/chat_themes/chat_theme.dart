enum ChatThemeMode {
  defaultTheme('Default', 'Classic Teal & Dark background', null),
  love('Love', 'Romantic Warm Rose & Gold', 0xFFFF4B6E),
  dark('Dark', 'Pure OLED Dark Mode', 0xFF121212),
  midnight('Midnight', 'Deep Cosmos Indigo', 0xFF0D1B2A),
  pink('Soft Pink', 'Blush Pastel Pink', 0xFFFFB7B2),
  minimal('Minimal', 'Clean Slate Charcoal', 0xFF2C3E50),
  customWallpaper('Custom Wallpaper', 'Image from device storage', null);

  final String label;
  final String description;
  final int? primaryColorValue;

  const ChatThemeMode(this.label, this.description, this.primaryColorValue);

  static ChatThemeMode fromString(String? name) {
    if (name == null) return ChatThemeMode.defaultTheme;
    return ChatThemeMode.values.firstWhere(
      (e) => e.name == name,
      orElse: () => ChatThemeMode.defaultTheme,
    );
  }
}
