import XCTest
import PencilKit
import SwiftUI
import UIKit

final class CanvasBackgroundExportTests: XCTestCase {
    @MainActor
    func testDocumentCompositeKeepsReferenceInkAndCropInTheSameCoordinates() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let referenceBytes = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120), format: format).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
        }
        var document = CanvasDocument(background: .gray)
        document.referenceImage = try CanvasDocumentReference(data: referenceBytes, name: "Reference.png", sourceID: "thread/result")
        document.drawing = makeDrawing(ink: .black)
        document.exportBounds = CGRect(x: 40, y: 40, width: 120, height: 120)
        let pixels = try Pixels(data: XCTUnwrap(CanvasExporter().pngData(document: document)))
        XCTAssertEqual(pixels.width, 120)
        XCTAssertEqual(pixels.height, 120)
        assertRGB(pixels.at(x: 60, y: 60), matches: .black)
        assertRGB(pixels.at(x: 20, y: 60), matches: .red)
        assertRGB(pixels.at(x: 100, y: 20), matches: CanvasBackground.gray.uiColor)
    }

    @MainActor
    func testLargeExportAreaHasBoundedRasterDimensions() throws {
        var document = CanvasDocument(background: .white)
        document.exportBounds = CGRect(x: 0, y: 0, width: 8_192, height: 4_096)
        let pixels = try Pixels(data: XCTUnwrap(CanvasExporter().pngData(document: document)))
        XCTAssertEqual(pixels.width, 2_048)
        XCTAssertEqual(pixels.height, 1_024)
    }

    @MainActor
    func testBackgroundSelectionPreservesBlackAndWhiteInkInOpaquePNG() throws {
        let backgrounds: [UIColor] = [.white, .black, UIColor(red: 58 / 255, green: 86 / 255, blue: 120 / 255, alpha: 1)]
        for ink in [UIColor.black, UIColor.white] {
            let drawing = makeDrawing(ink: ink)
            let original = drawing.dataRepresentation()
            for background in backgrounds {
                let exported = try CanvasExporter().export(drawing: drawing, duration: 100, backgroundColor: background)
                let data = try XCTUnwrap(Data(base64Encoded: exported.imageBase64))
                let pixels = try Pixels(data: data)
                let stroke = pixels.at(x: pixels.width / 2, y: pixels.height / 2)
                let paper = pixels.at(x: pixels.width / 2, y: pixels.height / 8)
                assertRGB(stroke, matches: ink)
                assertRGB(paper, matches: background)
                XCTAssertTrue(pixels.bytes.enumerated().allSatisfy { $0.offset % 4 != 3 || $0.element == 255 })
                XCTAssertEqual(drawing.dataRepresentation(), original, "Changing the background must not rewrite ink.")
            }
        }
    }

    @MainActor
    func testExportUsesFixedInkColorsRegardlessOfSystemAppearance() throws {
        let drawing = makeDrawing(ink: .white)
        var lightData: Data?
        var darkData: Data?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            lightData = drawing.exportPNG(backgroundColor: .black)
        }
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            darkData = drawing.exportPNG(backgroundColor: .black)
        }
        let light = try Pixels(data: XCTUnwrap(lightData))
        let dark = try Pixels(data: XCTUnwrap(darkData))
        XCTAssertEqual(light.width, dark.width)
        XCTAssertEqual(light.height, dark.height)
        XCTAssertEqual(light.bytes, dark.bytes)
        assertRGB(dark.at(x: dark.width / 2, y: dark.height / 2), matches: .white)
        assertRGB(dark.at(x: dark.width / 2, y: dark.height / 8), matches: .black)
    }

    @MainActor
    func testLegacyExportDefaultsToOpaqueWhiteAndCustomBackgroundIsOpaque() throws {
        let drawing = makeDrawing(ink: .black)
        let pixels = try Pixels(data: XCTUnwrap(drawing.exportPNG()))
        assertRGB(pixels.at(x: pixels.width / 2, y: pixels.height / 8), matches: .white)

        let custom = CanvasBackground(color: UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.25))
        let restored = try XCTUnwrap(CanvasBackground(rawValue: custom.rawValue))
        let customPixels = try Pixels(data: XCTUnwrap(drawing.exportPNG(backgroundColor: restored.uiColor)))
        assertRGB(customPixels.at(x: customPixels.width / 2, y: customPixels.height / 8), matches: UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        XCTAssertTrue(customPixels.bytes.enumerated().allSatisfy { $0.offset % 4 != 3 || $0.element == 255 })
    }

    @MainActor
    func testInterfaceSwitchPreservesSelectedInkAndExistingDrawing() throws {
        for ink in [UIColor.black, UIColor.white] {
            let canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 240, height: 240))
            let toolPicker = PKToolPicker()
            CanvasAppearance.apply(.light, to: canvas, toolPicker: toolPicker)
            toolPicker.addObserver(canvas)
            defer { toolPicker.removeObserver(canvas) }

            let selectedTool = PKInkingTool(.pen, color: ink, width: 7)
            toolPicker.selectedTool = selectedTool
            canvas.drawing = makeDrawing(ink: ink)
            let originalDrawing = canvas.drawing.dataRepresentation()

            for scheme in [ColorScheme.dark, .light, .dark] {
                CanvasAppearance.apply(scheme, to: canvas, toolPicker: toolPicker)
                canvas.backgroundColor = scheme == .dark ? CanvasBackground.charcoal.uiColor : .white

                XCTAssertEqual(toolPicker.overrideUserInterfaceStyle, scheme == .dark ? .dark : .light)
                XCTAssertEqual(toolPicker.colorUserInterfaceStyle, .light, "Picker appearance must not change how ink colors are interpreted.")
                XCTAssertEqual(canvas.overrideUserInterfaceStyle, .light)
                let activeTool = try XCTUnwrap(toolPicker.selectedTool as? PKInkingTool)
                XCTAssertEqual(activeTool, selectedTool, "Switching appearance must preserve the chosen tool, color, and width.")
                XCTAssertEqual(canvas.drawing.dataRepresentation(), originalDrawing)

                let pixels = try Pixels(data: XCTUnwrap(canvas.drawing.exportPNG(backgroundColor: XCTUnwrap(canvas.backgroundColor))))
                assertRGB(pixels.at(x: pixels.width / 2, y: pixels.height / 2), matches: ink)
                assertRGB(pixels.at(x: pixels.width / 2, y: pixels.height / 8), matches: try XCTUnwrap(canvas.backgroundColor))
            }
        }
    }

    private func makeDrawing(ink: UIColor) -> PKDrawing {
        let points = [20, 40, 60, 80, 100].enumerated().map { index, position in
            PKStrokePoint(
                location: CGPoint(x: position, y: position),
                timeOffset: Double(index) * 0.1,
                size: CGSize(width: 16, height: 16),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_700_000_000))
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: ink), path: path)])
    }

    private func assertRGB(_ pixel: [UInt8], matches color: UIColor, file: StaticString = #filePath, line: UInt = #line) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        for (actual, expected) in zip(pixel.prefix(3), [red, green, blue]) {
            XCTAssertEqual(Double(actual), Double(expected * 255), accuracy: 2, file: file, line: line)
        }
        XCTAssertEqual(pixel[3], 255, file: file, line: line)
    }

    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init(data: Data) throws {
            let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
            let width = image.width
            let height = image.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            try buffer.withUnsafeMutableBytes { storage in
                let context = try XCTUnwrap(CGContext(
                    data: storage.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            self.width = width
            self.height = height
            bytes = buffer
        }

        func at(x: Int, y: Int) -> [UInt8] {
            Array(bytes[(y * width + x) * 4..<(y * width + x + 1) * 4])
        }
    }
}
