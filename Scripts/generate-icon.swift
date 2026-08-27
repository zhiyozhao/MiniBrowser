// MiniBrowser 图标生成器：极简小帆船（SF Symbols sailboat.fill）
// 白底 squircle（1024 画布 / 824 主体 / 圆角 185）+ 黑色帆船 + 悬浮投影
// 用法: swift Scripts/generate-icon.swift [输出.png]   默认 Resources/AppIcon.png
import AppKit

let S: CGFloat = 1024
let C: CGFloat = 512
let inset: CGFloat = 100
let bodyRect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)

let symbolName = "sailboat.fill"
let symbolPointSize: CGFloat = 380

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.png"

let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// ---- 白色 squircle 主体 ----
let sq = NSBezierPath(roundedRect: bodyRect, xRadius: 185, yRadius: 185)
sq.addClip()
NSGradient(colors: [.white, NSColor(calibratedRed: 0.945, green: 0.945, blue: 0.96, alpha: 1)])!
    .draw(in: sq, angle: -90)

// ---- 黑色帆船（SF Symbol 染黑）+ 悬浮投影 ----
let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .medium)
let sym = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!
    .withSymbolConfiguration(config)!
let tinted = NSImage(size: sym.size, flipped: false) { rect in
    NSColor.black.set()
    rect.fill()
    sym.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
    return true
}

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24,
              color: NSColor.black.withAlphaComponent(0.25).cgColor)
let w = tinted.size.width, h = tinted.size.height
tinted.draw(in: CGRect(x: C - w / 2, y: C - h / 2, width: w, height: h))
ctx.restoreGState()

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: outPath))
print("已生成 \(outPath)")
