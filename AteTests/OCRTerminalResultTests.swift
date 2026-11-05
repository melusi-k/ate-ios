import XCTest
import UIKit
@testable import Ate

final class OCRTerminalResultTests: XCTestCase {
    func testSuccessfulWorkerReturnsText() async throws {
        let text = try await OCRTerminalResult.run(timeout: 1) { finish in
            finish(.success("Pancakes\n200 g flour\n2 eggs"))
        }
        XCTAssertEqual(text, "Pancakes\n200 g flour\n2 eggs")
    }

    func testWorkerFailurePropagatesInsteadOfBecomingEmptyOCR() async {
        struct Failed: Error {}
        do {
            _ = try await OCRTerminalResult.run(timeout: 1) { finish in
                finish(.failure(Failed()))
            }
            XCTFail("OCR failure must leave the attempt in an actionable error state")
        } catch {
            XCTAssertTrue(error is Failed)
        }
    }

    func testWorkerThatNeverCompletesReachesFriendlyDeadline() async {
        do {
            _ = try await OCRTerminalResult.run(timeout: 0) { _ in }
            XCTFail("A stalled worker must not leave generation loading indefinitely")
        } catch {
            XCTAssertTrue(error is OCRTerminalResult.DeadlineExceeded)
            XCTAssertTrue(error.localizedDescription.contains("Try again"))
        }
    }

    func testLateSuccessAndFailureCannotCompleteTwice() {
        let completed = expectation(description: "one terminal result")
        completed.assertForOverFulfill = true
        let terminal = OCRTerminalResult { result in
            guard case .failure(let error) = result else {
                XCTFail("The first terminal result must win")
                return
            }
            XCTAssertTrue(error is OCRTerminalResult.DeadlineExceeded)
            completed.fulfill()
        }
        terminal.finish(.failure(OCRTerminalResult.DeadlineExceeded()))
        terminal.finish(.success("late text"))
        terminal.finish(.failure(OCRTerminalResult.DeadlineExceeded()))
        wait(for: [completed], timeout: 1)
    }

    func testDeadlineRequestsWorkerCancellation() async {
        let cancelled = expectation(description: "Vision cancellation requested")
        do {
            _ = try await OCRTerminalResult.run(timeout: 0, cancel: { cancelled.fulfill() }) { _ in }
            XCTFail("Expected the deadline")
        } catch { XCTAssertTrue(error is OCRTerminalResult.DeadlineExceeded) }
        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testCancellationBeforeWorkerRegistersStillCancelsRequest() {
        let cancellation = OCRRequestCancellation()
        let cancelled = expectation(description: "late request receives cancellation")
        cancellation.cancel()
        cancellation.install { cancelled.fulfill() }
        wait(for: [cancelled], timeout: 1)
    }

    @MainActor func testRecoveryImageDoesNotMultiplyOCRPixelsByScreenScale() throws {
        let source = try XCTUnwrap(AddRecipeSheet.sampleImage())
        let data = try XCTUnwrap(AddRecipeSheet.recoverableJPEG(from: source))
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(image.width, 800)
        XCTAssertEqual(image.height, 600)
        XCTAssertLessThanOrEqual(data.count, 1_500_000)
    }

    @MainActor func testTallScreenshotKeepsTextWidthWithinRecoveryByteLimit() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1170, height: 2532), format: format).pngData { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1170, height: 2532))
            ("Ingredients: 200 g flour, 2 eggs" as NSString).draw(at: CGPoint(x: 40, y: 120),
                withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black])
        }
        let data = try XCTUnwrap(AddRecipeSheet.recoverableJPEG(from: source))
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(image.height, 2048)
        XCTAssertGreaterThanOrEqual(image.width, 940, "Tall recipe screenshots retain useful text width")
        XCTAssertLessThanOrEqual(data.count, 1_500_000)
    }
    @MainActor func testPreviewAndCoverKeepOriginalBytesWhileRecoveryIsCompressed() throws {
        let original = try XCTUnwrap(AddRecipeSheet.sampleImage())
        let prepared = AddRecipeSheet.prepareImage(original)
        XCTAssertEqual(prepared.previewAndCover, original)
        XCTAssertNotEqual(prepared.requestAndRecovery, original)
        XCTAssertLessThanOrEqual(prepared.requestAndRecovery.count, 1_500_000)
        XCTAssertEqual(UIImage(data: prepared.previewAndCover)?.cgImage?.width, 800)
    }

    @MainActor func testRealVisionReadsSampleScreenshotWellInsideDeadline() async throws {
        let original = try XCTUnwrap(AddRecipeSheet.sampleImage())
        let image = AddRecipeSheet.prepareImage(original).requestAndRecovery
        let started = Date()
        let text = try await OnDeviceBackend.ocr(dataURL: "data:image/jpeg;base64," + image.base64EncodedString())
        let elapsed = Date().timeIntervalSince(started)
        let timing = "OCR_TIMING sample pixels=800x600 seconds=\(elapsed)"
        print(timing)
        let evidence = XCTAttachment(string: timing)
        evidence.name = "OCR_TIMING-sample"
        evidence.lifetime = .keepAlways
        add(evidence)
        // Only bundled synthetic recipe fixtures reach this test, never user images.
        let recognized = XCTAttachment(string: text)
        recognized.name = evidence.name + "-recognized-text"
        recognized.lifetime = .keepAlways
        add(recognized)
        XCTAssertLessThan(elapsed, OnDeviceBackend.ocrDeadlineSeconds * 0.8,
                          "Sample OCR must finish well inside the terminal deadline")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Pancakes"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("200 g flour"), "Recognized fixture text: \(text)")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("2 eggs"))
    }

    @MainActor func testRealVisionReadsTallRecipeScreenshotWellInsideDeadline() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 1170, height: 2532), format: format).pngData { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1170, height: 2532))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28), .foregroundColor: UIColor.black
            ]
            let lines = ["Pancakes", "Ingredients", "200 g flour", "2 eggs", "250 ml milk",
                         "Method", "Mix flour, eggs and milk.", "Cook for 2 minutes."]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 40, y: 150 + index * 240), withAttributes: attributes)
            }
        }
        let image = AddRecipeSheet.prepareImage(original).requestAndRecovery
        let pixels = try XCTUnwrap(UIImage(data: image)?.cgImage)
        let started = Date()
        let text = try await OnDeviceBackend.ocr(dataURL: "data:image/jpeg;base64," + image.base64EncodedString())
        let elapsed = Date().timeIntervalSince(started)
        let timing = "OCR_TIMING tall pixels=\(pixels.width)x\(pixels.height) seconds=\(elapsed)"
        print(timing)
        let evidence = XCTAttachment(string: timing)
        evidence.name = "OCR_TIMING-tall"
        evidence.lifetime = .keepAlways
        add(evidence)
        // Only bundled synthetic recipe fixtures reach this test, never user images.
        let recognized = XCTAttachment(string: text)
        recognized.name = evidence.name + "-recognized-text"
        recognized.lifetime = .keepAlways
        add(recognized)
        XCTAssertLessThan(elapsed, OnDeviceBackend.ocrDeadlineSeconds * 0.8,
                          "Tall screenshot OCR must finish well inside the terminal deadline")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Pancakes"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("200 g flour"), "Recognized fixture text: \(text)")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("2 eggs"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Cook for 2 minutes"))
    }

}
