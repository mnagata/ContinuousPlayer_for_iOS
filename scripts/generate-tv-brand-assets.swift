import AppKit
let output = CommandLine.arguments[1]
func path(_ commands: [(String, [CGFloat])]) -> CGPath {
 let p = CGMutablePath()
 for (op, v) in commands {
  switch op {
  case "M": p.move(to: CGPoint(x:v[0], y:v[1]))
  case "L": p.addLine(to: CGPoint(x:v[0], y:v[1]))
  case "Q": p.addQuadCurve(to: CGPoint(x:v[2], y:v[3]), control: CGPoint(x:v[0], y:v[1]))
  case "C": p.addCurve(to: CGPoint(x:v[4], y:v[5]), control1: CGPoint(x:v[0], y:v[1]), control2: CGPoint(x:v[2], y:v[3]))
  default: p.closeSubpath()
  }
 }
 return p
}
func color(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat) -> CGColor { CGColor(red:r/255,green:g/255,blue:b/255,alpha:1) }
let back = path([("M",[46,43]),("L",[46,29]),("Q",[46,26,49,27]),("L",[76,32]),("Q",[79,32.5,79,36]),("L",[79,55])])
let front = path([("M",[33,68]),("L",[33,39]),("Q",[33,36,36,37]),("L",[65,42]),("Q",[68,42.5,68,46]),("L",[68,66])])
let play = path([("M",[46,47]),("Q",[44,46,44,49]),("L",[44,62]),("Q",[44,65,46,64]),("L",[57,57]),("Q",[59,55.5,57,54]),("Z",[])])
let arrow = path([("M",[30,60]),("C",[24,77,44,87,74,64]),("L",[68,60]),("L",[82,60]),("L",[78,74]),("L",[76,68]),("C",[49,90,20,79,30,60]),("Z",[])])

let metadata: [String: Any] = ["author": "xcode", "version": 1]
func json(_ directory: String, _ values: [String: Any]) throws {
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    var values = values
    values["info"] = metadata
    try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
        .write(to: URL(fileURLWithPath: directory + "/Contents.json"))
}
func render(_ destination: String, width: Int, height: Int, background: Bool, symbol: Bool) throws {
 let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                     space: CGColorSpaceCreateDeviceRGB(),
                     bitmapInfo: (background ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
 if background {
     ctx.setFillColor(color(16,23,67))
     ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
 }
 if symbol {
 ctx.translateBy(x: CGFloat(width - height) / 2, y: CGFloat(height))
 ctx.scaleBy(x: CGFloat(height) / 108, y: -CGFloat(height) / 108)
 func gradient(_ p:CGPath,_ colors:[CGColor],_ start:CGPoint,_ end:CGPoint,_ stroke:Bool = false) {
  ctx.saveGState(); ctx.addPath(p)
  if stroke { ctx.setLineWidth(5); ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.replacePathWithStrokedPath() }
  ctx.clip()
  let g = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors as CFArray,locations:nil)!
  ctx.drawLinearGradient(g,start:start,end:end,options:[.drawsBeforeStartLocation,.drawsAfterEndLocation]); ctx.restoreGState()
 }
 gradient(back,[color(148,116,255),color(255,142,219)],CGPoint(x:46,y:28),CGPoint(x:79,y:52),true)
 gradient(front,[color(54,229,245),color(52,138,255)],CGPoint(x:33,y:37),CGPoint(x:68,y:68),true)
 ctx.addPath(play); ctx.setFillColor(CGColor(gray:1,alpha:1)); ctx.fillPath()
 gradient(arrow,[color(24,217,242),color(79,154,255),color(255,158,228)],CGPoint(x:28,y:77),CGPoint(x:80,y:60))

 }
 let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
 try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
}
try json(output, [:])
let brand = output + "/TVBrand.brandassets"
var assets: [[String: Any]] = []
for (name, width, height, scales) in [("Small", 400, 240, [1, 2]), ("Large", 1280, 768, [1])] {
 let stack = name + ".imagestack"
 assets.append(["idiom": "tv", "filename": stack, "role": "primary-app-icon", "size": "\(width)x\(height)"])
 try json(brand + "/" + stack, ["layers": [["filename": "Front.imagestacklayer"], ["filename": "Back.imagestacklayer"]]])
 for layer in ["Front", "Back"] {
  let directory = brand + "/" + stack + "/" + layer + ".imagestacklayer"
  try json(directory, [:])
  let content = directory + "/Content.imageset"
  try json(content, ["images": scales.map { ["idiom": "tv", "scale": "\($0)x", "filename": "image-\($0)x.png"] }])
  for scale in scales {
   try render(content + "/image-\(scale)x.png", width: width * scale, height: height * scale,
              background: layer == "Back", symbol: layer == "Front")
  }
 }
}
for (name, width, role) in [("TopShelf", 1920, "top-shelf-image"), ("TopShelfWide", 2320, "top-shelf-image-wide")] {
 let directory = brand + "/" + name + ".imageset"
 assets.append(["idiom": "tv", "filename": name + ".imageset", "role": role, "size": "\(width)x720"])
 try json(directory, ["images": [1, 2].map { ["idiom": "tv", "scale": "\($0)x", "filename": "image-\($0)x.png"] }])
 for scale in [1, 2] {
  try render(directory + "/image-\(scale)x.png", width: width * scale, height: 720 * scale, background: true, symbol: true)
 }
}
try json(brand, ["assets": assets])
