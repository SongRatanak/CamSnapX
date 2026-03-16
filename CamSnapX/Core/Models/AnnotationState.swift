//
//  AnnotationState.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import AppKit
import Combine

final class AnnotationState: ObservableObject {
    @Published var selectedTool: AnnotationTool = AnnotationState.loadLastTool() {
        didSet {
            AnnotationState.saveLastTool(selectedTool)
        }
    }
    @Published var selectedColor: NSColor = .systemRed
    @Published var lineWidth: CGFloat = 3.0
    @Published var arrowStyle: ArrowAnnotationStyle = .standard
    @Published var fontSize: CGFloat = 20.0
    @Published var textStyle: TextAnnotationStyle = .standard
    @Published var annotations: [Annotation] = []
    @Published var activeAnnotation: Annotation?
    @Published var selectedAnnotationID: UUID?

    private static let lastToolKey = "annotation.lastSelectedTool"

    // Callback to notify canvas of state changes
    var onStateChanged: (() -> Void)?

    func beginAnnotation(_ annotation: Annotation) {
        activeAnnotation = annotation
        onStateChanged?()
    }

    func updateActiveAnnotation(_ annotation: Annotation) {
        activeAnnotation = annotation
        onStateChanged?()
    }

    func commitActiveAnnotation() {
        guard var annotation = activeAnnotation else { return }
        annotation.isComplete = true
        annotations.append(annotation)
        activeAnnotation = nil
        onStateChanged?()
    }

    func addAnnotation(_ annotation: Annotation) {
        var completed = annotation
        completed.isComplete = true
        annotations.append(completed)
        activeAnnotation = nil
        onStateChanged?()
    }

    func undoLast() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        onStateChanged?()
    }

    func clearAll() {
        annotations.removeAll()
        activeAnnotation = nil
        onStateChanged?()
    }

    private static func loadLastTool() -> AnnotationTool {
        let rawValue = UserDefaults.standard.string(forKey: lastToolKey)
        return rawValue.flatMap(AnnotationTool.init(rawValue:)) ?? .arrow
    }

    private static func saveLastTool(_ tool: AnnotationTool) {
        UserDefaults.standard.set(tool.rawValue, forKey: lastToolKey)
    }
}
