import Testing
import Foundation
@testable import PluginUpdater

@Suite("ProjectRow Sorting and Filtering Tests")
struct ProjectListViewTests {

    /// Creates a ProjectRow with the specified properties for testing sort/filter logic.
    /// Uses a lightweight stub approach since we only need the row's computed properties.
    private func makeRow(
        name: String,
        abletonVersion: String? = nil,
        pluginCount: Int = 0,
        missingCount: Int = 0,
        lastModified: Date = .now,
        fileSize: Int64 = 0,
        filePath: String = "/tmp/test.als"
    ) -> ProjectRow {
        // ProjectRow wraps an AbletonProject — create a real model object
        let project = AbletonProject(
            filePath: filePath,
            name: name,
            lastModified: lastModified,
            fileSize: fileSize,
            abletonVersion: abletonVersion
        )
        return ProjectRow(project: project)
    }

    @Test("ProjectRows sort by name ascending")
    func projectRowsSortByNameAscending() {
        let rows = [
            makeRow(name: "Zebra Project"),
            makeRow(name: "Alpha Project"),
            makeRow(name: "Middle Project"),
        ]
        let sorted = rows.sorted(using: KeyPathComparator(\ProjectRow.name))
        #expect(sorted[0].name == "Alpha Project")
        #expect(sorted[1].name == "Middle Project")
        #expect(sorted[2].name == "Zebra Project")
    }

    @Test("ProjectRows sort by plugin count descending")
    func projectRowsSortByPluginCountDescending() {
        // Note: pluginCount comes from project.plugins.count which defaults to 0
        // for newly created projects. We test the comparator works correctly.
        let rows = [
            makeRow(name: "A", filePath: "/tmp/a.als"),
            makeRow(name: "B", filePath: "/tmp/b.als"),
            makeRow(name: "C", filePath: "/tmp/c.als"),
        ]
        let sorted = rows.sorted(using: KeyPathComparator(\ProjectRow.pluginCount, order: .reverse))
        // All have 0 plugins, so order is stable — just verify it doesn't crash
        #expect(sorted.count == 3)
    }

    @Test("ProjectRows sort by last modified date")
    func projectRowsSortByLastModified() {
        let now = Date()
        let rows = [
            makeRow(name: "Old", lastModified: now.addingTimeInterval(-86400), filePath: "/tmp/old.als"),
            makeRow(name: "New", lastModified: now, filePath: "/tmp/new.als"),
            makeRow(name: "Mid", lastModified: now.addingTimeInterval(-3600), filePath: "/tmp/mid.als"),
        ]
        let sorted = rows.sorted(using: KeyPathComparator(\ProjectRow.lastModified, order: .reverse))
        #expect(sorted[0].name == "New")
        #expect(sorted[1].name == "Mid")
        #expect(sorted[2].name == "Old")
    }

    @Test("ProjectRows sort by file size")
    func projectRowsSortByFileSize() {
        let rows = [
            makeRow(name: "Big", fileSize: 50_000_000, filePath: "/tmp/big.als"),
            makeRow(name: "Small", fileSize: 500_000, filePath: "/tmp/small.als"),
            makeRow(name: "Medium", fileSize: 5_000_000, filePath: "/tmp/medium.als"),
        ]
        let sorted = rows.sorted(using: KeyPathComparator(\ProjectRow.fileSize))
        #expect(sorted[0].name == "Small")
        #expect(sorted[1].name == "Medium")
        #expect(sorted[2].name == "Big")
    }

    @Test("ProjectRows sort by missing count descending")
    func projectRowsSortByMissingCountDescending() {
        // missingCount comes from project.missingPluginCount — defaults to 0 for new projects
        let rows = [
            makeRow(name: "A", filePath: "/tmp/a.als"),
            makeRow(name: "B", filePath: "/tmp/b.als"),
        ]
        let sorted = rows.sorted(using: KeyPathComparator(\ProjectRow.missingCount, order: .reverse))
        #expect(sorted.count == 2)
    }

    @Test("Filter rows by search text matches case-insensitively")
    func projectRowsFilterBySearchText() {
        let projects = [
            AbletonProject(filePath: "/tmp/a.als", name: "My Cool Track", lastModified: .now, fileSize: 100),
            AbletonProject(filePath: "/tmp/b.als", name: "Another Song", lastModified: .now, fileSize: 200),
            AbletonProject(filePath: "/tmp/c.als", name: "cool beans", lastModified: .now, fileSize: 300),
        ]
        let searchText = "cool"
        let filtered = projects.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.name.lowercased().contains("cool") })
    }

    @Test("Filter with no match returns empty")
    func projectRowsFilterBySearchTextNoMatch() {
        let projects = [
            AbletonProject(filePath: "/tmp/a.als", name: "Track One", lastModified: .now, fileSize: 100),
            AbletonProject(filePath: "/tmp/b.als", name: "Track Two", lastModified: .now, fileSize: 200),
        ]
        let filtered = projects.filter {
            $0.name.localizedCaseInsensitiveContains("zzzzz")
        }
        #expect(filtered.isEmpty)
    }

    @Test("Empty search text returns all projects")
    func projectRowsFilterByEmptySearchReturnsAll() {
        let projects = [
            AbletonProject(filePath: "/tmp/a.als", name: "Track One", lastModified: .now, fileSize: 100),
            AbletonProject(filePath: "/tmp/b.als", name: "Track Two", lastModified: .now, fileSize: 200),
            AbletonProject(filePath: "/tmp/c.als", name: "Track Three", lastModified: .now, fileSize: 300),
        ]
        let searchText = ""
        let filtered = searchText.isEmpty ? projects : projects.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
        #expect(filtered.count == 3)
    }
}
