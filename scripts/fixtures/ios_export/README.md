# Exported iOS project fixture

Unmodified files from a real Godot 4.7.2 iOS project-only export of the game (preset "iPad",
plugin PhotoLibrary enabled), made on EC2 on 2026-10-07 with placeholders: team ID `ABCDE12345`,
bundle ID `org.example.lanternlane`. Used by `scripts/test_ios_photo_purpose.py`. It shows the two
export problems the tool fixes: an empty `NSPhotoLibraryUsageDescription` in the Info.plist and an
`InfoPlist.strings` variant group with only English.
