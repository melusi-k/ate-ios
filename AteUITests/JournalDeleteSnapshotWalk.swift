/// Walk only captured values, never evaluate a query under an indexed AX alias.
/// The root is excluded, just like XCUIElement.descendants(matching:).
/// No identity, label, enabled state or frame is used to hide or merge nodes.
enum JournalDeleteSnapshotWalk {
    static func descendants<Node>(of root: Node, children: (Node) -> [Node],
                                  matching: (Node) -> Bool) -> [Node] {
        var result: [Node] = []
        func visit(_ node: Node) {
            for child in children(node) {
                if matching(child) { result.append(child) }
                visit(child)
            }
        }
        visit(root)
        return result
    }
}
