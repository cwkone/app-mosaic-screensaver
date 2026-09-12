import AppKit

// Finder treats .saver bundles as documents and ignores CFBundleIconFile.
// Apply its native custom-file icon after signing, without changing code.
guard CommandLine.arguments.count == 3,
      let image = NSImage(contentsOfFile: CommandLine.arguments[2]),
      NSWorkspace.shared.setIcon(image, forFile: CommandLine.arguments[1], options: []) else {
    FileHandle.standardError.write(Data("Could not apply the screensaver Finder icon.\n".utf8))
    exit(1)
}
