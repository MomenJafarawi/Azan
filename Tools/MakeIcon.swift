import AppKit

// Draws the app icon: golden crescent over a sunset sky, dome silhouette, faint stars.
let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon1024.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

// shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill(); shape.fill()
ctx.restoreGState()

shape.addClip()
// sky: night blue at top, violet, warm orange at the horizon
let sky = NSGradient(colorsAndLocations:
    (NSColor(red: 0.06, green: 0.08, blue: 0.24, alpha: 1), 0.0),
    (NSColor(red: 0.27, green: 0.18, blue: 0.45, alpha: 1), 0.45),
    (NSColor(red: 0.85, green: 0.38, blue: 0.36, alpha: 1), 0.78),
    (NSColor(red: 0.99, green: 0.66, blue: 0.33, alpha: 1), 1.0))!
sky.draw(in: rect, angle: -90)

// stars
var seed: UInt64 = 42
func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1) }
for _ in 0..<45 {
    let x = rect.minX + rnd() * rect.width, y = rect.midY + rnd() * rect.height * 0.5
    let r = 1.5 + rnd() * 3.5
    NSColor.white.withAlphaComponent(0.35 + rnd() * 0.5).setFill()
    NSBezierPath(ovalIn: CGRect(x: x, y: y, width: r, height: r)).fill()
}

// crescent (gold, with glow)
let gold = NSColor(red: 0.99, green: 0.82, blue: 0.45, alpha: 1)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 60, color: gold.withAlphaComponent(0.7).cgColor)
let moonCenter = CGPoint(x: 560, y: 600)
let outer = NSBezierPath(ovalIn: CGRect(x: moonCenter.x - 190, y: moonCenter.y - 190, width: 380, height: 380))
let cut = NSBezierPath(ovalIn: CGRect(x: moonCenter.x - 105, y: moonCenter.y - 120, width: 350, height: 350))
let crescent = NSBezierPath()
crescent.append(outer)
crescent.append(cut.reversed)
crescent.windingRule = .evenOdd
ctx.saveGState()
outer.addClip()
let goldGrad = NSGradient(starting: NSColor(red: 1.0, green: 0.90, blue: 0.62, alpha: 1), ending: NSColor(red: 0.93, green: 0.66, blue: 0.25, alpha: 1))!
goldGrad.draw(in: crescent, angle: -60)
ctx.restoreGState()
ctx.restoreGState()

// small star beside the crescent
func star(_ c: CGPoint, _ r: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    for i in 0..<10 {
        let a = CGFloat(i) * .pi / 5 + .pi / 2
        let rr = i % 2 == 0 ? r : r * 0.42
        let pt = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
        i == 0 ? p.move(to: pt) : p.line(to: pt)
    }
    p.close(); return p
}
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 25, color: gold.cgColor)
gold.setFill(); star(CGPoint(x: 700, y: 640), 46).fill()
ctx.restoreGState()

// dome + minarets silhouette
let sil = NSColor(red: 0.10, green: 0.07, blue: 0.20, alpha: 0.92)
sil.setFill()
let base = NSBezierPath(rect: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 150))
base.fill()
let dome = NSBezierPath()
dome.move(to: CGPoint(x: 380, y: 250))
dome.curve(to: CGPoint(x: 512, y: 410), controlPoint1: CGPoint(x: 380, y: 340), controlPoint2: CGPoint(x: 450, y: 395))
dome.curve(to: CGPoint(x: 644, y: 250), controlPoint1: CGPoint(x: 574, y: 395), controlPoint2: CGPoint(x: 644, y: 340))
dome.close(); dome.fill()
NSBezierPath(rect: CGRect(x: 360, y: 150, width: 304, height: 105)).fill()
NSBezierPath(rect: CGRect(x: 507, y: 405, width: 10, height: 40)).fill()
for x in [260.0, 734.0] {
    NSBezierPath(rect: CGRect(x: x, y: 150, width: 30, height: 270)).fill()
    let cap = NSBezierPath()
    cap.move(to: CGPoint(x: x - 6, y: 420)); cap.line(to: CGPoint(x: x + 15, y: 470)); cap.line(to: CGPoint(x: x + 36, y: 420)); cap.close(); cap.fill()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("icon written:", out)
