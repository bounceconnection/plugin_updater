import Testing
import Foundation
@testable import PluginUpdater

@Suite("AbletonProjectParser Tests")
struct AbletonProjectParserTests {

    /// Creates a minimal gzip-compressed .als fixture from raw XML.
    private func makeALSFixture(xml: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ALSTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let alsURL = tempDir.appendingPathComponent("test.als")
        let inputURL = tempDir.appendingPathComponent("test.xml")
        try xml.data(using: .utf8)!.write(to: inputURL)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        proc.arguments = ["-c", inputURL.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        let gzData = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        try gzData.write(to: alsURL)
        return alsURL
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("Parses Ableton version from root element")
    func parsesAbletonVersion() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton MajorVersion="5" MinorVersion="12.1.5" Creator="Ableton Live 12.1.5">
        </Ableton>
        """
        let url = try makeALSFixture(xml: xml)
        defer { cleanup(url) }
        let parser = AbletonProjectParser()
        let project = try await parser.parse(fileURL: url)
        #expect(project.abletonVersion == "Ableton Live 12.1.5")
        #expect(project.plugins.isEmpty)
    }

    @Test("Parses AU plugin with component codes")
    func parsesAUPlugin() async throws {
        // ComponentType 'aufx' = 1635083896, SubType 'PrL2' = 1349667890, Manufacturer 'FbFl' = 1180845676
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton Creator="Ableton Live 12.1.5">
          <LiveSet>
            <Tracks>
              <AudioTrack>
                <DeviceChain>
                  <PluginDevice>
                    <AuPluginInfo>
                      <Name Value="Pro-L 2"/>
                      <Manufacturer Value="FabFilter"/>
                      <ComponentType Value="1635083896"/>
                      <ComponentSubType Value="1349667890"/>
                      <ComponentManufacturer Value="1180845676"/>
                    </AuPluginInfo>
                  </PluginDevice>
                </DeviceChain>
              </AudioTrack>
            </Tracks>
          </LiveSet>
        </Ableton>
        """
        let url = try makeALSFixture(xml: xml)
        defer { cleanup(url) }
        let parser = AbletonProjectParser()
        let project = try await parser.parse(fileURL: url)
        #expect(project.plugins.count == 1)
        let plugin = project.plugins[0]
        #expect(plugin.pluginName == "Pro-L 2")
        #expect(plugin.pluginType == "au")
        #expect(plugin.vendorName == "FabFilter")
        #expect(plugin.auComponentType == "aufx")
        #expect(plugin.auComponentSubType == "PrL2")
        #expect(plugin.auComponentManufacturer == "FbFl")
    }

    @Test("AU parser ignores nested preset Name elements")
    func parsesAUPluginIgnoresNestedPreset() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton Creator="Ableton Live 12.1.5">
          <LiveSet>
            <Tracks>
              <AudioTrack>
                <DeviceChain>
                  <PluginDevice>
                    <AuPluginInfo>
                      <Name Value="Real Name"/>
                      <Manufacturer Value="TestVendor"/>
                      <ComponentType Value="1635085685"/>
                      <ComponentSubType Value="1349480050"/>
                      <ComponentManufacturer Value="1178683442"/>
                      <Preset>
                        <AuPreset>
                          <Name Value="Default"/>
                        </AuPreset>
                      </Preset>
                    </AuPluginInfo>
                  </PluginDevice>
                </DeviceChain>
              </AudioTrack>
            </Tracks>
          </LiveSet>
        </Ableton>
        """
        let url = try makeALSFixture(xml: xml)
        defer { cleanup(url) }
        let parser = AbletonProjectParser()
        let project = try await parser.parse(fileURL: url)
        #expect(project.plugins.count == 1)
        #expect(project.plugins[0].pluginName == "Real Name")
    }

    @Test("Parses VST3 plugin with TUID")
    func parsesVST3Plugin() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton Creator="Ableton Live 12.1.5">
          <LiveSet>
            <Tracks>
              <AudioTrack>
                <DeviceChain>
                  <PluginDevice>
                    <Vst3PluginInfo>
                      <Name Value="Serum"/>
                      <Uid>
                        <Fields.0 Value="1397572658"/>
                        <Fields.1 Value="1400266862"/>
                        <Fields.2 Value="862218066"/>
                        <Fields.3 Value="0"/>
                      </Uid>
                    </Vst3PluginInfo>
                  </PluginDevice>
                </DeviceChain>
              </AudioTrack>
            </Tracks>
          </LiveSet>
        </Ableton>
        """
        let url = try makeALSFixture(xml: xml)
        defer { cleanup(url) }
        let parser = AbletonProjectParser()
        let project = try await parser.parse(fileURL: url)
        #expect(project.plugins.count == 1)
        let plugin = project.plugins[0]
        #expect(plugin.pluginName == "Serum")
        #expect(plugin.pluginType == "vst3")
        #expect(plugin.vst3TUID != nil)
    }

    @Test("VST3 parser ignores nested preset Name elements")
    func parsesVST3PluginIgnoresNestedPreset() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton Creator="Ableton Live 12.1.5">
          <LiveSet>
            <Tracks>
              <AudioTrack>
                <DeviceChain>
                  <PluginDevice>
                    <Vst3PluginInfo>
                      <Name Value="Real VST3 Name"/>
                      <Uid>
                        <Fields.0 Value="100"/>
                        <Fields.1 Value="200"/>
                        <Fields.2 Value="300"/>
                        <Fields.3 Value="400"/>
                      </Uid>
                      <Preset>
                        <Vst3Preset>
                          <Name Value=""/>
                        </Vst3Preset>
                      </Preset>
                    </Vst3PluginInfo>
                  </PluginDevice>
                </DeviceChain>
              </AudioTrack>
            </Tracks>
          </LiveSet>
        </Ableton>
        """
        let url = try makeALSFixture(xml: xml)
        defer { cleanup(url) }
        let parser = AbletonProjectParser()
        let project = try await parser.parse(fileURL: url)
        #expect(project.plugins.count == 1)
        #expect(project.plugins[0].pluginName == "Real VST3 Name")
    }

    @Test("Parses VST3 plugin with negative TUID fields")
    func parsesVST3PluginWithNegativeTUID() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton Creator="Ableton Live 12.1.5">
          <LiveSet>
            <Tracks>
              <AudioTrack>
                <DeviceChain>
                  <PluginDevice>
                    <Vst3PluginInfo>
                      <Name Value="NegTest"/>
                      <Uid>
                        <Fields.0 Value="-1"/>
                        <Fields.1 Value="0"/>
                        <Fields.2 Value="-2147483648"/>
                        <Fields.3 Value="1"/>
                      </Uid>
                    </Vst3PluginInfo>
                  </PluginDevice>
                </DeviceChain>
              </AudioTrack>
            </Tracks>
          </LiveSet>
        </Ableton>
        """
        let url = try makeALSFixture(xml: xml)
        defer { cleanup(url) }
        let parser = AbletonProjectParser()
        let project = try await parser.parse(fileURL: url)
        #expect(project.plugins.count == 1)
        // -1 as UInt32 = 0xFFFFFFFF, -2147483648 = 0x80000000
        #expect(project.plugins[0].vst3TUID == "FFFFFFFF000000008000000000000001")
    }

    @Test("Parses VST2 plugin")
    func parsesVST2Plugin() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton Creator="Ableton Live 12.1.5">
          <LiveSet>
            <Tracks>
              <AudioTrack>
                <DeviceChain>
                  <PluginDevice>
                    <VstPluginInfo>
                      <PlugName Value="Sylenth1"/>
                    </VstPluginInfo>
                  </PluginDevice>
                </DeviceChain>
              </AudioTrack>
            </Tracks>
          </LiveSet>
        </Ableton>
        """
        let url = try makeALSFixture(xml: xml)
        defer { cleanup(url) }
        let parser = AbletonProjectParser()
        let project = try await parser.parse(fileURL: url)
        #expect(project.plugins.count == 1)
        #expect(project.plugins[0].pluginName == "Sylenth1")
        #expect(project.plugins[0].pluginType == "vst2")
    }

    @Test("Deduplicates plugins within a project")
    func deduplicatesPluginsWithinProject() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton Creator="Ableton Live 12.1.5">
          <LiveSet>
            <Tracks>
              <AudioTrack>
                <DeviceChain>
                  <PluginDevice>
                    <AuPluginInfo>
                      <Name Value="Pro-L 2"/>
                      <Manufacturer Value="FabFilter"/>
                      <ComponentType Value="1635085685"/>
                      <ComponentSubType Value="1349480050"/>
                      <ComponentManufacturer Value="1178683442"/>
                    </AuPluginInfo>
                  </PluginDevice>
                </DeviceChain>
              </AudioTrack>
              <AudioTrack>
                <DeviceChain>
                  <PluginDevice>
                    <AuPluginInfo>
                      <Name Value="Pro-L 2"/>
                      <Manufacturer Value="FabFilter"/>
                      <ComponentType Value="1635085685"/>
                      <ComponentSubType Value="1349480050"/>
                      <ComponentManufacturer Value="1178683442"/>
                    </AuPluginInfo>
                  </PluginDevice>
                </DeviceChain>
              </AudioTrack>
              <AudioTrack>
                <DeviceChain>
                  <PluginDevice>
                    <AuPluginInfo>
                      <Name Value="Pro-L 2"/>
                      <Manufacturer Value="FabFilter"/>
                      <ComponentType Value="1635085685"/>
                      <ComponentSubType Value="1349480050"/>
                      <ComponentManufacturer Value="1178683442"/>
                    </AuPluginInfo>
                  </PluginDevice>
                </DeviceChain>
              </AudioTrack>
            </Tracks>
          </LiveSet>
        </Ableton>
        """
        let url = try makeALSFixture(xml: xml)
        defer { cleanup(url) }
        let parser = AbletonProjectParser()
        let project = try await parser.parse(fileURL: url)
        #expect(project.plugins.count == 1)
    }

    @Test("Parses empty project with no plugins")
    func parsesEmptyProject() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton Creator="Ableton Live 12.1.5">
          <LiveSet>
            <Tracks/>
          </LiveSet>
        </Ableton>
        """
        let url = try makeALSFixture(xml: xml)
        defer { cleanup(url) }
        let parser = AbletonProjectParser()
        let project = try await parser.parse(fileURL: url)
        #expect(project.plugins.isEmpty)
        #expect(project.abletonVersion == "Ableton Live 12.1.5")
    }

    @Test("Parses plain (non-gzipped) XML input")
    func parsesPlainXML() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton Creator="Ableton Live 11.0">
          <LiveSet>
            <Tracks>
              <AudioTrack>
                <DeviceChain>
                  <PluginDevice>
                    <VstPluginInfo>
                      <PlugName Value="TestPlug"/>
                    </VstPluginInfo>
                  </PluginDevice>
                </DeviceChain>
              </AudioTrack>
            </Tracks>
          </LiveSet>
        </Ableton>
        """
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ALSTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let alsURL = tempDir.appendingPathComponent("test.als")
        try xml.data(using: .utf8)!.write(to: alsURL)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let parser = AbletonProjectParser()
        let project = try await parser.parse(fileURL: alsURL)
        #expect(project.plugins.count == 1)
        #expect(project.plugins[0].pluginName == "TestPlug")
    }
}
