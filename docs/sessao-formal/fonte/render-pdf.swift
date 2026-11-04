// Renders an HTML file to a paginated A4 PDF through WebKit.
//
// Usage: render-pdf <input.html> <output.pdf>
//
// Built for the formal-session documents: each one is written as a small HTML file so that its
// wording is easy to edit, and this turns it into the PDF that goes to the participant. Runs
// without opening a visible window.
import AppKit
import PDFKit
import WebKit

final class Renderer: NSObject, WKNavigationDelegate {
    private let input: URL
    private let output: URL
    private let window: NSWindow
    private let web: WKWebView

    init(input: URL, output: URL) {
        self.input = input
        self.output = output

        let frame = NSRect(x: 0, y: 0, width: 595, height: 842)
        web = WKWebView(frame: frame)
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = web

        super.init()
        web.navigationDelegate = self
    }

    func start() {
        web.loadFileURL(input, allowingReadAccessTo: input.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Gives layout a moment to settle before paginating.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.print() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("load failed: \(error.localizedDescription)")
    }

    private func print() {
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595, height: 842)
        info.topMargin = 56
        info.bottomMargin = 56
        info.leftMargin = 56
        info.rightMargin = 56
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output

        let operation = web.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = NSRect(x: 0, y: 0, width: 483, height: 730)

        operation.runModal(
            for: window,
            delegate: self,
            didRun: #selector(printDidRun(_:success:contextInfo:)),
            contextInfo: nil
        )
    }

    @objc func printDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if success {
            stampTitle()
            exit(0)
        } else {
            fail("print operation failed")
        }
    }

    /// Writes the page title into the PDF's metadata.
    ///
    /// A screen reader announces that title when the file opens; without it the listener hears
    /// the file name instead.
    private func stampTitle() {
        guard let title = web.title, !title.isEmpty,
              let document = PDFDocument(url: output)
        else { return }

        var attributes = document.documentAttributes ?? [:]
        attributes[PDFDocumentAttribute.titleAttribute] = title
        document.documentAttributes = attributes
        document.write(to: output)
    }

    private func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("render-pdf: \(message)\n".utf8))
        exit(1)
    }
}

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: render-pdf <input.html> <output.pdf>\n".utf8))
    exit(2)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let renderer = Renderer(
    input: URL(fileURLWithPath: CommandLine.arguments[1]),
    output: URL(fileURLWithPath: CommandLine.arguments[2])
)
renderer.start()

DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
    FileHandle.standardError.write(Data("render-pdf: timed out\n".utf8))
    exit(3)
}

app.run()
