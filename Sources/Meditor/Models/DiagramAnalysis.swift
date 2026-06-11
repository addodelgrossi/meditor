import Foundation

enum DiagramOutlineKind: String, Codable, Hashable {
    case node
    case subgraph
    case participant
    case actor
    case `class`
    case state
    case entity
    case mindmapNode
    case group
    case service
    case junction

    var systemImage: String {
        switch self {
        case .node: "square"
        case .subgraph, .group: "square.3.layers.3d"
        case .participant: "person.crop.rectangle"
        case .actor: "person"
        case .class: "shippingbox"
        case .state: "circle"
        case .entity: "cylinder"
        case .mindmapNode: "point.3.connected.trianglepath.dotted"
        case .service: "server.rack"
        case .junction: "circle.hexagongrid"
        }
    }

    var canRename: Bool {
        self == .node || self == .participant || self == .actor
    }
}

struct DiagramOutlineItem: Codable, Hashable, Identifiable {
    let id: String
    let identifier: String?
    let title: String
    let kind: DiagramOutlineKind
    var children: [DiagramOutlineItem]
    var line: Int?

    var optionalChildren: [DiagramOutlineItem]? {
        children.isEmpty ? nil : children
    }
}

struct DiagramConnection: Codable, Hashable, Identifiable {
    let id: String
    let from: String
    let to: String
    let label: String?
}

struct DiagramIssue: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, Hashable {
        case duplicateIdentifier
        case disconnectedElement
    }

    let id: String
    let kind: Kind
    let message: String
    let line: Int?
}

struct DiagramAnalysis: Codable, Equatable {
    let diagramType: String
    let elementCount: Int?
    let connectionCount: Int?
    var outline: [DiagramOutlineItem]
    let connections: [DiagramConnection]
    var issues: [DiagramIssue]

    var allOutlineItems: [DiagramOutlineItem] {
        outline.flatMap(\.flattened)
    }

    func item(id: String) -> DiagramOutlineItem? {
        allOutlineItems.first { $0.id == id }
    }
}

private extension DiagramOutlineItem {
    var flattened: [DiagramOutlineItem] {
        [self] + children.flatMap(\.flattened)
    }
}

struct DiagramRenderResult: Equatable {
    let svg: String
    let analysis: DiagramAnalysis?
}

