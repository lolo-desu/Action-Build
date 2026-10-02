import Foundation
import AVFoundation
import CoreVideo

// Examine the simulator's actual displayed frames, including UIKit overlays.
let url=URL(fileURLWithPath:CommandLine.arguments[1])
let asset=AVURLAsset(url:url)
let track=asset.tracks(withMediaType:.video).first!
let reader=try AVAssetReader(asset:asset)
let output=AVAssetReaderTrackOutput(track:track,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
reader.add(output)
guard reader.startReading() else { fatalError("Cannot decode simulator video: \(String(describing: reader.error))") }
let palette:[(String,[Int])]=[("list",[23,105,170]),("chat",[198,40,40]),("profile",[230,81,0])]
var sequence:[String]=[],counts:[String:Int]=[:],frames=0
while let sample=output.copyNextSampleBuffer(),let buffer=CMSampleBufferGetImageBuffer(sample) {
    CVPixelBufferLockBaseAddress(buffer,.readOnly)
    let width=CVPixelBufferGetWidth(buffer),height=CVPixelBufferGetHeight(buffer),stride=CVPixelBufferGetBytesPerRow(buffer)
    let pointer=CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to:UInt8.self)
    let offset=(height/2)*stride+(width/2)*4
    let rgb=[Int(pointer[offset+2]),Int(pointer[offset+1]),Int(pointer[offset])]
    CVPixelBufferUnlockBaseAddress(buffer,.readOnly)
    frames += 1
    if let color=palette.first(where:{zip($0.1,rgb).reduce(0){$0+abs($1.0-$1.1)}<40}) {
        counts[color.0,default:0] += 1
        if sequence.last != color.0 { sequence.append(color.0) }
    }
}
guard reader.status == .completed else { fatalError("Video reading failed: \(String(describing:reader.error))") }
let report:[String:Any]=["sequence":sequence,"coloredFrames":counts,"frames":frames]
let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
try data.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
print(String(data:data,encoding:.utf8)!)
guard sequence == ["list","chat","profile","chat","list"],counts.values.allSatisfy({$0>=3}) else { fatalError("Displayed page flashed or skipped a level: \(sequence)") }
print("PASS: actual simulator video shows one parent handoff per return, without child reappearance or grandparent flashes")
