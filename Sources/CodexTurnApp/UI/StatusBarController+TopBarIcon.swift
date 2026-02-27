import AppKit

extension StatusBarController {
    func loadTopBarIcon() -> NSImage? {
        guard
            let iconURL = Bundle.module.url(forResource: "TopBarIcon", withExtension: "png"),
            let sourceImage = NSImage(contentsOf: iconURL),
            let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return nil
        }

        return makeTemplateMenuBarIcon(from: cgImage, pointSize: 16)
    }

    private func makeTemplateMenuBarIcon(from cgImage: CGImage, pointSize: CGFloat) -> NSImage? {
        let width = cgImage.width
        let height = cgImage.height
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let sourceContext = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ),
            let outputContext = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        else {
            return nil
        }

        sourceContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard
            let sourceData = sourceContext.data?.assumingMemoryBound(to: UInt8.self),
            let outputData = outputContext.data?.assumingMemoryBound(to: UInt8.self)
        else {
            return nil
        }

        let alphaThreshold: UInt8 = 220
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let alpha = sourceData[index + 3]

                if alpha >= alphaThreshold {
                    outputData[index] = 255
                    outputData[index + 1] = 255
                    outputData[index + 2] = 255
                    outputData[index + 3] = 255

                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                } else {
                    outputData[index] = 0
                    outputData[index + 1] = 0
                    outputData[index + 2] = 0
                    outputData[index + 3] = 0
                }
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return nil
        }

        let padding = 0
        let croppedRect = CGRect(
            x: max(0, minX - padding),
            y: max(0, minY - padding),
            width: min(width - max(0, minX - padding), (maxX - minX) + (padding * 2) + 1),
            height: min(height - max(0, minY - padding), (maxY - minY) + (padding * 2) + 1)
        )

        guard
            let thresholdedImage = outputContext.makeImage(),
            let croppedImage = thresholdedImage.cropping(to: croppedRect)
        else {
            return nil
        }

        let iconSize = NSSize(width: pointSize, height: pointSize)
        let preparedImage = NSImage(size: iconSize)
        let inset = max(3, Int(round(pointSize * 0.16)))
        let drawRect = NSRect(
            x: CGFloat(inset),
            y: CGFloat(inset),
            width: max(1, pointSize - CGFloat(inset * 2)),
            height: max(1, pointSize - CGFloat(inset * 2))
        )

        preparedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        NSImage(cgImage: croppedImage, size: iconSize).draw(
            in: drawRect,
            from: .zero,
            operation: .copy,
            fraction: 1
        )

        preparedImage.unlockFocus()
        preparedImage.isTemplate = true
        return preparedImage
    }
}
