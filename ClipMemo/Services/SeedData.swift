import AppKit
import UniformTypeIdentifiers

extension HistoryStore {

    /// Seeds a few realistic records on first launch so the UI is immediately meaningful.
    func seedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "didSeedHistory") else { return }
        UserDefaults.standard.set(true, forKey: "didSeedHistory")

        let cal = Calendar.current
        func today(_ h: Int, _ m: Int) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
        }
        func daysAgo(_ d: Int, _ h: Int, _ m: Int) -> Date {
            let day = cal.date(byAdding: .day, value: -d, to: Date()) ?? Date()
            return cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
        }

        var seeds: [ClipboardItem] = []

        // Text
        seeds.append(ClipboardItem(
            type: .text,
            text: "Clean, minimal, and powerful clipboard history.\nDesigned for productivity.",
            createdAt: today(10, 24)
        ))
        seeds.append(ClipboardItem(
            type: .text,
            text: "team@studio.design\nReach out anytime between 9:00 and 18:00.",
            createdAt: today(9, 15)
        ))
        seeds.append(ClipboardItem(
            type: .text,
            text: "Meeting moved to 3:30 PM in Room 4.\nBring the quarterly numbers.",
            isPinned: true,
            createdAt: daysAgo(1, 14, 2)
        ))

        // Code
        let snippet = """
        func formatDuration(_ seconds: Int) -> String {
            let minutes = seconds / 60
            let remaining = seconds % 60
            return String(format: "%02d:%02d", minutes, remaining)
        }
        """
        seeds.append(ClipboardItem(
            type: .code,
            text: snippet,
            createdAt: today(8, 47)
        ))

        // Image (drawn programmatically: "Scenic view of mountains")
        var imageBytesByID: [UUID: Data] = [:]
        if let png = Self.scenicMountainsPNG() {
            let imageItem = ClipboardItem(
                type: .image,
                fileName: "Scenic view of mountains",
                fileKind: "PNG Image",
                fileSize: Int64(png.count),
                createdAt: today(10, 2)
            )
            imageBytesByID[imageItem.id] = png
            seeds.append(imageItem)
        }

        // Files
        seeds.append(ClipboardItem(
            type: .file,
            fileName: "Project Roadmap.pdf",
            fileKind: "PDF Document",
            fileSize: 2_417_664,
            fileURLPath: "/Users/\(NSFullUserName())/Documents/Project Roadmap.pdf",
            createdAt: daysAgo(1, 16, 40)
        ))
        seeds.append(ClipboardItem(
            type: .file,
            fileName: "Q3-Budget.xlsx",
            fileKind: "Excel Spreadsheet",
            fileSize: 386_758,
            fileURLPath: "/Users/\(NSFullUserName())/Downloads/Q3-Budget.xlsx",
            createdAt: daysAgo(3, 11, 5)
        ))
        seeds.append(ClipboardItem(
            type: .file,
            fileName: "AppIcon.sketch",
            fileKind: "Sketch Document",
            fileSize: 1_884_160,
            fileURLPath: "/Users/\(NSFullUserName())/Design/AppIcon.sketch",
            createdAt: daysAgo(9, 19, 21)
        ))

        replaceAll(with: seeds, imageBytesByID: imageBytesByID)
    }

    /// Draws a small stylized mountain landscape and returns PNG data.
    private static func scenicMountainsPNG() -> Data? {
        let size = NSSize(width: 360, height: 224)
        let image = NSImage(size: size)
        image.lockFocus()

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return nil
        }

        // Sky gradient
        let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [NSColor(calibratedRed: 0.55, green: 0.72, blue: 0.96, alpha: 1).cgColor,
                                      NSColor(calibratedRed: 0.86, green: 0.92, blue: 0.99, alpha: 1).cgColor] as CFArray,
                             locations: [0, 1])!
        ctx.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

        // Sun
        ctx.setFillColor(NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.75, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: 250, y: 138, width: 44, height: 44))

        func mountain(_ baseY: CGFloat, _ peak: CGFloat, _ left: CGFloat, _ width: CGFloat, _ color: NSColor) {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: left, y: baseY))
            path.addLine(to: CGPoint(x: left + width / 2, y: peak))
            path.addLine(to: CGPoint(x: left + width, y: baseY))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.setFillColor(color.cgColor)
            ctx.fillPath()
        }

        mountain(84, 176, 8, 190, NSColor(calibratedRed: 0.42, green: 0.52, blue: 0.72, alpha: 1))
        mountain(70, 150, 120, 200, NSColor(calibratedRed: 0.55, green: 0.64, blue: 0.82, alpha: 1))
        mountain(60, 132, 220, 160, NSColor(calibratedRed: 0.68, green: 0.76, blue: 0.90, alpha: 1))

        // Snow caps
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        let cap = CGMutablePath()
        cap.move(to: CGPoint(x: 103, y: 176))
        cap.addLine(to: CGPoint(x: 90, y: 152))
        cap.addLine(to: CGPoint(x: 116, y: 152))
        cap.closeSubpath()
        cap.move(to: CGPoint(x: 220, y: 150))
        cap.addLine(to: CGPoint(x: 208, y: 128))
        cap.addLine(to: CGPoint(x: 232, y: 128))
        cap.closeSubpath()
        ctx.addPath(cap)
        ctx.fillPath()

        // Foreground
        ctx.setFillColor(NSColor(calibratedRed: 0.30, green: 0.46, blue: 0.42, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: 64))

        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return png
    }
}
