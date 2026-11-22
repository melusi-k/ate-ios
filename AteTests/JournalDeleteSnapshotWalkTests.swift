import XCTest

/// This target compiles the exact UI traversal helper, not a copied algorithm.
final class JournalDeleteSnapshotWalkTests: XCTestCase {
    private struct Node: Equatable {
        var name: String
        var button = true
        var identifier = "journal.delete.cancel"
        var label = "Cancel"
        var enabled = true
        var frame = [57, 473, 140, 48]
        var children: [Node] = []
    }

    private func buttons(_ root: Node) -> [Node] {
        JournalDeleteSnapshotWalk.descendants(of: root, children: { $0.children }, matching: { $0.button })
    }

    func testTerminalButtonHasNoDescendants() {
        XCTAssertEqual(buttons(Node(name: "leaf")), [])
    }

    func testNestedAliasesRetainBothNodesAndOneTerminalDecision() {
        let leaf = Node(name: "leaf")
        let alias = Node(name: "alias", children: [leaf])
        let nodes = buttons(Node(name: "alert", button: false, children: [alias]))
        XCTAssertEqual(nodes, [alias, leaf])
        XCTAssertEqual(nodes.filter { buttons($0).isEmpty }, [leaf])
    }

    func testEqualFrameSiblingActionsRemainTwoLeaves() {
        let first = Node(name: "first")
        let second = Node(name: "second")
        let nodes = buttons(Node(name: "alert", button: false, children: [first, second]))
        XCTAssertEqual(nodes, [first, second])
        XCTAssertEqual(nodes.filter { buttons($0).isEmpty }.count, 2,
                       "Same-frame siblings must still fail the UI's one-leaf assertion")
    }

    func testDifferentIdentifierDescendantIsNotFiltered() {
        let other = Node(name: "other", identifier: "journal.delete.confirm", label: "Delete")
        let descendants = buttons(Node(name: "alias", children: [other]))
        XCTAssertEqual(descendants, [other])
        XCTAssertNotEqual(descendants.count, descendants.filter { $0.identifier == "journal.delete.cancel" }.count,
                          "A foreign decision must still fail the UI's identity assertion")
    }

    func testButtonsUnderNonbuttonContainersRemainReachable() {
        let leaf = Node(name: "leaf")
        let nested = Node(name: "container", button: false, children: [
            Node(name: "inner", button: false, children: [leaf])])
        XCTAssertEqual(buttons(Node(name: "root", button: false, children: [nested])), [leaf])
    }

    func testMismatchedLabelsDisabledAliasesAndFramesStayVisible() {
        let wrongLabel = Node(name: "wrong label", label: "Delete")
        let disabled = Node(name: "disabled", enabled: false)
        let shifted = Node(name: "shifted", frame: [58, 473, 140, 48])
        let nodes = buttons(Node(name: "root", button: false, children: [wrongLabel, disabled, shifted]))
        XCTAssertEqual(nodes, [wrongLabel, disabled, shifted],
                       "Invalid metadata must reach the unchanged UI assertions")
    }
}
