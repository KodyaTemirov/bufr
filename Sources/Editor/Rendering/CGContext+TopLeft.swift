import CoreGraphics

extension CGContext {
    /// Draws `image` upright into `rect` of a context whose user space has a top-left origin
    /// (y down). A plain `draw` would come out upside down there.
    func drawImageTopLeft(_ image: CGImage, in rect: CGRect) {
        saveGState()
        translateBy(x: rect.minX, y: rect.maxY)
        scaleBy(x: 1, y: -1)
        draw(image, in: CGRect(origin: .zero, size: rect.size))
        restoreGState()
    }
}
