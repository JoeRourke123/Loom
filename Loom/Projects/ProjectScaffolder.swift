import Foundation

enum ProjectScaffolder {
    static func scaffold(into folderURL: URL, projectName: String) throws {
        let mainTS = """
import { loom } from '@loom/core';

export default loom(async (ctx) => {
  console.log('Hello from Loom!');
}, {
  name: '\(projectName)',
  description: 'A new Loom script.',
});
"""
        let mainURL = folderURL.appendingPathComponent("main.ts")
        try mainTS.write(to: mainURL, atomically: true, encoding: .utf8)
    }

    static func widgetTemplate(projectName: String) -> String {
        """
import { w } from '@loom/widget';

export const small = (ctx) => w.vstack([
  w.text('\(projectName)', { font: 'headline' }),
  w.text('Small widget', { font: 'caption', color: 'secondary' }),
]);

export const medium = (ctx) => w.hstack([
  w.icon('bolt.fill', { color: 'accent', size: 28 }),
  w.vstack([
    w.text('\(projectName)', { font: 'title3' }),
    w.text('Medium widget', { font: 'caption', color: 'secondary' }),
  ]),
]);
"""
    }

    static func emptyTemplate(fileName: String) -> String {
        "// \(fileName)\n"
    }

    static func scaffold(into folderURL: URL, projectName: String, template: ProjectTemplate) throws {
        let mainURL = folderURL.appendingPathComponent("main.ts")
        try template.mainTS.write(to: mainURL, atomically: true, encoding: .utf8)
        let widgetURL = folderURL.appendingPathComponent("widget.ts")
        try template.widgetTS.write(to: widgetURL, atomically: true, encoding: .utf8)
    }

    @discardableResult
    static func createFile(named name: String, in project: LoomProject) throws -> URL {
        let url = project.folderURL.appendingPathComponent(name)
        let content: String
        if name == "widget.ts" {
            content = widgetTemplate(projectName: project.name)
        } else {
            content = emptyTemplate(fileName: name)
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
