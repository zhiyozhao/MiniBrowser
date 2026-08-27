// MiniBrowser 图标生成器：Safari 图标的黑白复刻版
// 结构完全按 Safari 真实图标测量值复刻（256px 采样 → 等比放大）：
//   1024 画布 / 824 主体 / 圆角 185（Apple 官方模板）
//   表盘纯黑，半径 = 画布 34.8%
//   72 根白色刻度（每 5° 一根，长短交替），白色菱形指针（NE 半略长）
// 用法: swift Scripts/generate-icon.swift [输出.png]   默认 Resources/AppIcon.png
import AppKit

let S: CGFloat = 1024
let C: CGFloat = S / 2
let inset: CGFloat = 100
let bodyRect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)

let dialR: CGFloat = 349.5          // 表盘边线半径（内径与刻度外径间距 = 19.5，即原间距的 0.75 倍）
let tickW: CGFloat = 8             // 刻度宽
let longTick: (CGFloat, CGFloat) = (276, 324)   // 长刻度 0.775R~0.91R
let shortTick: (CGFloat, CGFloat) = (303, 324)  // 短刻度 0.85R~0.91R
let needleTip: CGFloat = 324        // 针尖：与刻度外径对齐
let needleTail: CGFloat = 324       // 针尾：与针尖等长
let needleHalfW: CGFloat = 36       // 针半宽（2 倍）

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.png"

let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// ---- 白色 squircle 主体 ----
let sq = NSBezierPath(roundedRect: bodyRect, xRadius: 185, yRadius: 185)
sq.addClip()
NSGradient(colors: [.white, NSColor(calibratedRed: 0.945, green: 0.945, blue: 0.96, alpha: 1)])!
    .draw(in: sq, angle: -90)

// ---- 表盘边线（黑色圆环，不填充） ----
NSColor.black.setStroke()
let ring = NSBezierPath(ovalIn: CGRect(x: C - dialR, y: C - dialR, width: dialR * 2, height: dialR * 2))
ring.lineWidth = 18
ring.stroke()

// ---- 黑色刻度：72 根，每 5° 一根，长短交替 ----
NSColor.black.setStroke()
for i in 0 ..< 72 {
    let deg = CGFloat(i) * 5
    let rad = deg * .pi / 180
    let (t1, t2) = i % 2 == 0 ? longTick : shortTick
    let dir = CGPoint(x: cos(rad), y: sin(rad))
    let p = NSBezierPath()
    p.move(to: CGPoint(x: C + dir.x * t1, y: C + dir.y * t1))
    p.line(to: CGPoint(x: C + dir.x * t2, y: C + dir.y * t2))
    p.lineWidth = tickW
    p.lineCapStyle = .butt
    p.stroke()
}

// ---- 指针（45° 朝东北）：两端式 + 悬浮投影 ----
let u = CGPoint(x: cos(CGFloat.pi / 4), y: sin(CGFloat.pi / 4))
let v = CGPoint(x: -u.y, y: u.x)
let tip = CGPoint(x: C + u.x * needleTip, y: C + u.y * needleTip)
let tail = CGPoint(x: C - u.x * needleTail, y: C - u.y * needleTail)
let right = CGPoint(x: C + v.x * needleHalfW, y: C + v.y * needleHalfW)
let left = CGPoint(x: C - v.x * needleHalfW, y: C - v.y * needleHalfW)

// 悬浮投影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28,
              color: NSColor.black.withAlphaComponent(0.38).cgColor)

// NE 半（纯黑）
let ne = NSBezierPath()
ne.move(to: tip); ne.line(to: right); ne.line(to: left); ne.close()
NSColor.black.setFill()
ne.fill()

// SW 半（深灰，与 NE 半区分为"另一端"）
let sw = NSBezierPath()
sw.move(to: tail); sw.line(to: left); sw.line(to: right); sw.close()
NSColor(calibratedWhite: 0.22, alpha: 1).setFill()
sw.fill()
ctx.restoreGState()

// 中心细白缝：强化"两端对接"的分界（宽度可用第二个参数调整，0 = 无缝）
let seamW: CGFloat = CommandLine.arguments.count > 2 ? CGFloat(Double(CommandLine.arguments[2]) ?? 0) : 0
if seamW > 0 {
    let seam = NSBezierPath()
    seam.move(to: left); seam.line(to: right)
    seam.lineWidth = seamW
    NSColor.white.setStroke()
    seam.stroke()
}

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: outPath))
print("已生成 \(outPath)")
