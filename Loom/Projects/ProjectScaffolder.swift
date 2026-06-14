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
}
