//
//  EdgeSwipeBack.swift
//  WorseFiles
//
//  The browser keeps its own directory model instead of pushing a
//  NavigationStack destination per folder. That removes the system
//  interactive-pop gesture, so install an edge recognizer whose action is
//  "go to the parent", not "pop to Home".
//

import SwiftUI
import UIKit

struct EdgeSwipeBack: UIViewControllerRepresentable {
    let onSwipe: () -> Void

    func makeUIViewController(context: Context) -> EdgeSwipeController {
        let controller = EdgeSwipeController()
        controller.onSwipe = onSwipe
        return controller
    }

    func updateUIViewController(_ controller: EdgeSwipeController, context: Context) {
        controller.onSwipe = onSwipe
    }
}

final class EdgeSwipeController: UIViewController, UIGestureRecognizerDelegate {
    var onSwipe: (() -> Void)?

    private var edgePan: UIScreenEdgePanGestureRecognizer?
    private weak var disabledPopGesture: UIGestureRecognizer?
    private var popWasEnabled = true

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        install()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        install()
    }

    override func viewWillDisappear(_ animated: Bool) {
        remove()
        super.viewWillDisappear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        remove()
    }

    private func install() {
        guard edgePan == nil, let window = view.window else { return }

        let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
        pan.edges = .left
        pan.cancelsTouchesInView = false
        pan.delegate = self
        window.addGestureRecognizer(pan)
        edgePan = pan

        // Do not let the hidden navigation back button turn the same edge
        // swipe into a pop all the way back to Home.
        if let navigation = navigationControllerInWindow() {
            if let pop = navigation.interactivePopGestureRecognizer, pop.isEnabled {
                popWasEnabled = true
                pop.isEnabled = false
                disabledPopGesture = pop
            }
        }
    }

    private func remove() {
        if let edgePan {
            edgePan.view?.removeGestureRecognizer(edgePan)
        }
        edgePan = nil
        if let pop = disabledPopGesture {
            pop.isEnabled = popWasEnabled
            disabledPopGesture = nil
        }
    }

    @objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let translation = gesture.translation(in: gesture.view)
        let velocity = gesture.velocity(in: gesture.view)

        let travelled = translation.x > 60 || velocity.x > 300
        let horizontal = abs(translation.y) < max(80, abs(translation.x))
        guard travelled, horizontal else { return }
        onSwipe?()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    private func navigationControllerInWindow() -> UINavigationController? {
        var controller: UIViewController? = self
        while let current = controller {
            if let navigation = current.navigationController { return navigation }
            controller = current.parent
        }

        guard let root = view.window?.rootViewController else { return nil }
        return findNavigationController(from: root)
    }

    private func findNavigationController(from controller: UIViewController?) -> UINavigationController? {
        guard let controller else { return nil }
        if let navigation = controller as? UINavigationController { return navigation }
        for child in controller.children {
            if let navigation = findNavigationController(from: child) { return navigation }
        }
        return nil
    }
}
