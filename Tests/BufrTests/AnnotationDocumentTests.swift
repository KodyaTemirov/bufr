import CoreGraphics
import Foundation
import Testing
@testable import Bufr

struct AnnotationDocumentTests {
    let style = AnnotationStyle(color: .red, lineWidth: 6, fontSize: 32)

    private func document(_ shapes: [AnnotationShape]) -> AnnotationDocument {
        AnnotationDocument(
            baseImageFilename: "A_orig.png", pixelWidth: 200, pixelHeight: 100, pointScale: 2,
            annotations: shapes.map { Annotation(shape: $0, style: style) }
        )
    }

    @Test func everyShapeRoundTripsThroughJSON() throws {
        let original = document([
            .arrow(start: CGPoint(x: 1, y: 2), end: CGPoint(x: 30, y: 40)),
            .line(start: .zero, end: CGPoint(x: 5, y: 5)),
            .rectangle(CGRect(x: 1, y: 2, width: 3, height: 4)),
            .filledRectangle(CGRect(x: 5, y: 6, width: 7, height: 8)),
            .ellipse(CGRect(x: 0, y: 0, width: 10, height: 20)),
            .text(origin: CGPoint(x: 10, y: 10), string: "Привет"),
            .highlighter(CGRect(x: 0, y: 50, width: 100, height: 12)),
            .pencil([CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 4)]),
            .counter(center: CGPoint(x: 50, y: 50), number: 3),
            .pixelate(CGRect(x: 10, y: 10, width: 40, height: 20)),
            .blur(CGRect(x: 60, y: 10, width: 40, height: 20)),
            .spotlight(CGRect(x: 20, y: 20, width: 60, height: 40)),
        ])
        var withCrop = original
        withCrop.crop = CGRect(x: 10, y: 10, width: 100, height: 50)

        let data = try JSONEncoder().encode(withCrop)
        let decoded = try JSONDecoder().decode(AnnotationDocument.self, from: data)

        #expect(decoded == withCrop)
    }

    /// Files written by this version must keep opening in later versions.
    @Test func decodesVersionOneFormat() throws {
        let json = """
        {"version":1,"baseImageFilename":"A_orig.png","pixelWidth":200,"pixelHeight":100,"pointScale":2,
         "annotations":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF",
           "shape":{"arrow":{"start":[1,2],"end":[30,40]}},
           "style":{"color":{"red":1,"green":0,"blue":0,"alpha":1},"lineWidth":6,"fontSize":32}}]}
        """

        let decoded = try JSONDecoder().decode(AnnotationDocument.self, from: Data(json.utf8))

        #expect(decoded.annotations.first?.shape == .arrow(start: CGPoint(x: 1, y: 2), end: CGPoint(x: 30, y: 40)))
        #expect(decoded.crop == nil)
        #expect(decoded.outputSize == CGSize(width: 200, height: 100))
    }

    @Test func nextCounterNumberFollowsTheHighest() {
        var doc = document([.counter(center: .zero, number: 1), .counter(center: .zero, number: 4)])
        #expect(doc.nextCounterNumber == 5)

        doc.annotations = []
        #expect(doc.nextCounterNumber == 1)
    }

    @Test func duplicateCreatesShiftedCopiesWithNewIds() {
        var doc = document([.rectangle(CGRect(x: 10, y: 10, width: 20, height: 20))])
        let originalId = doc.annotations[0].id

        let copies = doc.duplicate(ids: [originalId], offset: 12)

        #expect(doc.annotations.count == 2)
        #expect(copies.count == 1 && copies[0] != originalId)
        #expect(doc.annotations[1].shape == .rectangle(CGRect(x: 22, y: 22, width: 20, height: 20)))
    }

    @Test func removeDeletesOnlyGivenIds() {
        var doc = document([.line(start: .zero, end: CGPoint(x: 1, y: 1)), .line(start: .zero, end: CGPoint(x: 2, y: 2))])
        let keep = doc.annotations[1].id

        doc.remove(ids: [doc.annotations[0].id])

        #expect(doc.annotations.map(\.id) == [keep])
    }

    @Test func cropDefinesOutputSize() {
        var doc = document([])
        doc.crop = CGRect(x: 5, y: 5, width: 50, height: 40)

        #expect(doc.outputSize == CGSize(width: 50, height: 40))
    }
}
