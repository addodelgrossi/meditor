import Foundation
import SwiftUI

@MainActor
struct MermaidTemplate: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let source: String

    static let all: [MermaidTemplate] = [
        .init(
            id: "flowchart",
            title: "Flowchart",
            subtitle: "Map a clear process",
            systemImage: "point.3.connected.trianglepath.dotted",
            source: """
            flowchart LR
                Idea([Idea]) --> Draft[Draft]
                Draft --> Review{Ready?}
                Review -- Yes --> Ship([Ship])
                Review -- Not yet --> Draft
            """
        ),
        .init(
            id: "sequence",
            title: "Sequence",
            subtitle: "Explain an interaction",
            systemImage: "arrow.left.arrow.right",
            source: """
            sequenceDiagram
                participant User
                participant Meditor
                User->>Meditor: Write Mermaid
                Meditor-->>User: Show live preview
            """
        ),
        .init(
            id: "class",
            title: "Class",
            subtitle: "Describe a domain model",
            systemImage: "square.3.layers.3d",
            source: """
            classDiagram
                Document <|-- MermaidDocument
                MermaidDocument : +String text
                MermaidDocument : +render()
            """
        ),
        .init(
            id: "state",
            title: "State",
            subtitle: "Visualize lifecycle",
            systemImage: "circle.hexagongrid",
            source: """
            stateDiagram-v2
                [*] --> Editing
                Editing --> Validating
                Validating --> Preview: valid
                Validating --> Editing: error
            """
        ),
        .init(
            id: "er",
            title: "Entity relationship",
            subtitle: "Model connected data",
            systemImage: "cylinder.split.1x2",
            source: """
            erDiagram
                PROJECT ||--o{ DIAGRAM : contains
                DIAGRAM ||--o{ EXPORT : creates
                PROJECT {
                    string name
                }
            """
        ),
        .init(
            id: "gantt",
            title: "Gantt",
            subtitle: "Plan work over time",
            systemImage: "calendar",
            source: """
            gantt
                title Meditor launch
                dateFormat YYYY-MM-DD
                section Build
                Editor :done, 2026-06-01, 5d
                Preview :active, 2026-06-06, 4d
                Polish :2026-06-10, 3d
            """
        ),
        .init(
            id: "mindmap",
            title: "Mindmap",
            subtitle: "Explore an idea",
            systemImage: "brain.head.profile",
            source: """
            mindmap
              root((Meditor))
                Native
                  Files
                  Keyboard
                Focused
                  Code
                  Preview
                Beautiful
                  Glass
                  Themes
            """
        ),
        .init(
            id: "architecture",
            title: "Architecture",
            subtitle: "Show a system",
            systemImage: "building.2",
            source: """
            architecture-beta
                group app(cloud)[Meditor]
                service editor(server)[Editor] in app
                service renderer(server)[Renderer] in app
                service file(disk)[Document] in app
                editor:R -- L:renderer
                editor:B -- T:file
            """
        )
    ]
}
