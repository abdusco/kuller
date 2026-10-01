import SwiftUI
import ImageIO

struct ImageProperties {
    let name: String
    let dimensions: String
    let created: String
    let modified: String

    init(item: ImageItem, cropRect: NormalizedRect?) {
        name = item.displayName
        let values = try? item.url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        created = values?.creationDate?.formatted(date: .abbreviated, time: .standard) ?? "Unavailable"
        modified = values?.contentModificationDate?.formatted(date: .abbreviated, time: .standard) ?? "Unavailable"

        if let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
           let height = properties[kCGImagePropertyPixelHeight] as? NSNumber {
            let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            let swapsAxes = (5...8).contains(orientation)
            let size = CGSize(width: swapsAxes ? height.doubleValue : width.doubleValue,
                              height: swapsAxes ? width.doubleValue : height.doubleValue)
            let rect = cropRect ?? .fullImage
            let pixels = CGRect(x: rect.x * size.width,
                                y: (1 - rect.y - rect.height) * size.height,
                                width: rect.width * size.width,
                                height: rect.height * size.height)
                .integral.intersection(CGRect(origin: .zero, size: size))
            dimensions = "\(Int(pixels.width)) × \(Int(pixels.height)) px"
        } else {
            dimensions = "Unavailable"
        }
    }
}

struct ImagePropertiesView: View {
    let properties: ImageProperties

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(properties.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .truncationMode(.middle)
            Text(properties.dimensions)
            Text("Created: \(properties.created)")
            Text("Modified: \(properties.modified)")
        }
        .font(.system(size: 11))
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 320, alignment: .trailing)
        .padding(12)
        .allowsHitTesting(false)
    }
}
